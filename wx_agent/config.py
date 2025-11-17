from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

from .path_utils import resource_path


def _expand_path(value: Optional[str]) -> Optional[Path]:
    if not value:
        return None
    expanded = os.path.expandvars(os.path.expanduser(value))
    path = Path(expanded)
    if not path.is_absolute():
        return (resource_path() / path).resolve()
    return path.resolve()


@dataclass
class CommandSpec:
    """CLI 命令配置"""

    path: Optional[str] = None
    args: List[str] = field(default_factory=list)
    cwd: Optional[str] = None
    env: Dict[str, str] = field(default_factory=dict)

    def resolved_path(self) -> Optional[Path]:
        return _expand_path(self.path)

    def as_subprocess(self) -> Optional[List[str]]:
        exe = self.resolved_path()
        if not exe:
            return None
        return [str(exe), *self.args]

    @classmethod
    def from_dict(cls, data: Optional[Dict[str, Any]]) -> "CommandSpec":
        if not data:
            return cls()
        return cls(
            path=data.get("path"),
            args=list(data.get("args") or []),
            cwd=data.get("cwd"),
            env=dict(data.get("env") or {}),
        )


@dataclass
class PromptOverrides:
    summary_system: Optional[str] = None
    summary_user: Optional[str] = None
    reduce_system: Optional[str] = None
    reduce_user: Optional[str] = None
    qa_map_system: Optional[str] = None
    qa_map_user: Optional[str] = None
    qa_reduce_system: Optional[str] = None
    qa_reduce_user: Optional[str] = None


@dataclass
class PipelineConfig:
    export_dir: Path
    summary_output: Path
    summary_history_dir: Path
    state_file: Path
    wechat_install_path: Optional[Path]
    wechat_data_path: Optional[Path]
    wx_key_shared_prefs: Optional[Path]
    wx_key_command: CommandSpec
    echotrace_command: CommandSpec
    llm_model: str
    llm_base_url: Optional[str]
    llm_api_key: Optional[str]
    llm_temperature: float
    llm_timeout: Optional[float]
    max_tokens: int
    overlap_tokens: int
    api_max_tokens: int
    map_concurrency: int
    qa_context_tokens: int
    qa_overlap_tokens: int
    qa_max_batches: int
    prompts: PromptOverrides
    custom_questions: List[str]
    questions_file: Optional[Path]
    config_file: Path = field(init=False, repr=False, default=None)

    @classmethod
    def load(cls, path: Optional[str] = None) -> "PipelineConfig":
        config_path = (
            Path(path).expanduser().resolve()
            if path
            else Path(__file__).with_name("config.json")
        )

        data: Dict[str, Any] = {}
        if config_path.exists():
            with open(config_path, "r", encoding="utf-8") as f:
                data = json.load(f)

        export_dir = _expand_path(
            data.get("export_dir") or os.environ.get("WX_AGENT_EXPORT_DIR") or "../output_test"
        )
        summary_output = _expand_path(
            data.get("summary_output") or os.environ.get("WX_AGENT_SUMMARY_FILE") or "../summary_result.md"
        )
        summary_history = _expand_path(
            data.get("summary_history_dir") or os.environ.get("WX_AGENT_SUMMARY_HISTORY")
        )
        state_file = _expand_path(
            data.get("state_file") or os.environ.get("WX_AGENT_STATE_FILE") or "../.wx_agent_state.json"
        )
        wechat_install = _expand_path(
            data.get("wechat_install_path") or os.environ.get("WX_AGENT_WECHAT_INSTALL")
        )
        wechat_data = _expand_path(
            data.get("wechat_data_path") or os.environ.get("WX_AGENT_WECHAT_DATA")
        )
        wx_key_shared = _expand_path(
            data.get("wx_key_shared_prefs")
            or os.environ.get("WX_KEY_SHARED_PREFS")
            or r"%APPDATA%\com.example\wx_key\shared_preferences.json"
        )

        prompts = PromptOverrides(**(data.get("prompts") or {}))
        custom_questions = list(data.get("custom_questions") or [])
        questions_file = _expand_path(data.get("questions_file"))

        wx_key_cmd_data = dict(data.get("wx_key_command") or {})
        if not wx_key_cmd_data.get("path"):
            wx_key_cmd_data["path"] = str(resource_path("bin", "wx_key", "wx_key.exe"))

        echotrace_cmd_data = dict(data.get("echotrace_command") or {})
        if not echotrace_cmd_data.get("path"):
            echotrace_cmd_data["path"] = str(resource_path("bin", "echotrace", "echotrace.exe"))

        base_history_dir: Optional[Path] = None
        if summary_output:
            base_history_dir = summary_output if summary_output.is_dir() else summary_output.parent
        summary_history_dir = summary_history or (base_history_dir or Path.cwd()) / "summary_history"

        instance = cls(
            export_dir=export_dir,
            summary_output=summary_output,
            summary_history_dir=summary_history_dir.resolve(),
            state_file=state_file,
            wechat_install_path=wechat_install,
            wechat_data_path=wechat_data,
            wx_key_shared_prefs=wx_key_shared,
            wx_key_command=CommandSpec.from_dict(wx_key_cmd_data),
            echotrace_command=CommandSpec.from_dict(echotrace_cmd_data),
            llm_model=data.get("llm_model") or os.environ.get("LLM_MODEL") or "deepseek-v3-1-terminus",
            llm_base_url=data.get("llm_base_url") or os.environ.get("LLM_BASE_URL"),
            llm_api_key=data.get("llm_api_key") or os.environ.get("LLM_API_KEY"),
            llm_temperature=float(
                data.get("llm_temperature")
                or os.environ.get("LLM_TEMPERATURE")
                or 0.7
            ),
            llm_timeout=float(data.get("llm_timeout")) if data.get("llm_timeout") is not None else None,
            max_tokens=int(data.get("max_tokens") or os.environ.get("WX_AGENT_MAX_TOKENS", 60000)),
            overlap_tokens=int(data.get("overlap_tokens") or os.environ.get("WX_AGENT_OVERLAP_TOKENS", 800)),
            api_max_tokens=int(data.get("api_max_tokens") or os.environ.get("WX_AGENT_API_MAX_TOKENS", 98304)),
            map_concurrency=int(data.get("map_concurrency") or os.environ.get("WX_AGENT_MAP_CONCURRENCY", 3)),
            qa_context_tokens=int(
                data.get("qa_context_tokens") or os.environ.get("WX_AGENT_QA_CONTEXT_TOKENS", 20000)
            ),
            qa_overlap_tokens=int(
                data.get("qa_overlap_tokens") or os.environ.get("WX_AGENT_QA_OVERLAP_TOKENS", 400)
            ),
            qa_max_batches=int(
                data.get("qa_max_batches") or os.environ.get("WX_AGENT_QA_MAX_BATCHES", 4)
            ),
            prompts=prompts,
            custom_questions=custom_questions,
            questions_file=questions_file,
        )
        instance.config_file = config_path
        return instance

    def to_dict(self) -> Dict[str, Any]:
        return {
            "export_dir": str(self.export_dir),
            "summary_output": str(self.summary_output),
            "summary_history_dir": str(self.summary_history_dir),
            "state_file": str(self.state_file),
            "wechat_install_path": str(self.wechat_install_path) if self.wechat_install_path else None,
            "wechat_data_path": str(self.wechat_data_path) if self.wechat_data_path else None,
            "wx_key_shared_prefs": str(self.wx_key_shared_prefs) if self.wx_key_shared_prefs else None,
            "wx_key_command": {
                "path": self.wx_key_command.path,
                "args": list(self.wx_key_command.args),
                "cwd": self.wx_key_command.cwd,
                "env": dict(self.wx_key_command.env),
            },
            "echotrace_command": {
                "path": self.echotrace_command.path,
                "args": list(self.echotrace_command.args),
                "cwd": self.echotrace_command.cwd,
                "env": dict(self.echotrace_command.env),
            },
            "llm_model": self.llm_model,
            "llm_base_url": self.llm_base_url,
            "llm_api_key": self.llm_api_key,
            "llm_temperature": self.llm_temperature,
            "llm_timeout": self.llm_timeout,
            "max_tokens": self.max_tokens,
            "overlap_tokens": self.overlap_tokens,
            "api_max_tokens": self.api_max_tokens,
            "map_concurrency": self.map_concurrency,
            "qa_context_tokens": self.qa_context_tokens,
            "qa_overlap_tokens": self.qa_overlap_tokens,
            "qa_max_batches": self.qa_max_batches,
            "prompts": {
                "summary_system": self.prompts.summary_system,
                "summary_user": self.prompts.summary_user,
                "reduce_system": self.prompts.reduce_system,
                "reduce_user": self.prompts.reduce_user,
                "qa_map_system": self.prompts.qa_map_system,
                "qa_map_user": self.prompts.qa_map_user,
                "qa_reduce_system": self.prompts.qa_reduce_system,
                "qa_reduce_user": self.prompts.qa_reduce_user,
            },
            "custom_questions": list(self.custom_questions),
            "questions_file": str(self.questions_file) if self.questions_file else None,
        }

    def save(self, path: Optional[str] = None) -> Path:
        """Write current config to JSON file for the UI Settings page."""
        target = (
            Path(path).expanduser().resolve()
            if path
            else self.config_file
        )
        target.parent.mkdir(parents=True, exist_ok=True)
        with open(target, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, ensure_ascii=False, indent=2)
        self.config_file = target
        return target


__all__ = [
    "CommandSpec",
    "PromptOverrides",
    "PipelineConfig",
]
