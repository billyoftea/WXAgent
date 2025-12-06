package decrypt

import (
	"context"
	"crypto/sha512"
	"encoding/hex"
	"fmt"
	"hash"
	"io"
	"os"

	"golang.org/x/crypto/pbkdf2"
)

// V4 版本特定常量
const (
	PageSize       = 4096
	V4IterCount    = 256000
	HmacSHA512Size = 64
)

// Decryptor 定义数据库解密的接口
type Decryptor interface {
	// Decrypt 解密数据库到输出流
	Decrypt(ctx context.Context, dbfile string, hexKey string, output io.Writer) error

	// DecryptToFile 解密数据库到文件
	DecryptToFile(ctx context.Context, dbfile string, hexKey string, outputPath string) error

	// Validate 验证密钥是否有效
	Validate(page1 []byte, key []byte) bool

	// GetPageSize 返回页面大小
	GetPageSize() int

	// GetVersion 返回解密器版本
	GetVersion() string
}

// V4Decryptor 实现Windows V4版本的解密器
type V4Decryptor struct {
	iterCount int
	hmacSize  int
	hashFunc  func() hash.Hash
	reserve   int
	pageSize  int
	version   string
}

// NewV4Decryptor 创建Windows V4解密器
func NewV4Decryptor() *V4Decryptor {
	hashFunc := sha512.New
	hmacSize := HmacSHA512Size
	reserve := IVSize + hmacSize
	if reserve%AESBlockSize != 0 {
		reserve = ((reserve / AESBlockSize) + 1) * AESBlockSize
	}

	return &V4Decryptor{
		iterCount: V4IterCount,
		hmacSize:  hmacSize,
		hashFunc:  hashFunc,
		reserve:   reserve,
		pageSize:  PageSize,
		version:   "Windows v4",
	}
}

// deriveKeys 派生加密密钥和MAC密钥
func (d *V4Decryptor) deriveKeys(key []byte, salt []byte) ([]byte, []byte) {
	// 生成加密密钥
	encKey := pbkdf2.Key(key, salt, d.iterCount, KeySize, d.hashFunc)

	// 生成MAC密钥
	macSalt := XorBytes(salt, 0x3a)
	macKey := pbkdf2.Key(encKey, macSalt, 2, KeySize, d.hashFunc)

	return encKey, macKey
}

// Validate 验证密钥是否有效
func (d *V4Decryptor) Validate(page1 []byte, key []byte) bool {
	if len(page1) < d.pageSize || len(key) != KeySize {
		return false
	}

	salt := page1[:SaltSize]
	return ValidateKey(page1, key, salt, d.hashFunc, d.hmacSize, d.reserve, d.pageSize, d.deriveKeys)
}

// Decrypt 解密数据库
func (d *V4Decryptor) Decrypt(ctx context.Context, dbfile string, hexKey string, output io.Writer) error {
	// 解码密钥
	key, err := hex.DecodeString(hexKey)
	if err != nil {
		return fmt.Errorf("decode key failed: %w", err)
	}

	// 打开数据库文件并读取基本信息
	dbInfo, err := OpenDBFile(dbfile, d.pageSize)
	if err != nil {
		return err
	}

	// 验证密钥
	if !d.Validate(dbInfo.FirstPage, key) {
		return fmt.Errorf("incorrect key")
	}

	// 计算密钥
	encKey, macKey := d.deriveKeys(key, dbInfo.Salt)

	// 打开数据库文件
	dbFile, err := os.Open(dbfile)
	if err != nil {
		return fmt.Errorf("open file failed: %w", err)
	}
	defer dbFile.Close()

	// 写入SQLite头
	_, err = output.Write([]byte(SQLiteHeader))
	if err != nil {
		return fmt.Errorf("write header failed: %w", err)
	}

	// 处理每一页
	pageBuf := make([]byte, d.pageSize)

	for curPage := int64(0); curPage < dbInfo.TotalPages; curPage++ {
		// 检查是否取消
		select {
		case <-ctx.Done():
			return fmt.Errorf("operation canceled")
		default:
			// 继续处理
		}

		// 读取一页
		n, err := io.ReadFull(dbFile, pageBuf)
		if err != nil {
			if err == io.EOF || err == io.ErrUnexpectedEOF {
				// 处理最后一部分页面
				if n > 0 {
					break
				}
			}
			return fmt.Errorf("read page %d failed: %w", curPage, err)
		}

		// 检查页面是否全为零
		allZeros := true
		for _, b := range pageBuf {
			if b != 0 {
				allZeros = false
				break
			}
		}

		if allZeros {
			// 写入零页面
			_, err = output.Write(pageBuf)
			if err != nil {
				return fmt.Errorf("write zero page failed: %w", err)
			}
			continue
		}

		// 解密页面
		decryptedPage, err := DecryptPage(pageBuf, encKey, macKey, curPage, d.hashFunc, d.hmacSize, d.reserve, d.pageSize)
		if err != nil {
			return fmt.Errorf("decrypt page %d failed: %w", curPage, err)
		}

		// 写入解密后的页面
		_, err = output.Write(decryptedPage)
		if err != nil {
			return fmt.Errorf("write page %d failed: %w", curPage, err)
		}
	}

	return nil
}

// DecryptToFile 解密数据库到文件
func (d *V4Decryptor) DecryptToFile(ctx context.Context, dbfile string, hexKey string, outputPath string) error {
	outFile, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("create output file failed: %w", err)
	}
	defer outFile.Close()

	return d.Decrypt(ctx, dbfile, hexKey, outFile)
}

// GetPageSize 返回页面大小
func (d *V4Decryptor) GetPageSize() int {
	return d.pageSize
}

// GetVersion 返回解密器版本
func (d *V4Decryptor) GetVersion() string {
	return d.version
}
