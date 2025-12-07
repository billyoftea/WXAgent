package main

import (
	"database/sql"
	"encoding/hex"
	"fmt"
	"log"
	"os"

	_ "modernc.org/sqlite"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: test_message <db_path> <timestamp>")
		os.Exit(1)
	}

	dbPath := os.Args[1]
	timestamp := os.Args[2]

	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// 查找包含该 session 的表
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

	fmt.Printf("Found %d message tables\n", len(tables))

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

		for rows.Next() {
			var createTime int64
			var msgType int64
			var messageContent sql.RawBytes
			var compressContent sql.RawBytes

			if err := rows.Scan(&createTime, &msgType, &messageContent, &compressContent); err != nil {
				continue
			}

			fmt.Printf("\n=== Found in table: %s ===\n", table)
			fmt.Printf("Timestamp: %d\n", createTime)
			fmt.Printf("Type: %d\n", msgType)
			fmt.Printf("\nMessage Content (%d bytes):\n", len(messageContent))
			if len(messageContent) > 0 {
				fmt.Println("Hex:", hex.EncodeToString(messageContent[:min(200, len(messageContent))]))
				fmt.Println("String:", string(messageContent[:min(200, len(messageContent))]))
			}
			fmt.Printf("\nCompress Content (%d bytes):\n", len(compressContent))
			if len(compressContent) > 0 {
				fmt.Println("Hex:", hex.EncodeToString(compressContent[:min(200, len(compressContent))]))
				// 检查是否是 zstd 压缩
				if len(compressContent) >= 4 {
					magic := uint32(compressContent[0]) | uint32(compressContent[1])<<8 |
						uint32(compressContent[2])<<16 | uint32(compressContent[3])<<24
					if magic == 0xFD2FB528 || magic == 0x28B52FFD {
						fmt.Println("(Detected: ZSTD compressed)")
					}
				}
			}
		}
		rows.Close()
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
