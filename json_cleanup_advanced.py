"""
微信消息导出清理脚本
用于修复包含乱码和特殊字符的消息
"""

import json
import re
import sys
from pathlib import Path


def clean_message_content(content: str) -> str:
    """清理消息内容中的特殊字符和乱码"""
    if not content:
        return content
    
    # 如果是占位符消息，直接返回
    placeholders = [
        "[图文消息]", "[图片]", "[视频消息]", "[语音消息]",
        "[动画表情]", "[位置消息]", "[名片消息]", "[链接]",
        "[小程序]", "[音乐]", "[红包]", "[聊天记录]", "[拍一拍]",
        "[转账]", "[不支持的消息类型]", "[引用消息]"
    ]
    if content in placeholders:
        return content
    
    # 统计替换符数量
    replacement_count = content.count('\ufffd')
    total_chars = len(content)
    
    # 如果替换符超过20%，认为是乱码消息
    if total_chars > 0 and replacement_count / total_chars > 0.2:
        # 尝试提取可读部分
        # 移除所有替换符和控制字符
        cleaned = re.sub(r'[\ufffd\x00-\x1f\x7f-\x9f]', '', content)
        # 如果清理后长度太短，标记为不支持
        if len(cleaned) < 10:
            return "[消息内容无法解析]"
        return cleaned.strip()
    
    # 移除零散的替换符
    if replacement_count > 0:
        content = content.replace('\ufffd', '')
    
    # 移除控制字符（但保留换行和制表符）
    content = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]', '', content)
    
    return content.strip()


def process_json_file(input_path: Path, output_path: Path = None):
    """处理单个JSON文件"""
    if output_path is None:
        output_path = input_path.parent / f"{input_path.stem}_cleaned{input_path.suffix}"
    
    print(f"Processing: {input_path.name}")
    
    # 读取JSON
    with open(input_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # 统计信息
    total_messages = len(data.get('messages', []))
    cleaned_count = 0
    invalid_count = 0
    
    # 处理每条消息
    for msg in data.get('messages', []):
        original_content = msg.get('str_content', '')
        
        # 清理内容
        cleaned_content = clean_message_content(original_content)
        
        # 记录统计
        if cleaned_content != original_content:
            cleaned_count += 1
            if "[消息内容无法解析]" in cleaned_content or "[不支持的消息类型]" in cleaned_content:
                invalid_count += 1
        
        msg['str_content'] = cleaned_content
    
    # 写入清理后的JSON
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    
    print(f"  Total messages: {total_messages}")
    print(f"  Cleaned: {cleaned_count}")
    print(f"  Invalid: {invalid_count}")
    print(f"  Output: {output_path.name}\n")
    
    return cleaned_count, invalid_count


def main():
    if len(sys.argv) < 2:
        print("Usage: python json_cleanup.py <json_file_or_directory>")
        print("Example: python json_cleanup.py output/session.json")
        print("Example: python json_cleanup.py output/")
        sys.exit(1)
    
    input_path = Path(sys.argv[1])
    
    if not input_path.exists():
        print(f"Error: Path not found: {input_path}")
        sys.exit(1)
    
    total_cleaned = 0
    total_invalid = 0
    
    if input_path.is_file():
        # 处理单个文件
        cleaned, invalid = process_json_file(input_path)
        total_cleaned += cleaned
        total_invalid += invalid
    elif input_path.is_dir():
        # 处理目录中所有JSON文件
        json_files = list(input_path.glob("*.json"))
        # 排除已清理的文件和状态文件
        json_files = [f for f in json_files 
                     if not f.name.endswith('_cleaned.json') 
                     and f.name != '.wx_agent_state.json']
        
        if not json_files:
            print(f"No JSON files found in: {input_path}")
            sys.exit(1)
        
        print(f"Found {len(json_files)} JSON file(s) to process\n")
        
        for json_file in json_files:
            try:
                cleaned, invalid = process_json_file(json_file)
                total_cleaned += cleaned
                total_invalid += invalid
            except Exception as e:
                print(f"  Error processing {json_file.name}: {e}\n")
    
    print("=" * 50)
    print(f"Summary:")
    print(f"  Total messages cleaned: {total_cleaned}")
    print(f"  Total invalid messages: {total_invalid}")


if __name__ == "__main__":
    main()
