from __future__ import annotations

import argparse
import asyncio
import json
import logging
import threading
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence

import uvicorn
from fastapi import Body, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from .config import PipelineConfig
from .pipeline import KeyPayload, WxAgentPipeline

logger = logging.getLogger(__name__)


def _deep_merge_dict(target: Dict[str, Any], updates: Dict[str, Any]) -> Dict[str, Any]:
    for key, value in updates.items():
        if (
            key in target
            and isinstance(target[key], dict)
            and isinstance(value, dict)
        ):
            target[key] = _deep_merge_dict(dict(target[key]), value)
        else:
            target[key] = value
    return target


def _serialize_key(payload: KeyPayload) -> Dict[str, Any]:
    return {
        "db_key": payload.db_key,
        "image_xor_key": payload.image_xor_key,
        "image_aes_key": payload.image_aes_key,
        "timestamp": payload.timestamp,
        "raw": payload.raw,
    }


class PipelineService:
    """Wrap WxAgentPipeline with thread-safe helpers for FastAPI."""

    def __init__(self, config_path: Optional[str] = None):
        self.config_path = (
            Path(config_path).expanduser().resolve()
            if config_path
            else Path(__file__).with_name("config.json")
        )
        self._reload_lock = threading.Lock()
        self._pipeline_lock = threading.Lock()
        self.reload()

    def reload(self) -> PipelineConfig:
        with self._reload_lock:
            self.config = PipelineConfig.load(str(self.config_path))
            self.config_path = self.config.config_file
            self.pipeline = WxAgentPipeline(self.config)
            logger.info("Pipeline reloaded using config %s", self.config_path)
            return self.config

    def _call_pipeline(self, func: Callable[[WxAgentPipeline], Any]) -> Any:
        with self._pipeline_lock:
            return func(self.pipeline)

    async def run(self, func: Callable[[WxAgentPipeline], Any]) -> Any:
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, lambda: self._call_pipeline(func))

    def read_raw_config(self) -> Dict[str, Any]:
        if self.config_path.exists():
            with open(self.config_path, "r", encoding="utf-8") as f:
                return json.load(f)
        return {}

    def update_config(self, updates: Dict[str, Any]) -> Dict[str, Any]:
        raw = self.read_raw_config()
        merged = _deep_merge_dict(raw, updates)
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.config_path, "w", encoding="utf-8") as f:
            json.dump(merged, f, ensure_ascii=False, indent=2)
        self.reload()
        return merged


class RefreshKeyRequest(BaseModel):
    auto_launch: bool = False
    wait_seconds: int = 120
    poll_interval: int = 5


class TriggerExportRequest(BaseModel):
    extra_args: Optional[List[str]] = Field(
        default=None,
        description="Additional CLI args appended to the echotrace command.",
    )
    silent: bool = True


class FullRefreshRequest(BaseModel):
    auto_launch_key: bool = True
    wait_seconds: int = 90
    poll_interval: int = 3
    export_args: Optional[List[str]] = None


class SummarizeRequest(BaseModel):
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    incremental: bool = True
    questions: Optional[List[str]] = None
    save_markdown: bool = True
    summary_prompt: Optional[str] = None
    sessions: Optional[List[str]] = None


class DescribeSessionRequest(BaseModel):
    file: str
    start_date: Optional[str] = None
    end_date: Optional[str] = None


class ExportFilteredRequest(BaseModel):
    selected: Optional[List[str]] = None
    files: Optional[List[str]] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    output_dir: Optional[str] = None
    single_file: bool = True


class AnalyzeRequest(BaseModel):
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    top_n: int = 10
    session_types: Optional[List[str]] = None


class ConfigUpdateRequest(BaseModel):
    values: Dict[str, Any] = Field(default_factory=dict)


class LaunchWxKeyRequest(BaseModel):
    wait: bool = False
    extra_args: Optional[List[str]] = None


class TestLLMRequest(BaseModel):
    base_url: Optional[str] = None
    model: Optional[str] = None
    api_key: Optional[str] = None


def _register_routes(app: FastAPI, service: PipelineService) -> None:
    @app.get("/health")
    async def health() -> Dict[str, str]:
        return {"status": "ok"}

    @app.get("/status")
    async def status() -> Dict[str, Any]:
        return await service.run(lambda pipeline: pipeline.get_status())

    @app.post("/refresh-key")
    async def refresh_key(payload: RefreshKeyRequest) -> Dict[str, Any]:
        logger.info("Refreshing key with auto_launch=%s", payload.auto_launch)
        try:
            result = await service.run(
                lambda pipeline: pipeline.refresh_key(
                    auto_launch=payload.auto_launch,
                    wait_seconds=payload.wait_seconds,
                    poll_interval=payload.poll_interval,
                )
            )
            logger.info("Key refresh completed successfully")
            return _serialize_key(result)
        except FileNotFoundError as exc:
            logger.error("Key file not found: %s", exc)
            raise HTTPException(status_code=404, detail=f"Key file not found: {str(exc)}") from exc
        except PermissionError as exc:
            logger.error("Permission denied: %s", exc)
            raise HTTPException(status_code=403, detail=f"Permission denied: {str(exc)}") from exc
        except subprocess.CalledProcessError as exc:
            logger.error("wx_key command failed: %s", exc)
            raise HTTPException(status_code=500, detail=f"wx_key command failed: {str(exc)}") from exc
        except RuntimeError as exc:
            logger.error("Runtime error during key refresh: %s", exc)
            raise HTTPException(status_code=400, detail=f"Runtime error: {str(exc)}") from exc
        except Exception as exc:  # pylint: disable=broad-except
            logger.exception("Key refresh failed")
            raise HTTPException(status_code=500, detail=f"Key refresh error: {str(exc)}") from exc

    @app.post("/wx-key/launch")
    async def launch_wx_key(payload: LaunchWxKeyRequest) -> Dict[str, Any]:
        logger.info("Launching wx_key with extra_args=%s, wait=%s", payload.extra_args, payload.wait)
        try:
            result = await service.run(
                lambda pipeline: pipeline.launch_wx_key(
                    extra_args=payload.extra_args,
                    wait=payload.wait,
                )
            )
            logger.info("wx_key launched successfully")
            return {"pid": getattr(result, "pid", None), "waited": payload.wait}
        except FileNotFoundError as exc:
            logger.error("wx_key executable not found: %s", exc)
            raise HTTPException(status_code=404, detail=f"wx_key executable not found: {str(exc)}") from exc
        except PermissionError as exc:
            logger.error("Permission denied: %s", exc)
            raise HTTPException(status_code=403, detail=f"Permission denied: {str(exc)}") from exc
        except Exception as exc:  # pylint: disable=broad-except
            logger.exception("Failed to launch wx_key")
            raise HTTPException(status_code=500, detail=f"Launch error: {str(exc)}") from exc

    @app.post("/export")
    async def trigger_export(payload: TriggerExportRequest) -> Dict[str, Any]:
        logger.info("Triggering export with extra_args=%s", payload.extra_args)
        try:
            ok = await service.run(
                lambda pipeline: pipeline.trigger_export(
                    extra_args=payload.extra_args,
                    silent=payload.silent,
                )
            )
            logger.info("Export triggered successfully: %s", ok)
            return {"success": ok}
        except FileNotFoundError as exc:
            logger.error("Export command or path not found: %s", exc)
            raise HTTPException(status_code=404, detail=f"Export command not found: {str(exc)}") from exc
        except PermissionError as exc:
            logger.error("Permission denied during export: %s", exc)
            raise HTTPException(status_code=403, detail=f"Permission denied: {str(exc)}") from exc
        except subprocess.CalledProcessError as exc:
            logger.error("Export command failed: %s", exc)
            raise HTTPException(status_code=500, detail=f"Export command failed: {str(exc)}") from exc
        except Exception as exc:  # pylint: disable=broad-except
            logger.exception("Export failed")
            raise HTTPException(status_code=500, detail=f"Export error: {str(exc)}") from exc

    @app.post("/full-refresh")
    async def run_full_refresh(payload: FullRefreshRequest) -> Dict[str, Any]:
        return await service.run(
            lambda pipeline: pipeline.run_full_refresh(
                auto_launch_key=payload.auto_launch_key,
                wait_seconds=payload.wait_seconds,
                poll_interval=payload.poll_interval,
                export_args=payload.export_args,
            )
        )

    @app.get("/sessions")
    async def list_sessions() -> List[Dict[str, Any]]:
        return await service.run(lambda pipeline: pipeline.list_sessions())

    @app.get("/export/states")
    async def export_states() -> List[Dict[str, Any]]:
        return await service.run(lambda pipeline: pipeline.list_export_states())

    @app.post("/sessions/describe")
    async def describe_session(payload: DescribeSessionRequest) -> Dict[str, Any]:
        return await service.run(
            lambda pipeline: pipeline.describe_session(
                payload.file,
                start_date=payload.start_date,
                end_date=payload.end_date,
            )
        )

    @app.post("/summary/run")
    async def run_summary(payload: SummarizeRequest) -> Dict[str, Any]:
        logger.info("Starting summary generation with params: %s", payload.model_dump_json())
        def _runner(pipeline: WxAgentPipeline) -> Dict[str, Any]:
            sessions = payload.sessions or None
            if sessions is not None and not any(sessions):
                sessions = None
            return pipeline.run(
                start_date=payload.start_date,
                end_date=payload.end_date,
                incremental=payload.incremental,
                questions=payload.questions or [],
                save_markdown=payload.save_markdown,
                summary_prompt=payload.summary_prompt,
                sessions=sessions,
            )

        try:
            result = await service.run(_runner)
            logger.info("Summary generation completed successfully")
            return result
        except FileNotFoundError as exc:
            logger.error("Session file not found: %s", exc)
            raise HTTPException(status_code=404, detail=f"Session data not found: {str(exc)}") from exc
        except PermissionError as exc:
            logger.error("Permission denied: %s", exc)
            raise HTTPException(status_code=403, detail=f"Permission denied: {str(exc)}") from exc
        except Exception as exc:  # pylint: disable=broad-except
            logger.exception("Summary generation failed")
            raise HTTPException(status_code=500, detail=f"Summary error: {str(exc)}") from exc

    @app.get("/summary/history")
    async def summary_history(limit: Optional[int] = Query(default=None)) -> List[Dict[str, Any]]:
        return await service.run(lambda pipeline: pipeline.list_summary_history(limit=limit))

    @app.get("/summary/history/content")
    async def summary_history_content(path: str) -> Dict[str, Any]:
        try:
            content = await service.run(lambda pipeline: pipeline.read_summary_history(path))
        except FileNotFoundError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return {"path": path, "content": content}

    @app.post("/summary/export")
    async def export_filtered(payload: ExportFilteredRequest) -> Dict[str, Any]:
        return await service.run(
            lambda pipeline: pipeline.export_filtered_chats(
                selected=payload.selected,
                files=payload.files,
                start_date=payload.start_date,
                end_date=payload.end_date,
                output_dir=payload.output_dir,
                single_file=payload.single_file,
            )
        )

    @app.post("/analysis/sessions")
    async def analyze_sessions(payload: AnalyzeRequest) -> Dict[str, Any]:
        logger.info("Starting session analysis with params: %s", payload.model_dump_json())
        try:
            result = await service.run(
                lambda pipeline: pipeline.analyze_stats(
                    start_date=payload.start_date,
                    end_date=payload.end_date,
                    top_n=payload.top_n,
                    session_types=payload.session_types,
                )
            )
            logger.info("Analysis completed successfully")
            return result
        except FileNotFoundError as exc:
            logger.error("Session file not found: %s", exc)
            raise HTTPException(status_code=404, detail=f"Session data not found: {str(exc)}") from exc
        except PermissionError as exc:
            logger.error("Permission denied: %s", exc)
            raise HTTPException(status_code=403, detail=f"Permission denied: {str(exc)}") from exc
        except subprocess.CalledProcessError as exc:
            logger.error("External command failed: %s", exc)
            raise HTTPException(status_code=500, detail=f"External command failed: {str(exc)}") from exc
        except Exception as exc:  # pylint: disable=broad-except
            logger.exception("Analysis failed with unexpected error")
            raise HTTPException(status_code=500, detail=f"Analysis error: {str(exc)}") from exc

    @app.post("/llm/test")
    async def test_llm(payload: Optional[TestLLMRequest] = Body(default=None)) -> Dict[str, Any]:
        overrides = payload.model_dump(exclude_none=True) if payload else {}
        ok, message = await service.run(
            lambda pipeline: pipeline.test_llm_connection(
                base_url=overrides.get("base_url"),
                model=overrides.get("model"),
                api_key=overrides.get("api_key"),
            )
        )
        return {"success": ok, "message": message}

    @app.get("/config")
    async def fetch_config() -> Dict[str, Any]:
        config = service.config
        return {"path": str(config.config_file), "data": config.to_dict()}

    @app.put("/config")
    async def update_config(payload: ConfigUpdateRequest) -> Dict[str, Any]:
        if not payload.values:
            raise HTTPException(status_code=400, detail="No config values provided.")
        updated = service.update_config(payload.values)
        return {"path": str(service.config_path), "data": updated}

    @app.post("/config/reload")
    async def reload_config() -> Dict[str, Any]:
        config = service.reload()
        return {"path": str(config.config_file), "data": config.to_dict()}


def create_app(config_path: Optional[str] = None) -> FastAPI:
    service = PipelineService(config_path)
    app = FastAPI(
        title="WXAgent Service",
        description="HTTP bridge that exposes WxAgentPipeline capabilities for the Flutter UI.",
        version="0.1.0",
    )
    app.state.service = service
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )
    _register_routes(app, service)
    return app


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the WXAgent FastAPI service.")
    parser.add_argument("--host", default="127.0.0.1", help="Server host (default 127.0.0.1).")
    parser.add_argument("--port", type=int, default=8000, help="Server port (default 8000).")
    parser.add_argument("--config", help="Custom config.json path.")
    parser.add_argument(
        "--reload",
        action="store_true",
        help="Enable uvicorn autoreload (development only).",
    )
    return parser


def main(argv: Optional[Sequence[str]] = None) -> None:
    args = _build_parser().parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    target_app = create_app(args.config)
    uvicorn.run(target_app, host=args.host, port=args.port, reload=args.reload)


app = create_app()

__all__ = ["create_app", "app", "main"]

if __name__ == "__main__":
    main()
