from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Dict

from .config import PipelineConfig
from .pipeline import WxAgentPipeline


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="wx-agent",
        description="整合 wx_key + echotrace + LLM 的聊天记录总结工具",
    )
    parser.add_argument(
        "--config",
        help="指定配置文件路径（默认 wx_agent/config.json）",
    )
    subparsers = parser.add_subparsers(dest="command")

    summarize = subparsers.add_parser("summarize", help="执行增量聊天记录总结")
    summarize.add_argument("--start-date", help="起始日期（YYYY-MM-DD）")
    summarize.add_argument("--end-date", help="结束日期（YYYY-MM-DD）")
    summarize.add_argument(
        "--full",
        action="store_true",
        help="忽略增量状态，重新汇总所有记录",
    )
    summarize.add_argument(
        "--question",
        action="append",
        dest="questions",
        help="追加自定义问题（可多次指定）",
    )
    summarize.add_argument(
        "--no-save",
        action="store_true",
        help="仅在终端输出结果，不写入 Markdown",
    )
    summarize.add_argument(
        "--json",
        action="store_true",
        help="以 JSON 格式打印结果，方便与其他工具集成",
    )

    refresh = subparsers.add_parser("refresh-key", help="读取 wx_key 导出的数据库密钥")
    refresh.add_argument(
        "--ensure",
        action="store_true",
        help="若未检测到密钥则尝试自动启动 wx_key 并等待写入",
    )
    refresh.add_argument(
        "--wait",
        type=int,
        default=120,
        help="配合 --ensure 使用时的最长等待秒数（默认120）",
    )
    refresh.add_argument(
        "--poll",
        type=int,
        default=5,
        help="配合 --ensure 时的轮询间隔秒数（默认5）",
    )

    subparsers.add_parser("export", help="调用 echotrace 命令执行导出")

    launch_wx_key = subparsers.add_parser("launch-wx-key", help="启动 wx_key GUI")
    launch_wx_key.add_argument(
        "--wait",
        action="store_true",
        help="等待 wx_key 进程结束（默认后台运行）",
    )

    ui_parser = subparsers.add_parser("ui", help="启动桌面 UI")
    ui_parser.add_argument("--headless", action="store_true", help="调试模式，不实际渲染 UI")

    return parser


def _print_dict(title: str, payload: Dict[str, Any]) -> None:
    print(f"\n=== {title} ===")
    for key, value in payload.items():
        print(f"{key}: {value}")


def main(argv: list[str] | None = None) -> None:
    parser = _build_parser()
    args = parser.parse_args(argv)
    command = args.command or "summarize"

    config = PipelineConfig.load(args.config)

    if command == "ui":
        from . import ui as ui_module

        ui_module.launch(
            headless=getattr(args, "headless", False),
            config_path=args.config,
        )
        return

    pipeline = WxAgentPipeline(config)

    if command == "launch-wx-key":
        pipeline.launch_wx_key(wait=args.wait)
        return

    if command == "refresh-key":
        payload = pipeline.refresh_key(
            auto_launch=args.ensure,
            wait_seconds=args.wait,
            poll_interval=args.poll,
        )
        _print_dict(
            "当前密钥",
            {
                "db_key": payload.db_key,
                "image_xor_key": payload.image_xor_key,
                "image_aes_key": payload.image_aes_key,
                "timestamp": payload.timestamp,
                "pref_file": str(config.wx_key_shared_prefs),
            },
        )
        return

    if command == "export":
        ok = pipeline.trigger_export()
        print("echotrace 导出已启动。" if ok else "未配置可用的 echotrace 命令或执行失败。")
        return

    try:
        result = pipeline.run(
            start_date=args.start_date,
            end_date=args.end_date,
            incremental=not args.full,
            questions=args.questions,
            save_markdown=not args.no_save,
        )
    except ValueError as exc:
        parser.error(str(exc))

    if args.json:
        json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
        print()
        return

    print("\n=== 汇总完成 ===")
    print(f"输出文件: {result.get('output') or '未保存'}")
    print(f"涉及会话: {len(result.get('stats', []))}")
    if result.get("qa"):
        print(f"回答自定义问题: {len(result['qa'])} 个")


if __name__ == "__main__":
    main()

