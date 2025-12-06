package main

import (
	"encoding/json"
	"fmt"
)

type Message struct {
	CreateTime int64  `json:"create_time"`
	Type       string `json:"type"`
	StrContent string `json:"str_content"`
}

func main() {
	msg := Message{
		CreateTime: 1657430218,
		Type:       "文本",
		StrContent: "测试消息",
	}

	data, err := json.MarshalIndent(msg, "", "  ")
	if err != nil {
		panic(err)
	}

	fmt.Println(string(data))
}
