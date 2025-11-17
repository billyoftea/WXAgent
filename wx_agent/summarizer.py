from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

from langchain.prompts import ChatPromptTemplate
from langchain_openai import ChatOpenAI

from .langchain_test_v2 import (  # type: ignore
    count_tokens,
    format_messages_with_group_labels,
    split_text_by_tokens,
)


@dataclass
class PromptSet:
    """Prompt 模板配置"""

    summary_system: str
    summary_user: str
    reduce_system: str
    reduce_user: str


@dataclass
class QaPromptSet:
    """自定义问答 Prompt 配置"""

    map_system: str
    map_user: str
    reduce_system: str
    reduce_user: str


@dataclass
class SummaryConfig:
    """Map-Reduce 总结配置"""

    max_tokens: int = 60000
    overlap_tokens: int = 800
    api_max_tokens: int = 98304
    map_concurrency: int = 3


@dataclass
class QaConfig:
    """问答上下文配置"""

    context_tokens: int = 20000
    overlap_tokens: int = 400
    max_batches: int = 4


@dataclass
class LLMConfig:
    """LLM 连接配置"""

    api_key: Optional[str] = None
    base_url: Optional[str] = None
    model: str = "deepseek-v3-1-terminus"
    temperature: float = 0.3
    streaming: bool = False
    timeout: Optional[float] = None


DEFAULT_PROMPTS = PromptSet(
    summary_system=(
        "你是一个专业的微信群聊天内容分析助手，擅长结构化总结和关键信息提炼。"
    ),
    summary_user=(
        "请分别总结以下微信群聊天记录的主要内容和讨论话题。\n"
        "注意：以下文本包含来自不同群聊的消息，每个群聊用【群聊：群名】的格式标记，"
        "请按群聊分别总结。\n\n"
        "{messages}\n\n"
        "要求：\n"
        "1. 用中文总结，直接输出 Markdown。\n"
        "2. 按群聊拆分结果，列出最重要的 3-5 个话题，注明时间、人物与结论。\n"
        "3. 提取招聘/活动/投融资/任务等可执行信息，标注原文引用。\n"
        "4. 列出未解决的问题、后续行动项及负责人（若未提及可写“未指明”）。\n"
        "5. 给出该群聊活跃度（高/中/低）和整体情绪（积极/中性/消极）的判断。"
    ),
    reduce_system=(
        "你是一个严谨的会议与群聊纪要整理助手，负责打磨最终版本的汇总报告。"
    ),
    reduce_user=(
        "以下是多批次的局部总结，请将它们合并为一份结构化的最终报告，要求：\n"
        "1. 先输出整体概览（总消息数、涵盖群聊、主要主题）。\n"
        "2. 按群聊列出详细总结，每个群聊包含：核心主题、重要事件、风险/待办。\n"
        "3. 汇总所有群聊共有的行动项/风险，必要时引用原文。\n"
        "4. 保留时间、人名、金额等细节，避免重复描述。\n\n"
        "局部总结：\n{sub_summaries}\n"
    ),
)

DEFAULT_QA_PROMPTS = QaPromptSet(
    map_system=(
        "你是一个严谨的数据抽取助手，只能依据提供的聊天记录回答问题。"
    ),
    map_user=(
        "请阅读以下聊天记录，并围绕用户问题给出要点式答案。"
        "回答时务必引用原文或提供精确的时间/人物。\n\n"
        "【问题】{question}\n\n"
        "【聊天记录片段】\n{messages}\n"
    ),
    reduce_system="你负责整合多个片段的回答，输出最终答案。",
    reduce_user=(
        "以下是针对同一问题在不同聊天片段里的回答，请融合为最终结果：\n"
        "{partial_answers}\n\n"
        "要求：\n"
        "1. 去重且保持原始依据，必要时引用原文。\n"
        "2. 如果不同片段存在矛盾，请指出差异。\n"
        "3. 用 Markdown 输出，包含结论与证据小节。"
    ),
)


def _resolve_env(*names: str) -> Optional[str]:
    for name in names:
        val = os.environ.get(name)
        if val:
            return val
    return None


def build_llm(config: LLMConfig) -> ChatOpenAI:
    """根据配置构建 ChatOpenAI 客户端"""
    api_key = config.api_key or _resolve_env(
        "LLM_API_KEY",
        "WX_AGENT_API_KEY",
        "ARK_API_KEY",
        "DEEPSEEK_API_KEY",
        "OPENAI_API_KEY",
    )
    if not api_key:
        raise ValueError(
            "未配置 LLM API key，请设置 LLM_API_KEY / ARK_API_KEY 等环境变量，"
            "或在 LLMConfig.api_key 中显式传入。"
        )

    base_url = config.base_url or _resolve_env(
        "LLM_BASE_URL",
        "WX_AGENT_API_BASE",
        "ARK_API_BASE",
        "OPENAI_BASE_URL",
    )
    if not base_url:
        base_url = "https://ark.cn-beijing.volces.com/api/v3"

    return ChatOpenAI(
        model=config.model,
        base_url=base_url,
        api_key=api_key,
        temperature=config.temperature,
        streaming=config.streaming,
        timeout=config.timeout,
    )


class SummaryEngine:
    """负责 Map-Reduce 群聊总结"""

    def __init__(
        self,
        llm: ChatOpenAI,
        summary_config: SummaryConfig = SummaryConfig(),
        prompts: PromptSet = DEFAULT_PROMPTS,
    ):
        self.llm = llm
        self.config = summary_config
        self.prompts = prompts
        self.map_chain = ChatPromptTemplate.from_messages(
            [
                ("system", prompts.summary_system),
                ("user", prompts.summary_user),
            ]
        ) | llm
        self.reduce_chain = ChatPromptTemplate.from_messages(
            [
                ("system", prompts.reduce_system),
                ("user", prompts.reduce_user),
            ]
        ) | llm

    def summarize(
        self, messages_by_group: Dict[str, List[str]]
    ) -> Tuple[str, Dict[str, int]]:
        """执行 Map-Reduce 总结"""
        formatted = format_messages_with_group_labels(messages_by_group)
        total_tokens = count_tokens(formatted)
        total_messages = sum(len(v) for v in messages_by_group.values())

        batches = split_text_by_tokens(
            formatted,
            max_tokens=self.config.max_tokens,
            overlap_tokens=self.config.overlap_tokens,
        )
        if not batches:
            return "[没有可总结的消息]", {"total_tokens": 0, "total_messages": 0}

        payloads = [{"messages": batch} for batch in batches]
        summaries: List[str] = []

        if len(batches) > 1 and self.config.map_concurrency > 1:
            results = self.map_chain.batch(
                payloads,
                max_concurrency=self.config.map_concurrency,
                return_exceptions=True,
            )
            for idx, res in enumerate(results, 1):
                if isinstance(res, Exception):
                    raise RuntimeError(f"Map 阶段批次 {idx} 失败: {res}") from res
                summaries.append(res.content if hasattr(res, "content") else str(res))
        else:
            for payload in payloads:
                res = self.map_chain.invoke(payload)
                summaries.append(res.content if hasattr(res, "content") else str(res))

        sub_summaries = "\n\n---\n\n".join(
            f"【批次 {idx}】\n{summary.strip()}"
            for idx, summary in enumerate(summaries, start=1)
        )
        reduce_res = self.reduce_chain.invoke({"sub_summaries": sub_summaries})
        final_summary = (
            reduce_res.content if hasattr(reduce_res, "content") else str(reduce_res)
        )

        return final_summary, {
            "total_tokens": total_tokens,
            "total_messages": total_messages,
            "batches": len(batches),
        }


class QuestionAnsweringEngine:
    """基于原始聊天内容的分批问答"""

    def __init__(
        self,
        llm: ChatOpenAI,
        qa_config: QaConfig = QaConfig(),
        prompts: QaPromptSet = DEFAULT_QA_PROMPTS,
    ):
        self.llm = llm
        self.config = qa_config
        self.prompts = prompts
        self.map_chain = ChatPromptTemplate.from_messages(
            [
                ("system", prompts.map_system),
                ("user", prompts.map_user),
            ]
        ) | llm
        self.reduce_chain = ChatPromptTemplate.from_messages(
            [
                ("system", prompts.reduce_system),
                ("user", prompts.reduce_user),
            ]
        ) | llm

    def answer(
        self, formatted_messages: str, question: str
    ) -> Tuple[str, Dict[str, int]]:
        """针对单个问题执行分批问答"""
        batches = split_text_by_tokens(
            formatted_messages,
            max_tokens=self.config.context_tokens,
            overlap_tokens=self.config.overlap_tokens,
        )
        if not batches:
            return "暂无可用聊天记录回答该问题。", {"batches": 0, "used_tokens": 0}

        partial_answers: List[str] = []
        for idx, batch in enumerate(batches, start=1):
            if idx > self.config.max_batches:
                break
            res = self.map_chain.invoke({"messages": batch, "question": question})
            partial_answers.append(res.content if hasattr(res, "content") else str(res))

        if len(partial_answers) == 1:
            answer = partial_answers[0]
        else:
            combined = "\n\n".join(partial_answers)
            reduce_res = self.reduce_chain.invoke(
                {
                    "partial_answers": combined,
                    "question": question,
                }
            )
            answer = (
                reduce_res.content if hasattr(reduce_res, "content") else str(reduce_res)
            )

        used_tokens = count_tokens("\n".join(partial_answers))
        return answer, {"batches": len(partial_answers), "used_tokens": used_tokens}


__all__ = [
    "PromptSet",
    "QaPromptSet",
    "SummaryConfig",
    "QaConfig",
    "LLMConfig",
    "DEFAULT_PROMPTS",
    "DEFAULT_QA_PROMPTS",
    "build_llm",
    "SummaryEngine",
    "QuestionAnsweringEngine",
]

