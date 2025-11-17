from __future__ import annotations



import json

import os

import re

import subprocess

import time

from collections import Counter

from dataclasses import dataclass

from datetime import datetime, timedelta

from pathlib import Path

from typing import Any, Dict, List, Optional, Sequence, Tuple

from urllib.parse import urljoin



try:

    import requests  # type: ignore

except Exception:  # pragma: no cover - optional dependency

    requests = None



from .config import PipelineConfig

from .langchain_test_v2 import (

    format_messages_with_group_labels,

    save_summary as legacy_save_summary,

)  # type: ignore

from .state import PipelineState

from .summarizer import (

    DEFAULT_PROMPTS,

    DEFAULT_QA_PROMPTS,

    LLMConfig,

    QaConfig,

    QaPromptSet,

    QuestionAnsweringEngine,

    SummaryConfig,

    SummaryEngine,

    build_llm,

    PromptSet,

)





WINDOWS = os.name == "nt"

CREATE_NO_WINDOW = 0x08000000 if WINDOWS else 0





@dataclass

class KeyPayload:

    db_key: Optional[str]

    image_xor_key: Optional[int]

    image_aes_key: Optional[str]

    timestamp: Optional[str]

    raw: Dict[str, str]





def _parse_iso_datetime(value: Optional[str]) -> Optional[str]:

    if not value:

        return None

    try:

        dt = datetime.fromisoformat(value)

        return dt.strftime("%Y-%m-%d %H:%M:%S")

    except Exception:

        return value





@dataclass

class ExportStateInfo:

    path: Path

    session_id: Optional[str]

    display_name: Optional[str]

    file_path: Optional[str]

    total_count: int

    last_export_time: Optional[str]

    added_count: Optional[int]

    history: List[Dict[str, object]]



    @classmethod

    def from_path(cls, path: Path) -> Optional["ExportStateInfo"]:

        if not path.exists():

            return None

        try:

            with open(path, "r", encoding="utf-8") as f:

                raw = json.load(f)

        except Exception:

            return None

        history = raw.get("history")

        if not isinstance(history, list):

            history = []

        last_time = raw.get("lastExportTime")

        last_added = None

        if history:

            last_entry = history[-1]

            if isinstance(last_entry, dict):

                last_time = last_entry.get("exportTime") or last_time

                last_added = last_entry.get("addedCount")

        return cls(

            path=path,

            session_id=raw.get("sessionWxid"),

            display_name=raw.get("displayName"),

            file_path=raw.get("filePath"),

            total_count=int(raw.get("totalExportedCount") or 0),

            last_export_time=_parse_iso_datetime(last_time),

            added_count=int(last_added) if last_added is not None else None,

            history=history,

        )





def _format_timestamp(ts: Optional[int]) -> Optional[str]:

    if not ts:

        return None

    try:

        return datetime.fromtimestamp(int(ts)).strftime("%Y-%m-%d %H:%M:%S")

    except (ValueError, OSError, TypeError):

        return None





def _safe_filename(*parts: str) -> str:

    joined = "_".join(filter(None, (part.strip() for part in parts if part)))

    normalized = re.sub(r"[^0-9A-Za-z\u4e00-\u9fff_-]+", "_", joined).strip("_")

    return normalized or "summary"





def _build_completion_url(base_url: str) -> str:

    base = base_url.rstrip("/")

    if base.endswith("/chat/completions"):

        return base

    return urljoin(base + "/", "chat/completions")





def _build_models_url(base_url: str) -> str:

    base = base_url.rstrip("/")

    lowered = base.lower()

    for suffix in ("/v1/chat/completions", "/chat/completions"):

        if lowered.endswith(suffix):

            base = base[: -len(suffix)]

            break

    return urljoin(base.rstrip("/") + "/", "models")





def _dedupe_existing_paths(paths: Sequence[Optional[Path]]) -> List[str]:

    seen: set[str] = set()

    results: List[str] = []

    for candidate in paths:

        if not candidate:

            continue

        try:

            resolved = candidate.expanduser().resolve()

        except OSError:

            resolved = candidate.expanduser()

        key = str(resolved)

        if resolved.exists() and key not in seen:

            seen.add(key)

            results.append(key)

    return results





def _auto_detect_wechat_installations(explicit: Optional[Path]) -> List[str]:

    program_files = os.environ.get("ProgramFiles")

    program_files_x86 = os.environ.get("ProgramFiles(x86)")

    candidates: List[Optional[Path]] = [

        explicit,

        Path(program_files) / "Tencent" / "WeChat" if program_files else None,

        Path(program_files_x86) / "Tencent" / "WeChat" if program_files_x86 else None,

        Path.home() / "AppData" / "Local" / "Tencent" / "WeChat",

    ]

    return _dedupe_existing_paths(candidates)





def _auto_detect_wechat_data_dirs(explicit: Optional[Path]) -> List[str]:

    home = Path.home()

    documents = home / "Documents"

    roaming = Path(os.environ.get("APPDATA", home / "AppData" / "Roaming"))

    candidates: List[Optional[Path]] = [

        explicit,

        documents / "WeChat Files",

        documents / "WeChat Files" / "All Users",

        roaming / "Tencent" / "WeChat",

        home / "AppData" / "Roaming" / "Tencent" / "WeChat",

    ]

    return _dedupe_existing_paths(candidates)





def _categorize_message_type(message: Dict[str, Any]) -> str:

    type_field = str(message.get("type") or "").lower()

    local_type = str(message.get("localType") or "").lower()

    content = str(message.get("content") or "").lower()

    if any(token in type_field for token in ("text", "文本", "文字")):

        return "text"

    if any(token in type_field for token in ("image", "图片", "photo", "pic")) or "[图片]" in content:

        return "image"

    if any(token in type_field for token in ("voice", "audio", "语音", "录音")) or "voice" in local_type:

        return "voice"

    if any(token in type_field for token in ("video", "视频", "短视�?)):

        return "video"

    if any(token in type_field for token in ("file", "附件")):

        return "file"

    return "other"





def _categorize_session(meta: Dict[str, object]) -> str:

    session_type = str(meta.get("session_type") or "").lower()

    session_id = str(meta.get("session_id") or "")

    if "chatroom" in session_id or "�? in session_type or "group" in session_type:

        return "group"

    if "single" in session_type or "�? in session_type:

        return "single"

    return "single" if "@chatroom" not in session_id else "group"









def _normalize_session_filters(session_types: Optional[Sequence[str]]) -> Optional[set[str]]:

    if not session_types:

        return None

    mapping = {

        "group": "group",

        "groups": "group",

        "??": "group",

        "chatroom": "group",

        "team": "group",

        "single": "single",

        "private": "single",

        "direct": "single",

        "dm": "single",

        "??": "single",

        "??": "single",

        "all": "all",

        "??": "all",

    }

    normalized: set[str] = set()

    for item in session_types:

        if item is None:

            continue

        value = str(item).strip().lower()

        if not value:

            continue

        mapped = mapping.get(value, value)

        if mapped == "all":

            return None

        if mapped in {"group", "single"}:

            normalized.add(mapped)

    return normalized or None



class WxKeyBridge:

    """负责�?wx_key SharedPreferences 中读取密�?""



    def __init__(self, shared_pref_path: Optional[Path]):

        self.shared_pref_path = shared_pref_path



    def _read_preferences(self) -> Dict[str, str]:

        if not self.shared_pref_path:

            return {}

        if not self.shared_pref_path.exists():

            return {}

        with open(self.shared_pref_path, "r", encoding="utf-8") as f:

            try:

                return json.load(f)

            except json.JSONDecodeError:

                return {}



    def load_keys(self) -> KeyPayload:

        data = self._read_preferences()

        db_key = data.get("flutter.wechat_db_key") or data.get("wechat_db_key")

        timestamp = (

            data.get("flutter.key_timestamp")

            or data.get("key_timestamp")

            or data.get("flutter.image_key_timestamp")

        )

        return KeyPayload(

            db_key=db_key,

            image_xor_key=data.get("flutter.image_xor_key"),

            image_aes_key=data.get("flutter.image_aes_key"),

            timestamp=_parse_iso_datetime(timestamp),

            raw=data,

        )





class EchoTraceBridge:

    """可选地触发 echotrace 导出"""



    def __init__(self, command_spec, export_dir: Path):

        self.command_spec = command_spec

        self.export_dir = export_dir



    def run(self, extra_args: Optional[Sequence[str]] = None, silent: bool = True) -> bool:

        cmd = self.command_spec.as_subprocess()

        if not cmd:

            return False

        args = list(cmd)

        if extra_args:

            args.extend(extra_args)

        completed = subprocess.run(

            args,

            cwd=self.command_spec.cwd,

            env=self.command_spec.env or None,

            check=False,

            creationflags=CREATE_NO_WINDOW if silent and WINDOWS else 0,

        )

        return completed.returncode == 0





class ChatDatasetBuilder:

    """�?echotrace 导出�?JSON 中构建按群聊分组的文�?""



    def __init__(self, export_dir: Path, state: PipelineState):

        self.export_dir = export_dir

        self.state = state



    def build(

        self,

        start_date: Optional[datetime],

        end_date: Optional[datetime],

        incremental: bool,

        allowed_sessions: Optional[Sequence[str]] = None,

    ) -> Tuple[Dict[str, List[str]], List[Dict[str, object]]]:

        dataset: Dict[str, List[str]] = {}

        stats: List[Dict[str, object]] = []



        if not self.export_dir.exists():

            return dataset, stats



        allowed_names: Optional[set[str]] = None

        allowed_paths: Optional[set[str]] = None

        if allowed_sessions:

            names: set[str] = set()

            paths: set[str] = set()

            for item in allowed_sessions:

                if not item:

                    continue

                text = str(item).strip()

                if not text:

                    continue

                if any(sep in text for sep in ("/", "\\")) or text.lower().endswith(".json"):

                    try:

                        paths.add(str(Path(text).expanduser().resolve()))

                        continue

                    except Exception:

                        pass

                names.add(text.lower())

            allowed_names = names or None

            allowed_paths = paths or None



        files = sorted(self.export_dir.glob("*.json"))

        for json_file in files:

            session_data = self._load_json(json_file)

            if not session_data:

                continue



            session = session_data.get("session", {})

            session_id = session.get("wxid") or session.get("username") or json_file.stem

            display_name = session.get("displayName") or session.get("nickname") or json_file.stem

            messages = session_data.get("messages", [])



            include = True

            if allowed_paths:

                include = str(json_file.resolve()) in allowed_paths

            if include and allowed_names:

                tokens = {display_name.lower()}

                if session_id:

                    tokens.add(str(session_id).lower())

                include = any(token in allowed_names for token in tokens)

            if not include:

                continue



            session_state_ts = self.state.get_last_timestamp(session_id) if incremental else None



            filtered = []

            last_ts = session_state_ts or 0

            for message in messages:

                msg_dt, msg_ts = self._extract_datetime(message)

                if start_date and msg_dt and msg_dt < start_date:

                    continue

                if end_date and msg_dt and msg_dt > end_date + timedelta(days=1) - timedelta(seconds=1):

                    continue

                if incremental and session_state_ts and msg_ts and msg_ts <= session_state_ts:

                    continue



                text = self._message_to_text(message)

                if not text:

                    continue

                filtered.append(text)

                if msg_ts:

                    last_ts = max(last_ts, msg_ts)



            if filtered:

                dataset[display_name] = filtered

                stats.append(

                    {

                        "session_id": session_id,

                        "display_name": display_name,

                        "messages": len(filtered),

                        "file": str(json_file),

                        "last_timestamp": last_ts or session_state_ts or 0,

                    }

                )

                if incremental and last_ts:

                    self.state.update_session(session_id, last_ts, displayName=display_name)



        return dataset, stats



    def _load_json(self, json_file: Path) -> Optional[Dict[str, object]]:

        try:

            with open(json_file, "r", encoding="utf-8") as f:

                return json.load(f)

        except Exception:

            return None



    def _extract_datetime(self, message: Dict[str, object]) -> Tuple[Optional[datetime], Optional[int]]:

        if "createTime" in message:

            ts = message["createTime"]

            if isinstance(ts, (int, float)):

                dt = datetime.fromtimestamp(int(ts))

                return dt, int(ts)

        if "formattedTime" in message:

            try:

                dt = datetime.strptime(message["formattedTime"], "%Y-%m-%d %H:%M:%S")

                return dt, int(dt.timestamp())

            except Exception:

                return None, None

        return None, None



    def _message_to_text(self, message: Dict[str, object]) -> Optional[str]:

        content = str(message.get("content") or "").strip()

        sender = (

            message.get("senderDisplayName")

            or message.get("senderUsername")

            or message.get("from_nickname")

            or "未知用户"

        )

        formatted_time = message.get("formattedTime", "")

        prefix = f"[{formatted_time}] {sender}: " if formatted_time else f"{sender}: "



        if not content or content in {"[动画表情]", "[视频]", "[文件]", "[语音]"}:

            return None



        if content == "[图片]" or str(message.get("type", "")).startswith("图片"):

            return None



        return f"{prefix}{content}"



    def list_sessions_metadata(self) -> List[Dict[str, object]]:

        """扫描导出目录，返回每个会话的概要信息�?


        返回字段：session_id, display_name, session_type, messages, first_timestamp, last_timestamp, file, state_file

        """

        meta: List[Dict[str, object]] = []

        if not self.export_dir.exists():

            return meta

        files = sorted(self.export_dir.glob("*.json"))

        for json_file in files:

            data = self._load_json(json_file) or {}

            session = data.get("session", {}) if isinstance(data, dict) else {}

            session_id = (

                (session.get("wxid") or session.get("username") if isinstance(session, dict) else None)

                or json_file.stem

            )

            display_name = (

                (session.get("displayName") or session.get("nickname") if isinstance(session, dict) else None)

                or json_file.stem

            )

            session_type = session.get("type") if isinstance(session, dict) else None

            messages = data.get("messages") if isinstance(data, dict) else None

            count = len(messages) if isinstance(messages, list) else 0

            first_ts = None

            last_ts = None

            if isinstance(messages, list):

                for msg in messages:

                    dt, ts = self._extract_datetime(msg)

                    if ts is None:

                        continue

                    if first_ts is None or ts < first_ts:

                        first_ts = ts

                    if last_ts is None or ts > last_ts:

                        last_ts = ts

            meta.append(

                {

                    "session_id": session_id,

                    "display_name": display_name,

                    "session_type": session_type,

                    "messages": count,

                    "first_timestamp": first_ts or 0,

                    "last_timestamp": last_ts or 0,

                    "file": str(json_file),

                    "state_file": str(json_file.with_name(json_file.name + ".export_state")),

                }

            )

        return meta



    def load_filtered_messages(

        self,

        json_file: Path,

        start_date: Optional[datetime],

        end_date: Optional[datetime],

    ) -> Tuple[Dict[str, object], List[Dict[str, object]]]:

        if not json_file.exists():

            return {}, []

        data = self._load_json(json_file) or {}

        session = data.get("session", {}) if isinstance(data, dict) else {}

        messages = data.get("messages") if isinstance(data, dict) else None

        filtered: List[Dict[str, object]] = []

        if isinstance(messages, list):

            for msg in messages:

                dt, _ts = self._extract_datetime(msg)

                if start_date and dt and dt < start_date:

                    continue

                if end_date and dt and dt > end_date + timedelta(days=1) - timedelta(seconds=1):

                    continue

                filtered.append(msg)

        return session, filtered





def _normalize_date(value: Optional[str]) -> Optional[datetime]:

    if not value:

        return None

    formats = ("%Y-%m-%d", "%Y/%m/%d", "%Y%m%d", "%Y.%m.%d")

    for fmt in formats:

        try:

            return datetime.strptime(value, fmt)

        except ValueError:

            continue

    raise ValueError(f"无法解析日期格式: {value}")





def _load_questions_from_file(path: Optional[Path]) -> List[str]:

    if not path or not path.exists():

        return []

    with open(path, "r", encoding="utf-8") as f:

        return [line.strip() for line in f if line.strip()]





class WxAgentPipeline:

    """组合 wx_key + echotrace + LLM 的端到端流水�?""



    def __init__(self, config: PipelineConfig):

        self.config = config

        self.state = PipelineState(config.state_file)

        self.state.load()

        self.key_bridge = WxKeyBridge(config.wx_key_shared_prefs)

        self.export_bridge = EchoTraceBridge(config.echotrace_command, config.export_dir)

        self.dataset_builder = ChatDatasetBuilder(

            config.export_dir,

            self.state,

        )

        self.llm_config = LLMConfig(

            api_key=config.llm_api_key,

            base_url=config.llm_base_url,

            model=config.llm_model,

            temperature=config.llm_temperature,

        )

        self.summary_conf = SummaryConfig(

            max_tokens=config.max_tokens,

            overlap_tokens=config.overlap_tokens,

            api_max_tokens=config.api_max_tokens,

            map_concurrency=config.map_concurrency,

        )

        self.qa_conf = QaConfig(

            context_tokens=config.qa_context_tokens,

            overlap_tokens=config.qa_overlap_tokens,

            max_batches=config.qa_max_batches,

        )

        self.prompt_set = PromptSet(

            summary_system=config.prompts.summary_system or DEFAULT_PROMPTS.summary_system,

            summary_user=config.prompts.summary_user or DEFAULT_PROMPTS.summary_user,

            reduce_system=config.prompts.reduce_system or DEFAULT_PROMPTS.reduce_system,

            reduce_user=config.prompts.reduce_user or DEFAULT_PROMPTS.reduce_user,

        )

        self.qa_prompt_set = QaPromptSet(

            map_system=config.prompts.qa_map_system or DEFAULT_QA_PROMPTS.map_system,

            map_user=config.prompts.qa_map_user or DEFAULT_QA_PROMPTS.map_user,

            reduce_system=config.prompts.qa_reduce_system or DEFAULT_QA_PROMPTS.reduce_system,

            reduce_user=config.prompts.qa_reduce_user or DEFAULT_QA_PROMPTS.reduce_user,

        )

        self._llm = None

        self._summary_engine = None

        self._qa_engine = None



    def refresh_key(

        self,

        *,

        auto_launch: bool = False,

        wait_seconds: int = 120,

        poll_interval: int = 5,

    ) -> KeyPayload:

        payload = self.key_bridge.load_keys()

        if payload.db_key or not auto_launch:

            if not payload.db_key:

                raise RuntimeError("未能�?wx_key 首选项中找到数据库密钥，请先运�?wx_key 导出�?)

            return payload



        if not self.config.wx_key_command.as_subprocess():

            raise RuntimeError("未配�?wx_key 可执行文件路径，请在 config.json 中设�?wx_key_command.path�?)



        print("⚠️ 未检测到密钥，尝试为您启�?wx_key，请跟随界面操作�?)

        self.launch_wx_key(wait=False)



        deadline = time.time() + max(wait_seconds, poll_interval)

        while time.time() < deadline:

            time.sleep(max(1, poll_interval))

            payload = self.key_bridge.load_keys()

            if payload.db_key:

                print("�?已检测到新的数据库密钥�?)

                return payload



        raise RuntimeError("等待 wx_key 写出密钥超时，请确认操作完成后再重试�?)



    def trigger_export(

        self,

        extra_args: Optional[Sequence[str]] = None,

        silent: bool = True,

    ) -> bool:

        return self.export_bridge.run(extra_args=extra_args, silent=silent)



    def launch_wx_key(

        self,

        extra_args: Optional[Sequence[str]] = None,

        wait: bool = False,

        silent: bool = True,

    ):

        cmd = self.config.wx_key_command.as_subprocess()

        if not cmd:

            raise RuntimeError("未配�?wx_key 可执行文件路径，请在 config.json 中填�?wx_key_command.path�?)

        args = list(cmd)

        if extra_args:

            args.extend(extra_args)

        print(f"🚀 启动 wx_key: {' '.join(args)}")

        creationflags = CREATE_NO_WINDOW if silent and WINDOWS else 0

        proc = subprocess.Popen(

            args,

            cwd=self.config.wx_key_command.cwd,

            env=self.config.wx_key_command.env or None,

            creationflags=creationflags,

        )

        if wait:

            proc.wait()

        return proc



    def run(

        self,

        start_date: Optional[str] = None,

        end_date: Optional[str] = None,

        incremental: bool = True,

        questions: Optional[Sequence[str]] = None,

        save_markdown: bool = True,

        summary_prompt: Optional[str] = None,

        sessions: Optional[Sequence[str]] = None,

    ) -> Dict[str, object]:

        start_dt = _normalize_date(start_date) if start_date else None

        end_dt = _normalize_date(end_date) if end_date else None



        dataset, stats = self.dataset_builder.build(

            start_dt,

            end_dt,

            incremental=incremental,

            allowed_sessions=sessions,

        )

        if not dataset:

            return {"summary": "未找到符合条件的聊天记录�?, "stats": stats}



        summary_engine = (

            self._build_custom_summary_engine(summary_prompt)

            if summary_prompt

            else self._ensure_summary_engine()

        )

        summary_text, meta = summary_engine.summarize(dataset)

        formatted = format_messages_with_group_labels(dataset)



        merged_questions: List[str] = []

        merged_questions.extend(self.config.custom_questions or [])

        merged_questions.extend(_load_questions_from_file(self.config.questions_file))

        if questions:

            merged_questions.extend([q for q in questions if q])



        qa_engine = self._ensure_qa_engine()

        qa_results = {}

        for question in merged_questions:

            answer, qa_meta = qa_engine.answer(formatted, question)

            qa_results[question] = {"answer": answer, "meta": qa_meta}



        output_path = None

        history_path = None

        if save_markdown:

            output_path, history_path = self._write_markdown(

                summary_text,

                qa_results,

                stats,

                start_label=start_date,

                end_label=end_date,

            )



        self.state.save()



        return {

            "summary": summary_text,

            "stats": stats,

            "meta": meta,

            "qa": qa_results,

            "output": str(output_path) if output_path else None,

            "history_file": str(history_path) if history_path else None,

        }



    def _write_markdown(

        self,

        summary_text: str,

        qa_results: Dict[str, Dict[str, object]],

        stats: List[Dict[str, object]],

        *,

        start_label: Optional[str] = None,

        end_label: Optional[str] = None,

    ) -> Tuple[Path, Optional[Path]]:

        qa_section = ""

        if qa_results:

            qa_lines = ["## 自定义问答\n"]

            for question, payload in qa_results.items():

                qa_lines.append(f"### 问题：{question}\n")

                qa_lines.append(payload["answer"])

                qa_lines.append("")

            qa_section = "\n".join(qa_lines)



        stats_lines = []

        if stats:

            stats_lines.append("## 会话统计\n")

            for item in stats:

                stats_lines.append(

                    f"- {item['display_name']}：新�?{item['messages']} 条（最后时间戳 {item['last_timestamp']}�?

                )



        combined = "\n\n".join(

            section

            for section in [

                summary_text,

                qa_section,

                "\n".join(stats_lines),

            ]

            if section

        )

        base_path = Path(self.config.summary_output)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        if base_path.suffix:

            output_path = base_path.with_name(f"{base_path.stem}_{timestamp}{base_path.suffix}")

        else:

            output_path = base_path / f"summary_{timestamp}.md"

        output_path.parent.mkdir(parents=True, exist_ok=True)

        legacy_save_summary(combined, output_file=str(output_path), duration_seconds=None)

        history_path = self._write_history_archive(combined, start_label, end_label)

        return output_path, history_path



    def _write_history_archive(

        self,

        content: str,

        start_label: Optional[str],

        end_label: Optional[str],

    ) -> Optional[Path]:

        if not content:

            return None

        history_dir = self.config.summary_history_dir

        history_dir.mkdir(parents=True, exist_ok=True)

        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        range_label = _safe_filename(start_label or "begin", end_label or "end")

        filename = f"{stamp}_{range_label}.md"

        history_path = history_dir / filename

        with open(history_path, "w", encoding="utf-8") as f:

            f.write(content)

        return history_path



    def _ensure_llm(self):

        if self._llm is None:

            self._llm = build_llm(self.llm_config)

        return self._llm



    def _ensure_summary_engine(self) -> SummaryEngine:

        if self._summary_engine is None:

            self._summary_engine = SummaryEngine(

                self._ensure_llm(),

                self.summary_conf,

                prompts=self.prompt_set,

            )

        return self._summary_engine



    def _build_custom_summary_engine(self, summary_prompt: Optional[str]) -> SummaryEngine:

        if not summary_prompt:

            return self._ensure_summary_engine()

        prompt_override = PromptSet(

            summary_system=self.prompt_set.summary_system,

            summary_user=summary_prompt,

            reduce_system=self.prompt_set.reduce_system,

            reduce_user=self.prompt_set.reduce_user,

        )

        return SummaryEngine(

            self._ensure_llm(),

            self.summary_conf,

            prompts=prompt_override,

        )



    def _ensure_qa_engine(self) -> QuestionAnsweringEngine:

        if self._qa_engine is None:

            self._qa_engine = QuestionAnsweringEngine(

                self._ensure_llm(),

                self.qa_conf,

                prompts=self.qa_prompt_set,

            )

        return self._qa_engine



    # =============== 新增：供 UI 使用的便捷方�?===============

    def list_sessions(self) -> List[Dict[str, object]]:

        """列出已导出的会话及其基础信息�?""

        return self.dataset_builder.list_sessions_metadata()



    def run_full_refresh(

        self,

        *,

        auto_launch_key: bool = True,

        wait_seconds: int = 90,

        poll_interval: int = 3,

        export_args: Optional[Sequence[str]] = None,

    ) -> Dict[str, object]:

        """一键执行：同步密钥、触发导出并刷新数据集�?""

        result: Dict[str, object] = {

            "key": None,

            "export": False,

            "sessions": 0,

            "messages": 0,

        }



        try:

            key_payload = self.refresh_key(

                auto_launch=auto_launch_key,

                wait_seconds=wait_seconds,

                poll_interval=poll_interval,

            )

            result["key"] = {

                "timestamp": key_payload.timestamp,

                "db_key": key_payload.db_key,

            }

        except Exception as exc:

            result["key_error"] = str(exc)



        export_ok = self.trigger_export(extra_args=export_args)

        result["export"] = export_ok



        dataset, stats = self.dataset_builder.build(None, None, incremental=False)

        result["sessions"] = len(stats)

        result["messages"] = sum(int(item.get("messages", 0) or 0) for item in stats)

        result["dataset_ready"] = bool(dataset)



        return result



    def list_export_states(self) -> List[Dict[str, object]]:

        """读取 .export_state 信息，结合会话元数据返回导出批次状态�?""

        entries: List[Dict[str, object]] = []

        for meta in self.dataset_builder.list_sessions_metadata():

            json_path = Path(str(meta.get("file")))

            state_path = Path(str(meta.get("state_file"))) if meta.get("state_file") else json_path.with_name(

                json_path.name + ".export_state"

            )

            state_info = ExportStateInfo.from_path(state_path)

            entry = dict(meta)

            entry.update(

                {

                    "state_file_exists": state_path.exists(),

                    "state_file": str(state_path),

                    "last_export_time": (state_info.last_export_time if state_info else None)

                    or _format_timestamp(meta.get("last_timestamp")),

                    "total_exported": state_info.total_count if state_info else meta.get("messages", 0),

                    "last_added_count": state_info.added_count if state_info else None,

                }

            )

            entries.append(entry)

        return entries



    def get_status(self) -> Dict[str, object]:

        """汇总密钥、导出、总结文件等整体状态，供欢迎页展示�?""

        try:

            key_payload = self.key_bridge.load_keys()

        except Exception:

            key_payload = None

        pref_path = self.config.wx_key_shared_prefs

        pref_exists = bool(pref_path and pref_path.exists())



        sessions_meta = self.dataset_builder.list_sessions_metadata()

        export_states = self.list_export_states()

        total_sessions = len(sessions_meta)

        total_messages = sum(int(meta.get("messages", 0) or 0) for meta in sessions_meta)

        last_export_time = None

        candidate_times = [state.get("last_export_time") for state in export_states if state.get("last_export_time")]

        if candidate_times:

            last_export_time = max(candidate_times)



        summary_history_preview = self.list_summary_history(limit=5)

        summary_output = self.config.summary_output

        summary_output_exists = summary_output.exists()

        summary_output_mtime = (

            datetime.fromtimestamp(summary_output.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")

            if summary_output_exists

            else None

        )



        return {

            "key": {

                "db_key": key_payload.db_key if key_payload else None,

                "timestamp": key_payload.timestamp if key_payload else None,

                "pref_path": str(pref_path) if pref_path else None,

                "pref_exists": pref_exists,

            },

            "export": {

                "export_dir": str(self.config.export_dir),

                "exists": self.config.export_dir.exists(),

                "sessions": total_sessions,

                "messages": total_messages,

                "last_export_time": last_export_time,

            },

            "summary": {

                "output_path": str(summary_output),

                "output_exists": summary_output_exists,

                "last_modified": summary_output_mtime,

                "history_dir": str(self.config.summary_history_dir),

                "history_exists": self.config.summary_history_dir.exists(),

                "history_preview": summary_history_preview,

            },

            "environment": {

                "wechat_installations": _auto_detect_wechat_installations(self.config.wechat_install_path),

                "wechat_data_dirs": _auto_detect_wechat_data_dirs(self.config.wechat_data_path),

            },

        }



    def describe_session(

        self,

        session_file: str,

        *,

        start_date: Optional[str] = None,

        end_date: Optional[str] = None,

    ) -> Dict[str, object]:

        """返回指定会话在给定时间范围内的详细统计�?""

        json_path = Path(session_file).expanduser()

        start_dt = _normalize_date(start_date) if start_date else None

        end_dt = _normalize_date(end_date) if end_date else None

        session_info, messages = self.dataset_builder.load_filtered_messages(json_path, start_dt, end_dt)

        metrics = self._summarize_session_messages(messages)

        session_id = session_info.get("wxid") or session_info.get("username") or json_path.stem

        session_type = session_info.get("type")

        if not session_type and isinstance(session_id, str):

            session_type = "群聊" if "@chatroom" in session_id else "单聊"

        session_meta = {

            "display_name": session_info.get("displayName") or session_info.get("nickname") or json_path.stem,

            "session_id": session_id,

            "type": session_type,

            "member_count": session_info.get("memberCount") or session_info.get("membercount"),

            "file": str(json_path),

        }

        return {

            "session": session_meta,

            "filters": {"start_date": start_date, "end_date": end_date},

            "metrics": metrics,

        }



    def list_summary_history(self, limit: Optional[int] = None) -> List[Dict[str, object]]:

        """列出总结历史文件（Markdown/Txt）�?""

        history_dir = self.config.summary_history_dir

        if not history_dir.exists():

            return []

        files = sorted(

            [p for p in history_dir.glob("*") if p.suffix.lower() in {".md", ".txt"}],

            key=lambda p: p.stat().st_mtime,

            reverse=True,

        )

        entries: List[Dict[str, object]] = []

        for file in files:

            stat = file.stat()

            entries.append(

                {

                    "name": file.name,

                    "path": str(file),

                    "modified": datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S"),

                    "size": stat.st_size,

                }

            )

            if limit and len(entries) >= limit:

                break

        return entries



    def read_summary_history(self, path: str) -> str:

        """读取历史总结文件内容�?""

        file_path = Path(path).expanduser()

        if not file_path.exists():

            raise FileNotFoundError(path)

        with open(file_path, "r", encoding="utf-8") as f:

            return f.read()



    def test_llm_connection(self) -> Tuple[bool, str]:

        """尝试轻量检测当�?LLM 配置是否可用，优先探�?HTTP 接口�?""

        base_url = self.llm_config.base_url or os.environ.get("LLM_BASE_URL") or "https://api.openai.com/v1"

        api_key = self.llm_config.api_key or os.environ.get("LLM_API_KEY")

        timeout = min(self.llm_config.timeout or 8, 5)



        if requests is not None:

            headers = {"Content-Type": "application/json"}

            if api_key:

                headers["Authorization"] = f"Bearer {api_key}"



            completion_url = _build_completion_url(base_url)

            payload = {

                "model": self.llm_config.model,

                "messages": [

                    {"role": "system", "content": "ping"},

                    {"role": "user", "content": "ping"},

                ],

                "max_tokens": 1,

                "temperature": 0,

                "stream": False,

            }

            try:

                response = requests.post(completion_url, json=payload, headers=headers, timeout=timeout)

            except Exception as exc:

                return False, str(exc)



            if response.status_code < 400:

                return True, f"已连�?{self.llm_config.model}"

            error_text = (response.text or response.reason or "请求失败").replace("

", " ").strip()

            if len(error_text) > 200:

                error_text = error_text[:200] + '...'

            return False, f"{response.status_code}: {error_text}"



        try:

            temp_conf = LLMConfig(

                api_key=self.llm_config.api_key,

                base_url=self.llm_config.base_url,

                model=self.llm_config.model,

                temperature=0.0,

                timeout=timeout,

            )

            client = build_llm(temp_conf)

            client.invoke("ping")

            return True, "LLM 接口可用"

        except Exception as exc:  # pragma: no cover - 网络/环境问题

            return False, str(exc)





    def _summarize_session_messages(self, messages: List[Dict[str, object]]) -> Dict[str, object]:

        total = len(messages)

        stats = {

            "total_messages": total,

            "active_days": 0,

            "average_per_day": 0.0,

            "first_message": None,

            "last_message": None,

            "message_types": [],

            "direction": {"sent": 0, "received": 0, "sent_ratio": 0.0},

            "participants": {"unique": 0, "top": []},

        }

        if not messages:

            return stats



        type_counter: Counter[str] = Counter()

        direction_counter: Counter[str] = Counter()

        participant_counter: Counter[str] = Counter()

        days: set[str] = set()

        first_dt: Optional[datetime] = None

        last_dt: Optional[datetime] = None



        for msg in messages:

            dt, _ts = self.dataset_builder._extract_datetime(msg)

            if dt:

                days.add(dt.strftime("%Y-%m-%d"))

                if first_dt is None or dt < first_dt:

                    first_dt = dt

                if last_dt is None or dt > last_dt:

                    last_dt = dt

            msg_type = _categorize_message_type(msg)

            type_counter[msg_type] += 1



            sender = str(msg.get("senderDisplayName") or msg.get("senderUsername") or "未知联系�?)

            participant_counter[sender] += 1



            is_send = msg.get("isSend")

            sent_flag = False

            if isinstance(is_send, (int, float)):

                sent_flag = int(is_send) != 0

            elif isinstance(is_send, str):

                sent_flag = is_send.strip().lower() in {"1", "true", "yes"}

            elif isinstance(is_send, bool):

                sent_flag = is_send

            direction_counter["sent" if sent_flag else "received"] += 1



        active_days = len(days)

        stats["active_days"] = active_days

        stats["average_per_day"] = round(total / active_days, 2) if active_days else float(total)

        stats["first_message"] = first_dt.strftime("%Y-%m-%d %H:%M:%S") if first_dt else None

        stats["last_message"] = last_dt.strftime("%Y-%m-%d %H:%M:%S") if last_dt else None



        stats["message_types"] = [

            {"type": name, "count": count, "ratio": round(count / total, 3)}

            for name, count in type_counter.most_common()

        ]



        sent = direction_counter.get("sent", 0)

        received = direction_counter.get("received", 0)

        stats["direction"] = {

            "sent": sent,

            "received": received,

            "sent_ratio": round(sent / total, 3) if total else 0.0,

        }



        stats["participants"] = {

            "unique": len(participant_counter),

            "top": [

                {"name": name, "count": count, "ratio": round(count / total, 3)}

                for name, count in participant_counter.most_common(10)

            ],

        }



        return stats



    def export_filtered_chats(

        self,

        *,

        selected: Optional[Sequence[str]] = None,

        files: Optional[Sequence[str]] = None,

        start_date: Optional[str] = None,

        end_date: Optional[str] = None,

        output_dir: Optional[str] = None,

        single_file: bool = True,

    ) -> Dict[str, object]:

        """从导出的 JSON 中按会话和时间范围导出到本地 JSON�?


        - selected: 选择的会�?display_name 列表；为空则使用全部

        - files: 直接通过 json 文件路径选择会话，优先级高于 selected，用于避免重名冲�?
        - 时间范围: 字符串日期，支持 _normalize_date 的格�?
        - output_dir: 导出目录；默认使�?export_dir 下的 export 子目�?
        - single_file: 是否合并为单�?JSON（否则分文件输出�?
        返回：{"files": [路径...], "count": 总消息数}

        """

        start_dt = _normalize_date(start_date) if start_date else None

        end_dt = _normalize_date(end_date) if end_date else None

        export_base = Path(output_dir).expanduser().resolve() if output_dir else (self.config.export_dir / "export")

        export_base.mkdir(parents=True, exist_ok=True)



        sessions = self.dataset_builder.list_sessions_metadata()

        selected_set = set(selected or [s["display_name"] for s in sessions])

        file_set = {str(Path(f).expanduser().resolve()) for f in files or []}



        all_records: List[Dict[str, object]] = []

        written_files: List[str] = []

        total = 0



        for meta in sessions:

            display_name = str(meta.get("display_name") or "")

            json_path = Path(str(meta.get("file")))

            resolved_json = str(json_path.resolve())

            if file_set:

                if resolved_json not in file_set:

                    continue

            elif display_name not in selected_set:

                continue

            data = self.dataset_builder._load_json(json_path) or {}

            messages = data.get("messages") if isinstance(data, dict) else None

            if not isinstance(messages, list):

                continue

            filtered: List[Dict[str, object]] = []

            for msg in messages:

                dt, _ts = self.dataset_builder._extract_datetime(msg)

                if start_dt and dt and dt < start_dt:

                    continue

                if end_dt and dt and dt > end_dt + timedelta(days=1) - timedelta(seconds=1):

                    continue

                filtered.append(msg)



            total += len(filtered)

            record = {

                "session": data.get("session", {}),

                "messages": filtered,

            }

            if single_file:

                all_records.append({"display_name": display_name, **record})

            else:

                out_file = export_base / f"{display_name}.json"

                with open(out_file, "w", encoding="utf-8") as f:

                    json.dump(record, f, ensure_ascii=False, indent=2)

                written_files.append(str(out_file))



        if single_file:

            # 合并写出一个文�?
            stamp = datetime.now().strftime("%Y%m%d_%H%M%S")

            out_file = export_base / f"export_{stamp}.json"

            with open(out_file, "w", encoding="utf-8") as f:

                json.dump({"sessions": all_records}, f, ensure_ascii=False, indent=2)

            written_files.append(str(out_file))



        return {"files": written_files, "count": total}



    def analyze_stats(

        self,

        *,

        start_date: Optional[str] = None,

        end_date: Optional[str] = None,

        top_n: int = 10,

        session_types: Optional[Sequence[str]] = None,

    ) -> Dict[str, object]:

        """简单统计：按会话消息数排序，并返回�?N 个�?""

        start_dt = _normalize_date(start_date) if start_date else None

        end_dt = _normalize_date(end_date) if end_date else None

        sessions = self.dataset_builder.list_sessions_metadata()



        results: List[Dict[str, object]] = []

        total_msgs = 0

        allowed_types = _normalize_session_filters(session_types)

        breakdown = {

            "group": {"sessions": 0, "messages": 0},

            "single": {"sessions": 0, "messages": 0},

        }

        for meta in sessions:

            json_path = Path(str(meta.get("file")))

            data = self.dataset_builder._load_json(json_path) or {}

            messages = data.get("messages") if isinstance(data, dict) else None

            if not isinstance(messages, list):

                continue

            session_type = str(meta.get("session_type") or "")

            category_key = _categorize_session(meta)

            if allowed_types and category_key not in allowed_types:

                continue

            cnt = 0

            sent_count = 0

            received_count = 0

            for msg in messages:

                dt, _ts = self.dataset_builder._extract_datetime(msg)

                if start_dt and dt and dt < start_dt:

                    continue

                if end_dt and dt and dt > end_dt + timedelta(days=1) - timedelta(seconds=1):

                    continue

                cnt += 1

                direction = msg.get("isSend")

                sent_flag = False

                if isinstance(direction, (int, float)):

                    sent_flag = int(direction) != 0

                elif isinstance(direction, str):

                    sent_flag = direction.strip().lower() in {"1", "true", "yes"}

                if sent_flag:

                    sent_count += 1

                else:

                    received_count += 1

            total_msgs += cnt

            results.append(

                {

                    "session_id": meta.get("session_id"),

                    "display_name": meta.get("display_name"),

                    "messages": cnt,

                    "session_type": session_type,

                    "category": category_key,

                    "file": meta.get("file"),

                    "sent_messages": sent_count,

                    "received_messages": received_count,

                }

            )

            breakdown.setdefault(category_key, {"sessions": 0, "messages": 0})

            if cnt:

                breakdown[category_key]["sessions"] += 1

                breakdown[category_key]["messages"] += cnt



        results.sort(key=lambda x: int(x.get("messages", 0)), reverse=True)

        return {

            "total_messages": total_msgs,

            "session_count": len(results),

            "window": {"start": start_date, "end": end_date},

            "top": results[: max(1, top_n)],

            "all": results,

            "breakdown": breakdown,

        }





__all__ = ["WxAgentPipeline"]

