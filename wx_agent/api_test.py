import os
from openai import OpenAI
import json
import glob

# ==================== 第一步：读取并合并JSON ====================
json_path = '../output_test'

# 读取json_path中的所有JSON文件
json_files = glob.glob(os.path.join(json_path, '*.json'))
print(f"找到 {len(json_files)} 个JSON文件")

# 合并所有JSON文件
merged_data = {
    "sessions": [],
    "all_messages": []
}

for json_file in json_files:
    with open(json_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
        if "session" in data:
            merged_data["sessions"].append(data["session"])
        if "messages" in data:
            merged_data["all_messages"].extend(data["messages"])

print(f"合并后共有 {len(merged_data['sessions'])} 个会话，{len(merged_data['all_messages'])} 条消息")

# 提取所有消息内容用于AI总结
messages_text = []
for msg in merged_data["all_messages"]:
    if "content" in msg and msg["content"]:
        sender = msg.get("senderDisplayName", "未知用户")
        content = msg.get("content", "")
        # 过滤掉表情等特殊消息
        if content not in ["[动画表情]", "[图片]", "[视频]", "[文件]", "[语音]"]:
            messages_text.append(f"{sender}: {content}")

merged_content = "\n".join(messages_text)
print(f"\n已提取 {len(messages_text)} 条有效消息内容\n")


# ==================== 第二步：AI流式总结 ====================
# 请确保您已将 API Key 存储在环境变量 ARK_API_KEY 中
# 初始化Openai客户端，从环境变量中读取您的API Key
client = OpenAI(
    base_url="https://ark.cn-beijing.volces.com/api/v3",
    api_key='6c0430ad-12e5-4ea9-9661-bf2fa31d4514'
)

# 构建AI总结提示词
summary_prompt = f"""请总结以下微信群聊天记录的主要内容和讨论话题：

{merged_content}

要求：
1. 用中文总结
2. 总结出主要话题和讨论内容
3. 提取出重要信息（如招聘信息、活动信息等）
4. 概括参与者的主要观点或反应"""

print("=" * 60)
print("开始进行AI流式总结...")
print("=" * 60)

# 流式调用API进行总结
stream = client.chat.completions.create(
    model="deepseek-v3-1-terminus",
    messages=[
        {"role": "system", "content": "你是一个专业的微信群聊天内容分析助手，能够快速准确地总结和分析群聊内容。"},
        {"role": "user", "content": summary_prompt},
    ],
    stream=True,
)

print("\n【AI总结结果】\n")
full_response = ""
for chunk in stream:
    if not chunk.choices:
        continue
    if chunk.choices[0].delta.content:
        content = chunk.choices[0].delta.content
        print(content, end="", flush=True)
        full_response += content

print("\n\n" + "=" * 60)
print("总结完成！")
print("=" * 60)