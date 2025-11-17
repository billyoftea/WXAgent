import os
import json
import glob
import time
from langchain_openai import ChatOpenAI
from langchain.prompts import ChatPromptTemplate
from datetime import datetime, timedelta
from transformers import AutoTokenizer


# ==================== 初始化分词器 ====================
# 使用惰性加载，避免 import 阶段阻塞/打印
tokenizer = None
_tokenizer_load_failed = False


def ensure_tokenizer():
    """仅在需要时加载分词器，失败则退化为字符计数"""
    global tokenizer, _tokenizer_load_failed
    if tokenizer is not None or _tokenizer_load_failed:
        return tokenizer

    try:
        tokenizer = AutoTokenizer.from_pretrained("deepseek-ai/deepseek-llm-7b-base")
        print("✅ DeepSeek 分词器初始化完成")
    except Exception as exc:
        _tokenizer_load_failed = True
        print(f"⚠️ 无法加载 DeepSeek 分词器，将退化为字符计数: {exc}")
        tokenizer = None

    return tokenizer

# ==================== 第一步：读取并合并JSON ====================
def load_and_merge_json(json_path='./output_test'):
    """
    读取并按群聊分别合并JSON文件
    返回字典：{群聊名称: {"session": {...}, "messages": [...]}}
    """
    json_files = glob.glob(os.path.join(json_path, '*.json'))
    print(f"找到 {len(json_files)} 个JSON文件")
    
    merged_data = {}  # 按群聊名称分组
    
    for json_file in json_files:
        try:
            with open(json_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
                
                if "session" in data:
                    group_name = data["session"].get("displayName", "未知群聊")
                    
                    if group_name not in merged_data:
                        merged_data[group_name] = {
                            "session": data["session"],
                            "messages": []
                        }
                    
                    if "messages" in data:
                        merged_data[group_name]["messages"].extend(data["messages"])
        except Exception as e:
            print(f"⚠️ 读取文件 {json_file} 出错: {e}")
    
    return merged_data


def parse_date_input(date_str):
    """
    解析用户输入的日期字符串
    支持格式：YYYY-MM-DD 或 YYYY年MM月DD日
    
    Args:
        date_str: 日期字符串
    
    Returns:
        datetime 对象，如果解析失败返回 None
    """
    date_str = date_str.strip()
    
    # 尝试解析 YYYY-MM-DD 格式
    try:
        return datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        pass
    
    # 尝试解析 YYYY年MM月DD日 格式
    try:
        return datetime.strptime(date_str, "%Y年%m月%d日")
    except ValueError:
        pass
    
    # 尝试解析 YYYY/MM/DD 格式
    try:
        return datetime.strptime(date_str, "%Y/%m/%d")
    except ValueError:
        pass
    
    return None


def filter_messages_by_time(messages, start_date=None, end_date=None):
    """
    根据时间范围筛选消息
    
    Args:
        messages: 消息列表
        start_date: 开始日期（datetime对象），如果为None则不限制开始时间
        end_date: 结束日期（datetime对象），如果为None则不限制结束时间
    
    Returns:
        筛选后的消息列表
    """
    if start_date is None and end_date is None:
        return messages
    
    filtered = []
    for msg in messages:
        # 获取消息时间
        msg_time = None
        
        # 优先使用 createTime（Unix时间戳）
        if "createTime" in msg:
            msg_time = datetime.fromtimestamp(msg["createTime"])
        # 如果没有 createTime，尝试解析 formattedTime
        elif "formattedTime" in msg:
            try:
                msg_time = datetime.strptime(msg["formattedTime"], "%Y-%m-%d %H:%M:%S")
            except ValueError:
                continue
        
        if msg_time is None:
            continue
        
        # 检查时间范围
        if start_date is not None and msg_time < start_date:
            continue
        if end_date is not None:
            # 结束日期包含当天的23:59:59
            end_datetime = end_date.replace(hour=23, minute=59, second=59)
            if msg_time > end_datetime:
                continue
        
        filtered.append(msg)
    
    return filtered


def extract_messages_by_group(merged_data, start_date=None, end_date=None):
    """
    按群聊分别提取消息内容，支持时间筛选
    
    Args:
        merged_data: 合并后的数据字典
        start_date: 开始日期（datetime对象），如果为None则不限制开始时间
        end_date: 结束日期（datetime对象），如果为None则不限制结束时间
    
    Returns:
        字典：{群聊名称: [消息列表]}
    """
    excluded_types = ["[动画表情]", "[图片]", "[视频]", "[文件]", "[语音]"]
    
    result = {}
    
    for group_name, group_data in merged_data.items():
        messages_text = []
        
        # 获取所有消息
        all_messages = group_data.get("messages", [])
        
        # 应用时间筛选
        if start_date is not None or end_date is not None:
            all_messages = filter_messages_by_time(all_messages, start_date, end_date)
            print(f"   • 【{group_name}】时间筛选后: {len(all_messages)} 条消息")
        
        for msg in all_messages:
            if "content" in msg and msg["content"]:
                sender = msg.get("senderDisplayName", "未知用户")
                content = msg.get("content", "")
                # 过滤掉特殊消息类型
                if content not in excluded_types:
                    # 添加时间信息到消息中
                    time_str = ""
                    if "formattedTime" in msg:
                        time_str = f"[{msg['formattedTime']}] "
                    messages_text.append(f"{time_str}{sender}: {content}")
        
        result[group_name] = messages_text
    
    return result


def format_messages_with_group_labels(messages_by_group):
    """
    将按群聊分组的消息格式化为一个统一的文本，
    用清晰的分隔符标明不同群聊，用于一次 API 调用
    
    Args:
        messages_by_group: 字典 {群聊名称: [消息列表]}
    
    Returns:
        格式化后的文本，包含所有群聊的消息
    """
    formatted_content = ""
    
    for group_name, messages_text in messages_by_group.items():
        if not messages_text:
            continue
        
        formatted_content += f"\n{'=' * 80}\n"
        formatted_content += f"【群聊：{group_name}】（共 {len(messages_text)} 条消息）\n"
        formatted_content += f"{'=' * 80}\n\n"
        formatted_content += "\n".join(messages_text)
        formatted_content += "\n\n"
    
    return formatted_content


# ==================== Token 管理工具 ====================
def count_tokens(text):
    """
    计算文本的token 数量
    使用 DeepSeek 官方分词器
    """
    tok = ensure_tokenizer()
    if tok is None:
        return len(text)

    try:
        tokens = tok.encode(text)
        return len(tokens)
    except Exception as e:
        print(f"⚠️ Token 计数异常: {e}，使用字符计数")
        return len(text)


def split_text_by_tokens(text, max_tokens=60000, overlap_tokens=500):
    """
    按token 数量智能分割文本（基于DeepSeek 分词器）
    优化：单次编码 + 滑动窗口，避免 O(n^2) 重复编码

    Args:
        text: 要分割的文本
        max_tokens: 每个分割的最大token 数（API限制98304，prompt约3000，文本限制90000）
        overlap_tokens: 分割之间的重叠token 数（保持上下文）

    Returns:
        分割后的文本列表
    """
    if max_tokens <= 0:
        raise ValueError("max_tokens 必须大于 0")
    if overlap_tokens < 0:
        raise ValueError("overlap_tokens 不能为负数")
    if overlap_tokens >= max_tokens:
        raise ValueError("overlap_tokens 必须小于 max_tokens")

    tok = ensure_tokenizer()
    if tok is None:
        approx_chars = max_tokens * 4
        overlap_chars = overlap_tokens * 4
        batches = []
        start_idx = 0
        while start_idx < len(text):
            end_idx = min(start_idx + approx_chars, len(text))
            batches.append(text[start_idx:end_idx])
            if end_idx == len(text):
                break
            start_idx = max(0, end_idx - overlap_chars)
        return batches

    token_ids = tok.encode(text)
    total_tokens = len(token_ids)
    if total_tokens <= max_tokens:
        return [text]

    print("\n📊 文本 token 数超过限制，执行智能分割...")
    print(f"   - 总 tokens: {total_tokens}")
    print(f"   - 每批上限: {max_tokens} tokens")
    print(f"   - 上下文重叠: {overlap_tokens} tokens")
    print(f"   - 预计批次数: {(total_tokens + max_tokens - 1) // max_tokens}")

    batches = []
    batch_token_counts = []
    step = max_tokens - overlap_tokens
    start_idx = 0
    while start_idx < total_tokens:
        end_idx = min(start_idx + max_tokens, total_tokens)
        batch_tokens = token_ids[start_idx:end_idx]
        batches.append(tok.decode(batch_tokens))
        batch_token_counts.append(len(batch_tokens))
        if end_idx == total_tokens:
            break
        start_idx += step

    print(f"   - 分割完成！共 {len(batches)} 批\n")
    for idx, count in enumerate(batch_token_counts, 1):
        extra = " ⚠️ 超过限制！" if count > max_tokens else " tokens"
        print(f"     批次 {idx}: {count}{extra}")

    return batches


# ==================== 第二步：初始化LangChain LLM ====================
def init_langchain_llm(api_key='6c0430ad-12e5-4ea9-9661-bf2fa31d4514'):
    """初始化 LangChain ChatOpenAI 客户端"""
    llm = ChatOpenAI(
        model="deepseek-v3-1-terminus",
        base_url="https://ark.cn-beijing.volces.com/api/v3",
        api_key=api_key,
        temperature=0.7,
        streaming=True
    )
    return llm


# ==================== 第三步：创建LangChain链 ====================
def create_summary_chain(llm):
    """创建聊天总结链（支持多群聊）"""
    
    prompt_template = ChatPromptTemplate.from_messages([
        ("system", "你是一个专业的微信群聊天内容分析助手，能够快速准确地总结和分析群聊内容。你需要处理多个不同的群聊，请按群聊分别进行总结分析。"),
        ("user", """请分别总结以下微信群聊天记录的主要内容和讨论话题。
注意：以下文本包含来自不同群聊的消息，每个群聊用【群聊：群名】的格式标记，请按群聊分别总结。

{messages}

要求：
1. 用中文总结
2. 分聊天对象进行总结，同一个群聊或者同一个聊天记录放在一起总结。
3. 总结出主要话题和讨论内容（用编号列出，并附上时间和讨论人（如果必要））
4. 提取出重要信息（如招聘信息、活动信息等），并注意引用原文！
5. 概括参与者的主要观点或反应
6. 标出最活跃的话题和讨论热度""")

    ])
    
    chain = prompt_template | llm
    return chain


def create_reduce_chain(llm):
    """创建合并多批次总结的 reduce 链"""
    reduce_prompt = ChatPromptTemplate.from_messages([
        ("system", "你是一个严谨的会议/群聊纪要整理助手，会将多份局部总结整合成结构化的最终报告。"),
        ("user", """下面提供了若干分片的局部总结，请你：
1. 按群聊/话题重新组织内容，去掉重复叙述，但要保留所有关键细节、时间、人物与数量。
2. 识别跨批次连续的讨论并合并，补全上下文。
3. 输出 Markdown，包含：概览、按群聊的详细总结、关键行动项/待办/风险。

分片总结如下：
{sub_summaries}
""")
    ])
    return reduce_prompt | llm


# ==================== 第四步：执行总结和流式输出 ====================
def run_summary(map_chain, reduce_chain, messages_by_group, max_tokens=60000, overlap_tokens=500, map_concurrency=10):
    """
    使用 Map-Reduce 策略执行总结

    Args:
        map_chain: 用于局部总结的 LangChain 链
        reduce_chain: 用于合并局部总结的 LangChain 链
        messages_by_group: 按群聊分组的消息字典 {群聊名称: [消息列表]}
        max_tokens: 文本部分允许的 token 数（默认60000，留出 prompt 空间）
        overlap_tokens: 批次之间保留的 token 数
        map_concurrency: map 阶段并发度（>1 时使用 batch）

    Returns:
        最终总结内容字符串
    """

    prompt_tokens = 400

    api_max_tokens = 98304
    available_tokens = api_max_tokens - prompt_tokens - 1000
    if max_tokens > available_tokens:
        print(f"⚠️ 调整 max_tokens 从 {max_tokens} 到 {available_tokens}（为 prompt 留出空间）")
        max_tokens = available_tokens

    merged_content = format_messages_with_group_labels(messages_by_group)
    total_messages = sum(len(msgs) for msgs in messages_by_group.values())
    total_tokens = count_tokens(merged_content)

    print("=" * 80)
    print("🚀 开始执行 Map-Reduce 群聊总结流程")
    print("=" * 80)
    print(f"   - 群聊数: {len(messages_by_group)} 个")
    print(f"   - 总消息数: {total_messages} 条")
    print(f"   - 原始文本 token: {total_tokens}")
    print("=" * 80)

    batches = split_text_by_tokens(merged_content, max_tokens=max_tokens, overlap_tokens=overlap_tokens)
    if not batches:
        return "[没有可总结的消息]"

    def stream_single_batch(batch_text, idx, total):
        batch_tokens = count_tokens(batch_text)
        total_batch_tokens = batch_tokens + prompt_tokens

        print(f"\n{'='*80}")
        print(f"[MAP] 第 {idx}/{total} 批")
        print(f"   文本 tokens: {batch_tokens} / {max_tokens}")
        print(f"   Prompt tokens: {prompt_tokens}")
        print(f"   总 tokens: {total_batch_tokens} / {api_max_tokens}")

        if total_batch_tokens > api_max_tokens:
            warning = f"[批次 {idx} 跳过: token 数 {total_batch_tokens} 超过 API 限制]"
            print(f"   ⚠️ {warning}")
            return warning

        full_response = ""
        chunk_count = 0
        start_time = time.time()
        last_chunk_time = start_time

        try:
            for chunk in map_chain.stream({"messages": batch_text}):
                current_time = time.time()
                last_chunk_time = current_time
                chunk_count += 1
                content = chunk.content if hasattr(chunk, "content") else str(chunk)
                print(content, end="", flush=True)
                full_response += content

                if chunk_count % 100 == 0:
                    elapsed = current_time - start_time
                    print(f"\n[进度: 已接收 {chunk_count} 个chunks, 耗时 {elapsed:.1f}秒]", end="\r", flush=True)

                if current_time - last_chunk_time > 300:
                    print("\n⚠️ 警告: 超过5分钟未收到响应，可能网络有问题")
        except Exception as exc:
            print(f"\n❌ 批次 {idx} 处理出错: {exc}")
            return full_response if full_response else f"[批次 {idx} 处理失败: {exc}]"

        elapsed = time.time() - start_time
        print(f"\n\n✅ 批次 {idx} 完成，耗时 {elapsed:.1f}秒\n")
        return full_response

    map_summaries = []
    total_batches = len(batches)
    print(f"\n[MAP 阶段] 需要处理 {total_batches} 个批次（overlap={overlap_tokens} tokens）")

    if total_batches > 1 and map_concurrency > 1:
        print(f"⚡ 启用并发 map 处理（max_concurrency={map_concurrency}）")
        payloads = [{"messages": batch} for batch in batches]
        results = map_chain.batch(payloads, max_concurrency=map_concurrency, return_exceptions=True)
        for idx, (batch, res) in enumerate(zip(batches, results), 1):
            if isinstance(res, Exception):
                print(f"   ⚠️ 批次 {idx} 并发处理失败，改用串行重试: {res}")
                map_summaries.append(stream_single_batch(batch, idx, total_batches))
                continue
            text = res.content if hasattr(res, "content") else str(res)
            print(f"   ✅ 批次 {idx}/{total_batches} 并发完成（长度 {len(text)} 字符）")
            map_summaries.append(text)
    else:
        for idx, batch in enumerate(batches, 1):
            map_summaries.append(stream_single_batch(batch, idx, total_batches))

    print("\n[REDUCE 阶段] 正在整合所有批次总结...")
    sub_summaries = "\n\n---\n\n".join(
        f"【批次 {idx}】\n{summary.strip()}" for idx, summary in enumerate(map_summaries, 1)
    )

    try:
        reduce_result = reduce_chain.invoke({"sub_summaries": sub_summaries})
        final_text = reduce_result.content if hasattr(reduce_result, "content") else str(reduce_result)
        print("✅ 合并完成！")
        return final_text
    except Exception as exc:
        print(f"⚠️ 合并阶段出错，返回拼接文本: {exc}")
        return sub_summaries


# ==================== 第五步：保存总结结果 ====================
def format_duration(seconds):
    """格式化耗时秒数为可读文本"""
    if seconds is None:
        return "未记录"
    seconds = int(max(0, seconds))
    minutes, secs = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    parts = []
    if hours:
        parts.append(f"{hours}小时")
    if minutes:
        parts.append(f"{minutes}分钟")
    if not parts or secs:
        parts.append(f"{secs}秒")
    return "".join(parts)


def save_summary(summary_content, output_file='summary_result.md', duration_seconds=None):
    """保存总结结果到Markdown文件"""
    if not output_file.endswith('.md'):
        output_file = output_file.replace('.json', '') + '.md'
    
    duration_text = format_duration(duration_seconds)
    
    # 准备 Markdown 内容
    md_content = f"""# 微信群聊天记录总结报告

**生成时间**: {datetime.now().strftime('%Y年%m月%d日 %H:%M:%S')}
**生成耗时**: {duration_text}

---

{summary_content}

---

**生成工具**: LangChain + DeepSeek V3 + 分词器智能分割
"""
    
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(md_content)
    
    print(f"\n✅ 总结结果已保存到: {output_file}")
    return output_file


# ==================== 主函数 ====================
def main():
    """主函数：执行完整的总结流程"""
    overall_start = time.time()
    
    # 第一步：加载和合并JSON
    print("\n[第一步] 加载并合并JSON文件...")
    merged_data = load_and_merge_json('./output_test')
    print(f"✅ 合并后共有 {len(merged_data)} 个群聊\n")
    
    for group_name in merged_data.keys():
        print(f"   • {group_name}: {len(merged_data[group_name]['messages'])} 条消息")
    print()
    
    # 时间筛选功能
    print("=" * 80)
    print("📅 时间筛选设置（可选）")
    print("=" * 80)
    print("提示：可以直接按回车跳过，表示不进行时间筛选")
    print("日期格式支持：YYYY-MM-DD 或 YYYY年MM月DD日 或 YYYY/MM/DD")
    print()
    
    start_date = None
    end_date = None
    
    # 获取开始日期
    start_input = input("请输入开始日期（年月日，例如：2025-11-10）: ").strip()
    if start_input:
        start_date = parse_date_input(start_input)
        if start_date is None:
            print("⚠️ 开始日期格式错误，将跳过时间筛选")
            start_date = None
        else:
            print(f"✅ 开始日期: {start_date.strftime('%Y年%m月%d日')}")
    
    # 获取结束日期
    end_input = input("请输入结束日期（年月日，例如：2025-11-12）: ").strip()
    if end_input:
        end_date = parse_date_input(end_input)
        if end_date is None:
            print("⚠️ 结束日期格式错误，将跳过时间筛选")
            end_date = None
        else:
            print(f"✅ 结束日期: {end_date.strftime('%Y年%m月%d日')}")
    
    if start_date and end_date and start_date > end_date:
        print("⚠️ 开始日期不能晚于结束日期，将跳过时间筛选")
        start_date = None
        end_date = None
    
    if start_date or end_date:
        print(f"\n📊 时间筛选范围: {start_date.strftime('%Y-%m-%d') if start_date else '不限'} 至 {end_date.strftime('%Y-%m-%d') if end_date else '不限'}")
    else:
        print("\n📊 不进行时间筛选，将分析所有消息")
    print("=" * 80)
    print()
    
    # 第二步：按群聊提取消息（应用时间筛选）
    print("[第二步] 按群聊提取有效消息内容（应用时间筛选）...")
    messages_by_group = extract_messages_by_group(merged_data, start_date, end_date)
    total_valid = sum(len(msgs) for msgs in messages_by_group.values())
    print(f"✅ 已提取 {total_valid} 条有效消息内容\n")
    
    # 第三步：初始化LangChain LLM
    print("[第三步] 初始化LangChain LLM...")
    llm = init_langchain_llm()
    print("✅ LLM 初始化成功\n")
    
    # 第四步：创建总结链
    print("[第四步] 创建 Map/Reduce 总结链...")
    map_chain = create_summary_chain(llm)
    reduce_chain = create_reduce_chain(llm)
    print("✅ Map 链 & Reduce 链创建成功\n")
    
    # 第五步：执行总结
    print("[第五步] 执行总结...")
    summary = run_summary(map_chain, reduce_chain, messages_by_group)
    
    # 第六步：保存结果
    print("\n[第六步] 保存总结结果...")
    total_duration = time.time() - overall_start
    save_summary(summary, duration_seconds=total_duration)
    
    print("\n" + "=" * 80)
    print("🎉 所有流程完成！")
    print("=" * 80)


if __name__ == "__main__":
    main()
