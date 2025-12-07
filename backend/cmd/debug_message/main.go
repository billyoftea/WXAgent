package main

import (
	"database/sql"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"strings"

	_ "modernc.org/sqlite"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: debug_message <db_path> <timestamp>")
		fmt.Println("Example: debug_message message_0.db 1761193232")
		os.Exit(1)
	}

	dbPath := os.Args[1]
	timestamp := os.Args[2]

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// 查找所有 Msg_ 表
	query := `SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Msg_%'`
	rows, err := db.Query(query)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	var tables []string
	for rows.Next() {
		var tableName string
		if err := rows.Scan(&tableName); err != nil {
			continue
		}
		tables = append(tables, tableName)
	}

	fmt.Printf("Found %d message tables\n\n", len(tables))

	// 在每个表中搜索
	for _, table := range tables {
		query := fmt.Sprintf(`SELECT create_time, type, message_content, compress_content 
			FROM "%s" 
			WHERE create_time = %s
			LIMIT 5`, table, timestamp)

		rows, err := db.Query(query)
		if err != nil {
			continue
		}

		found := false
		for rows.Next() {
			var createTime int64
			var msgType int64
			var messageContent sql.RawBytes
			var compressContent sql.RawBytes

			if err := rows.Scan(&createTime, &msgType, &messageContent, &compressContent); err != nil {
				continue
			}

			if !found {
				fmt.Printf("=== Found in table: %s ===\n", table)
				found = true
			}

			fmt.Printf("\nTimestamp: %d\n", createTime)
			fmt.Printf("Type: %d\n", msgType)

			fmt.Printf("\n--- message_content (%d bytes) ---\n", len(messageContent))
			if len(messageContent) > 0 {
				fmt.Printf("Hex (first 200 bytes): %s\n", hex.EncodeToString(messageContent[:min(200, len(messageContent))]))
				fmt.Printf("String (first 500 chars): %s\n", string(messageContent[:min(500, len(messageContent))]))

				// 检查是否包含 XML
				content := string(messageContent)
				if strings.Contains(strings.ToLower(content), "<title>") {
					fmt.Println("✓ Contains <title> tag")
					// 尝试提取title
					lowerContent := strings.ToLower(content)
					start := strings.Index(lowerContent, "<title>")
					if start != -1 {
						end := strings.Index(lowerContent[start:], "</title>")
						if end != -1 {
							title := content[start+7 : start+end]
							fmt.Printf("Extracted title: %s\n", title)
						}
					}
				}
			}

			fmt.Printf("\n--- compress_content (%d bytes) ---\n", len(compressContent))
			if len(compressContent) > 0 {
				fmt.Printf("Hex (first 200 bytes): %s\n", hex.EncodeToString(compressContent[:min(200, len(compressContent))]))

				// 检查魔数
				if len(compressContent) >= 4 {
					magic := uint32(compressContent[0]) | uint32(compressContent[1])<<8 |
						uint32(compressContent[2])<<16 | uint32(compressContent[3])<<24
					if magic == 0xFD2FB528 || magic == 0x28B52FFD {
						fmt.Println("✓ Detected: ZSTD compressed")
					} else {
						fmt.Printf("Magic: 0x%X\n", magic)
						// 尝试作为字符串查看
						fmt.Printf("As string (first 200 chars): %s\n", string(compressContent[:min(200, len(compressContent))]))
					}
				}
			}

			fmt.Println("\n" + strings.Repeat("-", 80))
		}
		rows.Close()

		if found {
			break // 找到了就不再搜索其他表
		}
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
