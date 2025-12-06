package decrypt

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"encoding/binary"
	"fmt"
	"hash"
	"io"
	"os"
)

const (
	KeySize      = 32
	SaltSize     = 16
	AESBlockSize = 16
	SQLiteHeader = "SQLite format 3\x00"
	IVSize       = 16
)

// DBFile 数据库文件信息
type DBFile struct {
	Path       string
	Salt       []byte
	TotalPages int64
	FirstPage  []byte
}

// OpenDBFile 打开并读取数据库文件基本信息
func OpenDBFile(dbPath string, pageSize int) (*DBFile, error) {
	fp, err := os.Open(dbPath)
	if err != nil {
		return nil, fmt.Errorf("open file failed: %w", err)
	}
	defer fp.Close()

	fileInfo, err := fp.Stat()
	if err != nil {
		return nil, fmt.Errorf("stat file failed: %w", err)
	}

	fileSize := fileInfo.Size()
	totalPages := fileSize / int64(pageSize)
	if fileSize%int64(pageSize) > 0 {
		totalPages++
	}

	buffer := make([]byte, pageSize)
	n, err := io.ReadFull(fp, buffer)
	if err != nil {
		return nil, fmt.Errorf("read file failed: %w", err)
	}
	if n != pageSize {
		return nil, fmt.Errorf("incomplete read: got %d bytes, expected %d", n, pageSize)
	}

	// 检查是否已经是解密的数据库
	if bytes.Equal(buffer[:len(SQLiteHeader)-1], []byte(SQLiteHeader[:len(SQLiteHeader)-1])) {
		return nil, fmt.Errorf("database already decrypted")
	}

	return &DBFile{
		Path:       dbPath,
		Salt:       buffer[:SaltSize],
		FirstPage:  buffer,
		TotalPages: totalPages,
	}, nil
}

// XorBytes 异或操作
func XorBytes(a []byte, b byte) []byte {
	result := make([]byte, len(a))
	for i := range a {
		result[i] = a[i] ^ b
	}
	return result
}

// ValidateKey 验证密钥是否正确
func ValidateKey(page1 []byte, key []byte, salt []byte, hashFunc func() hash.Hash, hmacSize int, reserve int, pageSize int, deriveKeys func([]byte, []byte) ([]byte, []byte)) bool {
	if len(key) != KeySize {
		return false
	}

	_, macKey := deriveKeys(key, salt)

	mac := hmac.New(hashFunc, macKey)
	dataEnd := pageSize - reserve + IVSize
	mac.Write(page1[SaltSize:dataEnd])

	pageNoBytes := make([]byte, 4)
	binary.LittleEndian.PutUint32(pageNoBytes, 1)
	mac.Write(pageNoBytes)

	calculatedMAC := mac.Sum(nil)
	storedMAC := page1[dataEnd : dataEnd+hmacSize]

	return hmac.Equal(calculatedMAC, storedMAC)
}

// DecryptPage 解密单个数据库页面
func DecryptPage(pageBuf []byte, encKey []byte, macKey []byte, pageNum int64, hashFunc func() hash.Hash, hmacSize int, reserve int, pageSize int) ([]byte, error) {
	offset := 0
	if pageNum == 0 {
		offset = SaltSize
	}

	// 验证 HMAC
	mac := hmac.New(hashFunc, macKey)
	mac.Write(pageBuf[offset : pageSize-reserve+IVSize])

	pageNoBytes := make([]byte, 4)
	binary.LittleEndian.PutUint32(pageNoBytes, uint32(pageNum+1))
	mac.Write(pageNoBytes)

	hashMac := mac.Sum(nil)

	hashMacStartOffset := pageSize - reserve + IVSize
	hashMacEndOffset := hashMacStartOffset + hmacSize

	if !bytes.Equal(hashMac, pageBuf[hashMacStartOffset:hashMacEndOffset]) {
		return nil, fmt.Errorf("HMAC verification failed for page %d", pageNum)
	}

	// 解密页面
	iv := pageBuf[pageSize-reserve : pageSize-reserve+IVSize]
	block, err := aes.NewCipher(encKey)
	if err != nil {
		return nil, fmt.Errorf("create cipher failed: %w", err)
	}

	mode := cipher.NewCBCDecrypter(block, iv)

	encrypted := make([]byte, pageSize-reserve-offset)
	copy(encrypted, pageBuf[offset:pageSize-reserve])

	mode.CryptBlocks(encrypted, encrypted)

	decryptedPage := append(encrypted, pageBuf[pageSize-reserve:pageSize]...)

	return decryptedPage, nil
}
