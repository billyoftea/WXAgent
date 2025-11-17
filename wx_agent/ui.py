from __future__ import annotations

import os
import subprocess
import sys
import threading
import calendar
from datetime import date, datetime
from pathlib import Path
from typing import Dict, List, Optional

import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, ttk

from .config import PipelineConfig
from .path_utils import resource_path
from .pipeline import WxAgentPipeline


def _format_dt(value: Optional[str]) -> str:
    return value or "--"


def _open_in_file_browser(path: Path) -> None:
    try:
        resolved = Path(path).expanduser().resolve()
    except Exception:
        resolved = Path(path)
    if not resolved.exists():
        messagebox.showwarning("提示", f"路径不存在：{resolved}")
        return
    if os.name == "nt":
        os.startfile(str(resolved))  # type: ignore[attr-defined]
    elif sys.platform == "darwin":
        subprocess.Popen(["open", str(resolved)])
    else:
        subprocess.Popen(["xdg-open", str(resolved)])


def _parse_date(value: str) -> Optional[date]:
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        return None


class DatePickerDialog(tk.Toplevel):
    """简单的日期选择弹窗。"""

    def __init__(self, master: tk.Misc, initial: Optional[date] = None):
        super().__init__(master)
        self.title("选择日期")
        self.resizable(False, False)
        self.transient(master)
        self.grab_set()
        self.result: Optional[date] = None

        current = initial or date.today()
        self._display_year = current.year
        self._display_month = current.month

        self._build_ui()

    def _build_ui(self) -> None:
        header = ttk.Frame(self)
        header.pack(fill="x", pady=4, padx=8)

        ttk.Button(header, text="‹", width=3, command=self._prev_month).pack(side="left")
        self._title_var = tk.StringVar()
        ttk.Label(header, textvariable=self._title_var, width=14, anchor="center").pack(
            side="left", expand=True
        )
        ttk.Button(header, text="›", width=3, command=self._next_month).pack(side="right")

        self._calendar_frame = ttk.Frame(self)
        self._calendar_frame.pack(fill="both", expand=True, padx=8, pady=(0, 8))

        self._draw_calendar()

    def _draw_calendar(self) -> None:
        for child in self._calendar_frame.winfo_children():
            child.destroy()

        self._title_var.set(f"{self._display_year} 年 {self._display_month:02d} 月")
        week_days = ["一", "二", "三", "四", "五", "六", "日"]

        head = ttk.Frame(self._calendar_frame)
        head.pack(fill="x", pady=(0, 4))
        for idx, label in enumerate(week_days):
            ttk.Label(head, text=label, width=3, anchor="center").grid(row=0, column=idx, padx=2)

        cal = calendar.Calendar()
        body = ttk.Frame(self._calendar_frame)
        body.pack()
        for row_idx, week in enumerate(cal.monthdayscalendar(self._display_year, self._display_month)):
            for col_idx, day in enumerate(week):
                if day == 0:
                    ttk.Label(body, text="", width=3).grid(row=row_idx, column=col_idx, padx=2, pady=1)
                    continue
                btn = ttk.Button(
                    body,
                    text=f"{day:02d}",
                    width=3,
                    command=lambda d=day: self._select_day(d),
                )
                btn.grid(row=row_idx, column=col_idx, padx=2, pady=1)

    def _prev_month(self) -> None:
        if self._display_month == 1:
            self._display_month = 12
            self._display_year -= 1
        else:
            self._display_month -= 1
        self._draw_calendar()

    def _next_month(self) -> None:
        if self._display_month == 12:
            self._display_month = 1
            self._display_year += 1
        else:
            self._display_month += 1
        self._draw_calendar()

    def _select_day(self, day: int) -> None:
        self.result = date(self._display_year, self._display_month, day)
        self.destroy()


def _open_date_picker(master: tk.Misc, var: tk.StringVar) -> None:
    dialog = DatePickerDialog(master, initial=_parse_date(var.get()))
    if dialog.result:
        var.set(dialog.result.strftime("%Y-%m-%d"))


def _create_date_selector(parent: ttk.Frame, label: str, var: tk.StringVar) -> ttk.Frame:
    frame = ttk.Frame(parent)
    ttk.Label(frame, text=label).pack(side="left")
    entry = ttk.Entry(frame, textvariable=var, width=12, state="readonly")
    entry.pack(side="left", padx=(6, 4))
    ttk.Button(
        frame,
        text="📅",
        width=3,
        command=lambda: _open_date_picker(parent.winfo_toplevel(), var),
    ).pack(side="left")
    ttk.Button(
        frame,
        text="清空",
        width=4,
        command=lambda: var.set(""),
    ).pack(side="left", padx=(4, 0))
    return frame


class BasePage(ttk.Frame):
    page_title = ""
    page_description = ""

    def __init__(self, parent, app: "WxAgentApp"):
        super().__init__(parent)
        self.app = app

    def on_show(self) -> None:
        pass

    def on_pipeline_reload(self) -> None:
        pass


class WxAgentApp:
    """Tkinter 桌面 UI，含侧边导航与多页面。"""

    def __init__(self, root: tk.Tk, config_path: Optional[str] = None):
        self.root = root
        self.root.title("WXAgent")
        self.config_path = config_path
        self.config = PipelineConfig.load(config_path)
        self.pipeline = WxAgentPipeline(self.config)

        self._pages: Dict[str, BasePage] = {}
        self._nav_buttons: Dict[str, ttk.Button] = {}
        self.current_page_key = "welcome"
        self.header_title_var = tk.StringVar()
        self.header_desc_var = tk.StringVar()

        self._init_style()
        self._build_layout()
        self._build_sidebar()
        self._build_pages()
        self.show_page("welcome")

    def _init_style(self) -> None:
        style = ttk.Style()
        try:
            style.theme_use("clam")
        except Exception:
            pass
        self.root.configure(bg="#F3F5FB")
        style.configure("App.TFrame", background="#F3F5FB")
        style.configure("Card.TFrame", background="#FFFFFF", relief="ridge", borderwidth=1)
        style.configure(
            "Accent.TButton",
            padding=(12, 6),
            relief="flat",
        )
        style.map("Accent.TButton", background=[("active", "#3450E8")], foreground=[("active", "#FFFFFF")])
        style.configure("Nav.TButton", anchor="w", padding=10)
        style.map("Nav.TButton", background=[("active", "#E7ECFF")])
        style.configure("NavActive.TButton", anchor="w", padding=10, background="#D6DBFF")
        style.configure(
            "App.Treeview",
            rowheight=28,
            borderwidth=0,
            relief="flat",
            font=("Segoe UI", 10),
        )
        style.configure("App.Treeview.Heading", font=("Segoe UI", 10, "bold"))
        style.map(
            "App.Treeview",
            background=[("selected", "#D8E1FF")],
            foreground=[("selected", "#1F2A44")],
        )

    def _build_layout(self) -> None:
        self.root.geometry("1180x780")
        self.root.minsize(1080, 680)
        self.root.grid_columnconfigure(1, weight=1)
        self.root.grid_rowconfigure(0, weight=1)

        self.sidebar = ttk.Frame(self.root, padding=(16, 24), style="App.TFrame")
        self.sidebar.grid(row=0, column=0, sticky="nsw")

        self.main_area = ttk.Frame(self.root, padding=(24, 24), style="App.TFrame")
        self.main_area.grid(row=0, column=1, sticky="nsew")
        self.main_area.grid_columnconfigure(0, weight=1)
        self.main_area.grid_rowconfigure(1, weight=1)

        header = ttk.Frame(self.main_area)
        header.grid(row=0, column=0, sticky="ew")
        ttk.Label(header, textvariable=self.header_title_var, font=("Segoe UI", 18, "bold")).pack(anchor="w")
        ttk.Label(
            header,
            textvariable=self.header_desc_var,
            font=("Segoe UI", 10),
            foreground="#475467",
            wraplength=820,
        ).pack(anchor="w", pady=(4, 12))

        self.content_stack = ttk.Frame(self.main_area, style="App.TFrame")
        self.content_stack.grid(row=1, column=0, sticky="nsew")
        self.content_stack.grid_propagate(False)

    def _build_sidebar(self) -> None:
        header = ttk.Frame(self.sidebar)
        header.pack(fill="x", pady=(0, 18))
        try:
            from PIL import Image, ImageTk  # type: ignore

            logo_path = resource_path("..", "WXAgent_logo.png")
            img = Image.open(logo_path)
            img = img.resize((40, 40))
            self._logo_img = ImageTk.PhotoImage(img)
            ttk.Label(header, image=self._logo_img).pack(side="left", padx=(0, 8))
        except Exception:
            pass
        ttk.Label(header, text="WXAgent", font=("Segoe UI", 14, "bold")).pack(side="left")

        nav_frame = ttk.Frame(self.sidebar)
        nav_frame.pack(fill="both", expand=True)
        nav_items = [
            ("welcome", "欢迎页"),
            ("key", "密钥获取"),
            ("export", "聊天读取与导出"),
            ("analysis", "聊天记录分析"),
            ("summary", "聊天记录 AI 总结"),
            ("settings", "设置"),
        ]
        for key, label in nav_items:
            btn = ttk.Button(nav_frame, text=label, style="Nav.TButton", command=lambda k=key: self.show_page(k))
            btn.pack(fill="x", pady=4)
            self._nav_buttons[key] = btn

    def _build_pages(self) -> None:
        page_classes = {
            "welcome": WelcomePage,
            "key": KeyPage,
            "export": ExportPage,
            "analysis": AnalysisPage,
            "summary": SummaryPage,
            "settings": SettingsPage,
        }
        for key, cls in page_classes.items():
            frame = cls(self.content_stack, self)
            frame.grid(row=0, column=0, sticky="nsew")
            frame.grid_remove()
            self._pages[key] = frame

    def show_page(self, key: str) -> None:
        frame = self._pages.get(key)
        if frame is None:
            return
        previous = self._pages.get(self.current_page_key)
        if previous:
            previous.grid_remove()
        frame.grid()
        self.current_page_key = key
        self.header_title_var.set(getattr(frame, "page_title", key.title()))
        self.header_desc_var.set(getattr(frame, "page_description", ""))
        for nav_key, btn in self._nav_buttons.items():
            btn.configure(style="NavActive.TButton" if nav_key == key else "Nav.TButton")
        frame.on_show()

    def reload_pipeline(self) -> None:
        self.pipeline = WxAgentPipeline(self.config)
        for frame in self._pages.values():
            frame.on_pipeline_reload()

    def open_path(self, path: Path) -> None:
        _open_in_file_browser(path)


class WelcomePage(BasePage):
    page_title = "WELCOME! 欢迎使用 WXAgent"
    page_description = "WXAgent 帮助你读取、导出与分析微信聊天记录，并可用 AI 生成总结。"

    def __init__(self, parent, app: WxAgentApp):
        super().__init__(parent, app)
        self.status_note = tk.StringVar(value="状态尚未刷新")
        self.key_status = tk.StringVar(value="--")
        self.export_status = tk.StringVar(value="--")
        self.summary_status = tk.StringVar(value="--")
        self._flow_running = False

        container = ttk.Frame(self)
        container.pack(fill="both", expand=True, padx=12, pady=12)

        intro = ttk.Label(
            container,
            text="WXAgent 是一个本地桌面工具，整合密钥获取、聊天导出、统计分析与 AI 总结。",
            wraplength=780,
            font=("Segoe UI", 11),
        )
        intro.pack(anchor="w", pady=(0, 16))

        status_frame = ttk.LabelFrame(container, text="当前状态")
        status_frame.pack(fill="x", pady=(0, 12))

        cards = ttk.Frame(status_frame)
        cards.pack(fill="x", padx=12, pady=12)
        self._build_status_card(cards, "密钥状态", self.key_status, 0)
        self._build_status_card(cards, "导出数据", self.export_status, 1)
        self._build_status_card(cards, "总结输出", self.summary_status, 2)

        ttk.Button(status_frame, text="刷新状态", command=self.refresh_status).pack(anchor="e", padx=12, pady=(0, 12))
        ttk.Label(status_frame, textvariable=self.status_note, foreground="#475467").pack(anchor="w", padx=12, pady=(0, 12))

        self.flow_status = tk.StringVar(value="尚未执行一键流程")
        flow_box = ttk.LabelFrame(container, text="一键流程")
        flow_box.pack(fill="x", pady=(0, 12))
        flow_controls = ttk.Frame(flow_box)
        flow_controls.pack(fill="x", padx=12, pady=8)
        ttk.Button(
            flow_controls,
            text="一键同步聊天记录",
            style="Accent.TButton",
            command=self._run_integrated_flow,
        ).pack(side="left")
        ttk.Label(flow_controls, textvariable=self.flow_status, foreground="#475467").pack(side="left", padx=12)

        guide = ttk.LabelFrame(container, text="新手指引")
        guide.pack(fill="x", pady=(0, 12))
        steps = [
            ("密钥获取", "在“密钥获取”页面读取微信聊天数据库密钥。", "key"),
            ("聊天读取与导出", "调用内置 echotrace 并筛选需要的会话数据。", "export"),
            ("聊天记录分析", "查看活跃度、消息类型与群成员榜单。", "analysis"),
            ("聊天记录 AI 总结", "选择时间范围与提示词，生成结构化总结。", "summary"),
        ]
        for title, desc, target in steps:
            row = ttk.Frame(guide)
            row.pack(fill="x", padx=12, pady=6)
            ttk.Label(row, text=title, font=("Segoe UI", 10, "bold")).pack(anchor="w")
            ttk.Label(row, text=desc, foreground="#475467").pack(anchor="w")
            ttk.Button(row, text="去页面", command=lambda k=target: self.app.show_page(k)).pack(anchor="e", pady=(4, 0))

        history_frame = ttk.LabelFrame(container, text="最近的总结记录")
        history_frame.pack(fill="both", expand=True)
        self.history_tree = ttk.Treeview(
            history_frame,
            columns=("name", "modified", "size"),
            show="headings",
            height=5,
            style="App.Treeview",
        )
        self.history_tree.heading("name", text="文件")
        self.history_tree.heading("modified", text="更新时间")
        self.history_tree.heading("size", text="大小")
        self.history_tree.column("name", width=320)
        self.history_tree.column("modified", width=180)
        self.history_tree.column("size", width=80, anchor="e")
        self.history_tree.pack(fill="both", expand=True, padx=12, pady=12)

        contact = ttk.Label(
            container,
            text="作者联系方式：xuang_work@foxmail.com ／ Github @billyoftea",
            foreground="#475467",
        )
        contact.pack(anchor="w", pady=(8, 0))

    def _build_status_card(self, parent: ttk.Frame, title: str, var: tk.StringVar, column: int) -> None:
        card = ttk.Frame(parent, padding=12, style="Card.TFrame")
        card.grid(row=0, column=column, sticky="nsew", padx=6)
        parent.grid_columnconfigure(column, weight=1)
        ttk.Label(card, text=title, font=("Segoe UI", 11, "bold")).pack(anchor="w")
        ttk.Label(card, textvariable=var, wraplength=220, foreground="#475467").pack(anchor="w", pady=(6, 0))

    def on_show(self) -> None:
        self.refresh_status()

    def refresh_status(self) -> None:
        self.status_note.set("状态刷新中...")
        thread = threading.Thread(target=self._load_status, daemon=True)
        thread.start()

    def _load_status(self) -> None:
        try:
            status = self.app.pipeline.get_status()
        except Exception as exc:
            self.after(0, lambda: messagebox.showerror("刷新失败", str(exc)))
            return
        self.after(0, lambda: self._apply_status(status))

    def _apply_status(self, status: Dict[str, object]) -> None:
        key = status.get("key") or {}
        export = status.get("export") or {}
        summary = status.get("summary") or {}
        history = summary.get("history_preview") or []

        pref = key.get("pref_path") or "--"
        pref_exists = key.get("pref_exists")
        timestamp = key.get("timestamp") or "--"
        self.key_status.set(f"SharedPreferences: {pref} ({'可用' if pref_exists else '未找到'})\n最新写入：{_format_dt(timestamp)}")

        export_dir = export.get("export_dir") or "--"
        sessions = export.get("sessions") or 0
        messages = export.get("messages") or 0
        last_export = export.get("last_export_time") or "--"
        self.export_status.set(
            f"导出目录：{export_dir}\n会话：{sessions} 个｜消息：{messages} 条\n最近解密：{_format_dt(last_export)}"
        )

        output_path = summary.get("output_path") or "--"
        last_modified = summary.get("last_modified") or "--"
        history_exists = summary.get("history_exists")
        self.summary_status.set(
            f"总结输出：{output_path}\n最近更新：{_format_dt(last_modified)}｜历史目录：{'可用' if history_exists else '未创建'}"
        )

        for item in self.history_tree.get_children():
            self.history_tree.delete(item)
        for entry in history:
            self.history_tree.insert(
                "",
                "end",
                values=(
                    entry.get("name"),
                    entry.get("modified"),
                    f"{int(entry.get('size', 0)) // 1024} KB",
                ),
            )

        self.status_note.set("状态已刷新")

    def _run_integrated_flow(self) -> None:
        if getattr(self, "_flow_running", False):
            return
        self._flow_running = True
        self.flow_status.set("正在同步数据...")
        thread = threading.Thread(target=self._flow_worker, daemon=True)
        thread.start()

    def _flow_worker(self) -> None:
        result = self.app.pipeline.run_full_refresh()
        self.after(0, lambda r=result: self._finish_flow(r))

    def _finish_flow(self, result: Dict[str, object]) -> None:
        self._flow_running = False
        if result.get("dataset_ready"):
            summary = f"同步完成：{result.get('sessions', 0)} 个会话 / {result.get('messages', 0)} 条消息"
            self.flow_status.set(summary)
        else:
            self.flow_status.set("同步流程完成，但未检测到新的聊天记录。")
        self.refresh_status()


class KeyPage(BasePage):
    page_title = "密钥获取"
    page_description = "WXAgent 需要读取本地微信数据库密钥，仅用于解密聊天记录，不会上传。"

    def __init__(self, parent, app: WxAgentApp):
        super().__init__(parent, app)
        cfg = app.config
        self.pref_var = tk.StringVar(value=str(cfg.wx_key_shared_prefs or ""))
        self.install_var = tk.StringVar(value=str(cfg.wechat_install_path or ""))
        self.data_var = tk.StringVar(value=str(cfg.wechat_data_path or ""))
        self.status_var = tk.StringVar(value="尚未读取密钥")
        self._key_thread: Optional[threading.Thread] = None

        container = ttk.Frame(self)
        container.pack(fill="both", expand=True, padx=12, pady=12)

        ttk.Label(container, text="请确认以下路径后再尝试获取密钥：", font=("Segoe UI", 11)).pack(anchor="w")

        paths = ttk.LabelFrame(container, text="路径设置")
        paths.pack(fill="x", pady=10)
        self._build_path_row(paths, "SharedPreferences JSON", self.pref_var, self._choose_pref)
        self._build_path_row(paths, "微信安装路径（可选）", self.install_var, lambda: self._choose_dir(self.install_var))
        self._build_path_row(paths, "微信数据路径（可选）", self.data_var, lambda: self._choose_dir(self.data_var))
        ttk.Button(paths, text="保存路径设置", command=self._save_paths).pack(anchor="e", padx=12, pady=(4, 8))

        actions = ttk.Frame(container)
        actions.pack(fill="x", pady=(0, 10))
        ttk.Button(actions, text="开始获取密钥", command=lambda: self._refresh_key(False)).pack(side="left", padx=(0, 8))
        ttk.Button(actions, text="自动启动 wx_key 并获取", command=lambda: self._refresh_key(True)).pack(side="left")
        ttk.Button(actions, text="复制密钥内容", command=self._copy_key).pack(side="right")

        ttk.Label(container, textvariable=self.status_var, foreground="#475467").pack(anchor="w")

        result_frame = ttk.LabelFrame(container, text="密钥读取结果")
        result_frame.pack(fill="both", expand=True, pady=(8, 0))
        self.key_text = scrolledtext.ScrolledText(result_frame, height=7, wrap="word")
        self.key_text.pack(fill="both", expand=True, padx=12, pady=12)

    def _build_path_row(self, parent: ttk.Frame, label: str, var: tk.StringVar, chooser) -> None:
        row = ttk.Frame(parent)
        row.pack(fill="x", padx=12, pady=6)
        ttk.Label(row, text=label, width=20).pack(side="left")
        ttk.Entry(row, textvariable=var, width=60).pack(side="left", padx=(0, 8))
        ttk.Button(row, text="浏览", command=chooser).pack(side="left")

    def _choose_pref(self) -> None:
        path = filedialog.askopenfilename(title="选择 shared_preferences.json")
        if path:
            self.pref_var.set(path)

    def _choose_dir(self, var: tk.StringVar) -> None:
        path = filedialog.askdirectory()
        if path:
            var.set(path)

    def _save_paths(self) -> None:
        cfg = self.app.config
        pref = self.pref_var.get().strip()
        cfg.wx_key_shared_prefs = Path(pref) if pref else None
        install = self.install_var.get().strip()
        cfg.wechat_install_path = Path(install) if install else None
        data = self.data_var.get().strip()
        cfg.wechat_data_path = Path(data) if data else None
        cfg.save(self.app.config_path)
        self.app.reload_pipeline()
        messagebox.showinfo("提示", "路径设置已保存。")

    def _refresh_key(self, auto_launch: bool) -> None:
        if self._key_thread and self._key_thread.is_alive():
            return
        self.status_var.set("正在读取密钥，请稍候...")
        self._key_thread = threading.Thread(target=self._refresh_key_worker, args=(auto_launch,), daemon=True)
        self._key_thread.start()

    def _refresh_key_worker(self, auto_launch: bool) -> None:
        try:
            payload = self.app.pipeline.refresh_key(auto_launch=auto_launch)
        except Exception as exc:
            self.after(0, lambda: self.status_var.set(f"读取失败：{exc}"))
            messagebox.showerror("读取失败", str(exc))
            return

        text = (
            f"DB Key: {payload.db_key or '--'}\n"
            f"Image AES Key: {payload.image_aes_key or '--'}\n"
            f"Image XOR Key: {payload.image_xor_key or '--'}\n"
            f"更新时间: {payload.timestamp or '--'}"
        )
        self.after(0, lambda: self._update_key_view(text))

    def _update_key_view(self, text: str) -> None:
        self.key_text.delete("1.0", "end")
        self.key_text.insert("1.0", text)
        self.status_var.set("读取完成，可以复制密钥。")

    def _copy_key(self) -> None:
        content = self.key_text.get("1.0", "end").strip()
        if not content:
            return
        self.clipboard_clear()
        self.clipboard_append(content)
        messagebox.showinfo("提示", "密钥内容已复制到剪贴板。")


class ExportPage(BasePage):
    page_title = "聊天读取与导出"
    page_description = "管理本地导出的聊天记录，并按需筛选导出 JSON 文件。"

    def __init__(self, parent, app: WxAgentApp):
        super().__init__(parent, app)
        self.sessions: List[Dict[str, object]] = []
        self.filtered_sessions: List[Dict[str, object]] = []

        self.search_var = tk.StringVar()
        self.start_var = tk.StringVar()
        self.end_var = tk.StringVar()
        self.output_dir_var = tk.StringVar(value=str((app.config.export_dir / "export").resolve()))
        self.merge_var = tk.BooleanVar(value=True)
        self.agree_var = tk.BooleanVar(value=False)
        self.status_var = tk.StringVar(value="尚未加载导出数据")
        self.search_var.trace_add("write", lambda *_: self._render_sessions())

        container = ttk.Frame(self)
        container.pack(fill="both", expand=True, padx=12, pady=12)

        top = ttk.Frame(container)
        top.pack(fill="x", pady=(0, 10))
        ttk.Label(top, text=f"当前导出目录：{self.app.config.export_dir}").pack(side="left")
        ttk.Button(top, text="打开目录", command=lambda: self.app.open_path(self.app.config.export_dir)).pack(side="right")

        actions = ttk.Frame(container)
        actions.pack(fill="x", pady=(0, 10))
        ttk.Button(actions, text="刷新列表", command=self.refresh_sessions).pack(side="left")
        ttk.Button(actions, text="启动 echotrace 导出", command=self._trigger_export).pack(side="left", padx=8)
        ttk.Entry(actions, textvariable=self.search_var, width=26).pack(side="right")
        ttk.Label(actions, text="搜索会话：").pack(side="right", padx=(0, 6))

        table_frame = ttk.LabelFrame(container, text="导出的会话")
        table_frame.pack(fill="both", expand=True)
        columns = ("name", "messages", "last_export", "last_added")
        self.tree = ttk.Treeview(
            table_frame,
            columns=columns,
            show="headings",
            selectmode="extended",
            style="App.Treeview",
        )
        self.tree.heading("name", text="会话")
        self.tree.heading("messages", text="消息数")
        self.tree.heading("last_export", text="最近导出")
        self.tree.heading("last_added", text="上次新增")
        self.tree.column("name", width=260)
        self.tree.column("messages", width=80, anchor="e")
        self.tree.column("last_export", width=160)
        self.tree.column("last_added", width=100, anchor="e")
        self.tree.pack(fill="both", expand=True, padx=12, pady=12)

        export_box = ttk.LabelFrame(container, text="筛选导出 JSON")
        export_box.pack(fill="x", pady=(0, 10))

        row1 = ttk.Frame(export_box)
        row1.pack(fill="x", padx=12, pady=6)
        start_field = _create_date_selector(row1, "开始日期", self.start_var)
        start_field.pack(side="left", padx=(0, 18))
        end_field = _create_date_selector(row1, "结束日期", self.end_var)
        end_field.pack(side="left")

        row2 = ttk.Frame(export_box)
        row2.pack(fill="x", padx=12, pady=6)
        ttk.Label(row2, text="输出目录").pack(side="left")
        ttk.Entry(row2, textvariable=self.output_dir_var, width=50).pack(side="left", padx=(6, 8))
        ttk.Button(row2, text="浏览", command=self._choose_output_dir).pack(side="left")

        row3 = ttk.Frame(export_box)
        row3.pack(fill="x", padx=12, pady=6)
        ttk.Checkbutton(row3, text="合并为单个 JSON 文件", variable=self.merge_var).pack(side="left")
        ttk.Checkbutton(row3, text="我已知晓将导出所选会话内容", variable=self.agree_var).pack(side="left", padx=(18, 0))
        ttk.Button(row3, text="开始导出", command=self._export_selected).pack(side="right")

        ttk.Label(container, textvariable=self.status_var, foreground="#475467").pack(anchor="w")

    def on_show(self) -> None:
        if not self.sessions:
            self.refresh_sessions()

    def on_pipeline_reload(self) -> None:
        self.sessions.clear()
        self.refresh_sessions()

    def refresh_sessions(self) -> None:
        self.status_var.set("正在加载导出列表...")

        def worker():
            try:
                data = self.app.pipeline.list_export_states()
            except Exception as exc:
                self.after(0, lambda: messagebox.showerror("加载失败", str(exc)))
                return
            self.sessions = data
            self.after(0, self._render_sessions)

        threading.Thread(target=worker, daemon=True).start()

    def _render_sessions(self) -> None:
        keyword = self.search_var.get().strip().lower()
        if keyword:
            self.filtered_sessions = [
                meta for meta in self.sessions if keyword in str(meta.get("display_name", "")).lower()
            ]
        else:
            self.filtered_sessions = list(self.sessions)

        for item in self.tree.get_children():
            self.tree.delete(item)
        for meta in self.filtered_sessions:
            self.tree.insert(
                "",
                "end",
                iid=str(meta.get("file")),
                values=(
                    meta.get("display_name"),
                    meta.get("messages"),
                    meta.get("last_export_time"),
                    meta.get("last_added_count") or "-",
                ),
            )
        self.status_var.set(f"共 {len(self.filtered_sessions)} 个会话。")

    def _choose_output_dir(self) -> None:
        path = filedialog.askdirectory(title="选择导出目录")
        if path:
            self.output_dir_var.set(path)

    def _selected_files(self) -> List[str]:
        return list(self.tree.selection())

    def _export_selected(self) -> None:
        if not self.agree_var.get():
            messagebox.showwarning("提示", "请先勾选“我已知晓将导出所选会话内容”。")
            return
        selected = self._selected_files()
        if not selected:
            messagebox.showwarning("提示", "请在会话列表中选择至少一项。")
            return
        try:
            result = self.app.pipeline.export_filtered_chats(
                files=selected,
                start_date=self.start_var.get() or None,
                end_date=self.end_var.get() or None,
                output_dir=self.output_dir_var.get() or None,
                single_file=self.merge_var.get(),
            )
        except Exception as exc:
            messagebox.showerror("导出失败", str(exc))
            return
        files = "\n".join(result.get("files") or [])
        messagebox.showinfo("导出完成", f"共导出 {result.get('count', 0)} 条消息。\n文件：\n{files}")

    def _trigger_export(self) -> None:
        ok = self.app.pipeline.trigger_export()
        if ok:
            messagebox.showinfo("提示", "已启动 echotrace，请在其界面完成操作。")
        else:
            messagebox.showwarning("提示", "未配置可用的 echotrace 命令。")


class AnalysisPage(BasePage):
    page_title = "聊天记录分析"
    page_description = "查看时间范围内的聊天活跃度、类型分布和群成员榜单。"

    def __init__(self, parent, app: WxAgentApp):
        super().__init__(parent, app)
        self.start_var = tk.StringVar()
        self.end_var = tk.StringVar()
        self.session_type_var = tk.StringVar(value="all")
        self.top_var = tk.IntVar(value=10)
        self.status_var = tk.StringVar(value="尚未统计")
        self.group_summary_var = tk.StringVar(value="群聊：--")
        self.single_summary_var = tk.StringVar(value="私聊：--")

        container = ttk.Frame(self)
        container.pack(fill="both", expand=True, padx=12, pady=12)

        filters = ttk.Frame(container)
        filters.pack(fill="x", pady=(0, 10))
        start_field = _create_date_selector(filters, "开始日期", self.start_var)
        start_field.pack(side="left", padx=(0, 12))
        end_field = _create_date_selector(filters, "结束日期", self.end_var)
        end_field.pack(side="left", padx=(0, 12))
        ttk.Label(filters, text="会话类型").pack(side="left")
        ttk.OptionMenu(filters, self.session_type_var, "all", "all", "single", "group").pack(side="left", padx=(6, 12))
        ttk.Label(filters, text="Top N").pack(side="left")
        ttk.OptionMenu(filters, self.top_var, 10, 10, 20, 50).pack(side="left", padx=(6, 12))
        ttk.Button(filters, text="刷新统计", command=self.refresh_stats).pack(side="left")

        summary_frame = ttk.Frame(container)
        summary_frame.pack(fill="x", pady=(0, 10))
        self.total_msgs_var = tk.StringVar(value="--")
        self.session_count_var = tk.StringVar(value="--")
        self.window_var = tk.StringVar(value="--")
        self._build_summary_label(summary_frame, "总消息数", self.total_msgs_var, 0)
        self._build_summary_label(summary_frame, "会话数量", self.session_count_var, 1)
        self._build_summary_label(summary_frame, "统计区间", self.window_var, 2)
        self._build_summary_label(summary_frame, "群聊", self.group_summary_var, 3)
        self._build_summary_label(summary_frame, "私聊", self.single_summary_var, 4)

        table_frame = ttk.LabelFrame(container, text="聊天活跃榜")
        table_frame.pack(fill="both", expand=True)
        columns = ("name", "messages", "type")
        self.table = ttk.Treeview(table_frame, columns=columns, show="headings", style="App.Treeview")
        self.table.heading("name", text="会话")
        self.table.heading("messages", text="消息数")
        self.table.heading("type", text="类型")
        self.table.column("name", width=280)
        self.table.column("messages", width=80, anchor="e")
        self.table.column("type", width=80)
        self.table.pack(fill="both", expand=True, padx=12, pady=12)
        self.table.bind("<<TreeviewSelect>>", self._handle_selection)

        detail = ttk.LabelFrame(container, text="会话详情")
        detail.pack(fill="both", expand=True, pady=(10, 0))
        self.detail_status_var = tk.StringVar(value="请选择上方会话查看详情。")
        ttk.Label(detail, textvariable=self.detail_status_var, foreground="#475467").pack(anchor="w", padx=12, pady=(8, 0))

        info_frame = ttk.Frame(detail)
        info_frame.pack(fill="x", padx=12, pady=8)
        self.detail_total_var = tk.StringVar(value="--")
        self.detail_days_var = tk.StringVar(value="--")
        self.detail_avg_var = tk.StringVar(value="--")
        self._build_summary_label(info_frame, "消息数", self.detail_total_var, 0)
        self._build_summary_label(info_frame, "活跃天数", self.detail_days_var, 1)
        self._build_summary_label(info_frame, "日均消息", self.detail_avg_var, 2)

        self.detail_first_var = tk.StringVar(value="--")
        self.detail_last_var = tk.StringVar(value="--")
        ttk.Label(detail, textvariable=self.detail_first_var).pack(anchor="w", padx=12)
        ttk.Label(detail, textvariable=self.detail_last_var).pack(anchor="w", padx=12)

        charts = ttk.Frame(detail)
        charts.pack(fill="both", expand=True, padx=12, pady=12)
        self.type_tree = ttk.Treeview(
            charts,
            columns=("type", "count", "ratio"),
            show="headings",
            height=4,
            style="App.Treeview",
        )
        self.type_tree.heading("type", text="消息类型")
        self.type_tree.heading("count", text="数量")
        self.type_tree.heading("ratio", text="占比")
        self.type_tree.column("type", width=120)
        self.type_tree.column("count", width=80, anchor="e")
        self.type_tree.column("ratio", width=80, anchor="e")
        self.type_tree.pack(side="left", fill="both", expand=True)

        self.part_tree = ttk.Treeview(
            charts,
            columns=("name", "count", "ratio"),
            show="headings",
            height=4,
            style="App.Treeview",
        )
        self.part_tree.heading("name", text="群成员 / 联系人")
        self.part_tree.heading("count", text="消息数")
        self.part_tree.heading("ratio", text="占比")
        self.part_tree.column("name", width=180)
        self.part_tree.column("count", width=80, anchor="e")
        self.part_tree.column("ratio", width=80, anchor="e")
        self.part_tree.pack(side="left", fill="both", expand=True, padx=(12, 0))

        ttk.Label(container, textvariable=self.status_var, foreground="#475467").pack(anchor="w")

    def _build_summary_label(self, parent: ttk.Frame, title: str, var: tk.StringVar, column: int) -> None:
        frame = ttk.Frame(parent)
        frame.grid(row=0, column=column, sticky="nsew", padx=6)
        parent.grid_columnconfigure(column, weight=1)
        ttk.Label(frame, text=title, font=("Segoe UI", 10)).pack(anchor="w")
        ttk.Label(frame, textvariable=var, font=("Segoe UI", 12, "bold")).pack(anchor="w")

    def refresh_stats(self) -> None:
        self.status_var.set("正在统计...")

        def worker():
            try:
                session_types = None
                if self.session_type_var.get() == "single":
                    session_types = ["单聊", "single"]
                elif self.session_type_var.get() == "group":
                    session_types = ["群聊", "group"]
                data = self.app.pipeline.analyze_stats(
                    start_date=self.start_var.get() or None,
                    end_date=self.end_var.get() or None,
                    top_n=self.top_var.get(),
                    session_types=session_types,
                )
            except Exception as exc:
                self.after(0, lambda: messagebox.showerror("统计失败", str(exc)))
                return
            self.after(0, lambda d=data: self._apply_stats(d))

        threading.Thread(target=worker, daemon=True).start()

    def _apply_stats(self, data: Dict[str, object]) -> None:
        self.total_msgs_var.set(str(data.get("total_messages", 0)))
        self.session_count_var.set(str(data.get("session_count", 0)))
        window = data.get("window") or {}
        self.window_var.set(f"{window.get('start') or '--'} ~ {window.get('end') or '--'}")
        breakdown = data.get("breakdown") or {}
        group = breakdown.get("group", {})
        single = breakdown.get("single", {})
        self.group_summary_var.set(
            f"群聊：{group.get('sessions', 0)} 个 / {group.get('messages', 0)} 条"
        )
        self.single_summary_var.set(
            f"私聊：{single.get('sessions', 0)} 个 / {single.get('messages', 0)} 条"
        )

        for item in self.table.get_children():
            self.table.delete(item)
        for row in data.get("top", []):
            self.table.insert(
                "",
                "end",
                iid=str(row.get("file")),
                values=(row.get("display_name"), row.get("messages"), row.get("session_type") or "-"),
            )

        self.status_var.set(f"统计完成，共 {data.get('session_count', 0)} 个会话。")
        self.detail_status_var.set("请选择会话查看详情。")

    def _handle_selection(self, _event) -> None:
        selection = self.table.selection()
        if not selection:
            return
        file_path = selection[0]
        self.detail_status_var.set("正在加载详情...")

        def worker():
            try:
                detail = self.app.pipeline.describe_session(
                    file_path,
                    start_date=self.start_var.get() or None,
                    end_date=self.end_var.get() or None,
                )
            except Exception as exc:
                self.after(0, lambda: messagebox.showerror("加载失败", str(exc)))
                return
            self.after(0, lambda d=detail: self._render_detail(d))

        threading.Thread(target=worker, daemon=True).start()

    def _render_detail(self, detail: Dict[str, object]) -> None:
        metrics = detail.get("metrics") or {}
        self.detail_total_var.set(str(metrics.get("total_messages", "--")))
        self.detail_days_var.set(str(metrics.get("active_days", "--")))
        self.detail_avg_var.set(str(metrics.get("average_per_day", "--")))
        self.detail_first_var.set(f"首条消息：{metrics.get('first_message') or '--'}")
        self.detail_last_var.set(f"最新消息：{metrics.get('last_message') or '--'}")

        for tree in (self.type_tree, self.part_tree):
            for item in tree.get_children():
                tree.delete(item)

        for entry in metrics.get("message_types", []):
            self.type_tree.insert("", "end", values=(entry.get("type"), entry.get("count"), entry.get("ratio")))

        for entry in metrics.get("participants", {}).get("top", []):
            self.part_tree.insert("", "end", values=(entry.get("name"), entry.get("count"), entry.get("ratio")))

        self.detail_status_var.set("详情已加载。")


class SummaryPage(BasePage):
    page_title = "聊天记录 AI 总结"
    page_description = "选择时间范围和提示词，生成并管理本地保存的总结记录。"

    def __init__(self, parent, app: WxAgentApp):
        super().__init__(parent, app)
        self.start_var = tk.StringVar()
        self.end_var = tk.StringVar()
        self.incremental_var = tk.BooleanVar(value=True)
        self.prompt_mode = tk.StringVar(value="default")
        self.status_var = tk.StringVar(value="尚未生成")
        self.history_var = tk.StringVar()
        self.session_filter_var = tk.StringVar()
        self._running = False

        self.sessions: List[Dict[str, object]] = []
        self.filtered_sessions: List[Dict[str, object]] = []

        container = ttk.Frame(self)
        container.pack(fill="both", expand=True, padx=12, pady=12)

        filters = ttk.Frame(container)
        filters.pack(fill="x")
        start_field = _create_date_selector(filters, "开始日期", self.start_var)
        start_field.grid(row=0, column=0, sticky="w", padx=(0, 18))
        end_field = _create_date_selector(filters, "结束日期", self.end_var)
        end_field.grid(row=0, column=1, sticky="w", padx=(0, 18))
        ttk.Checkbutton(filters, text="增量模式（跳过已总结）", variable=self.incremental_var).grid(row=0, column=4, padx=(6, 0))
        filters.grid_columnconfigure(5, weight=1)

        sessions_frame = ttk.LabelFrame(container, text="选择会话（留空表示全部）")
        sessions_frame.pack(fill="x", pady=(12, 0))
        search_row = ttk.Frame(sessions_frame)
        search_row.pack(fill="x", padx=12, pady=6)
        ttk.Label(search_row, text="搜索").pack(side="left")
        entry = ttk.Entry(search_row, textvariable=self.session_filter_var, width=30)
        entry.pack(side="left", padx=(6, 0))
        entry.bind("<KeyRelease>", self._apply_session_filter)
        ttk.Button(search_row, text="刷新列表", command=self.refresh_sessions).pack(side="right")

        columns = ("name", "messages")
        self.session_tree = ttk.Treeview(
            sessions_frame,
            columns=columns,
            show="headings",
            selectmode="extended",
            height=6,
            style="App.Treeview",
        )
        self.session_tree.heading("name", text="会话")
        self.session_tree.heading("messages", text="消息数")
        self.session_tree.column("name", width=360)
        self.session_tree.column("messages", width=80, anchor="e")
        self.session_tree.pack(fill="x", padx=12, pady=(0, 12))

        prompt_frame = ttk.LabelFrame(container, text="提示词")
        prompt_frame.pack(fill="x", pady=(12, 0))
        prompt_row = ttk.Frame(prompt_frame)
        prompt_row.pack(fill="x", padx=12, pady=6)
        ttk.Radiobutton(prompt_row, text="使用默认总结提示词", variable=self.prompt_mode, value="default").pack(anchor="w")
        ttk.Radiobutton(prompt_row, text="使用自定义提示词", variable=self.prompt_mode, value="custom").pack(anchor="w")
        self.custom_prompt_text = scrolledtext.ScrolledText(prompt_frame, height=4, state="disabled")
        self.custom_prompt_text.pack(fill="x", padx=12, pady=(0, 8))
        self.prompt_mode.trace_add("write", lambda *_: self._toggle_prompt_state())

        question_frame = ttk.LabelFrame(container, text="自定义问题（每行一个，可选）")
        question_frame.pack(fill="x", pady=(12, 0))
        self.question_text = scrolledtext.ScrolledText(question_frame, height=4)
        self.question_text.pack(fill="x", padx=12, pady=8)

        actions = ttk.Frame(container)
        actions.pack(fill="x", pady=(12, 0))
        ttk.Button(actions, text="开始总结", command=self._run_summary).pack(side="left")
        ttk.Label(actions, textvariable=self.status_var, foreground="#475467").pack(side="right")

        history_frame = ttk.LabelFrame(container, text="历史总结记录")
        history_frame.pack(fill="x", pady=(12, 0))
        history_row = ttk.Frame(history_frame)
        history_row.pack(fill="x", padx=12, pady=6)
        self.history_combo = ttk.Combobox(history_row, textvariable=self.history_var, state="readonly", width=60)
        self.history_combo.pack(side="left", fill="x", expand=True)
        self.history_combo.bind("<<ComboboxSelected>>", self._load_history)
        ttk.Button(history_row, text="刷新", command=self.refresh_history).pack(side="left", padx=(8, 0))

        buttons = ttk.Frame(history_frame)
        buttons.pack(fill="x", padx=12, pady=(0, 8))
        ttk.Button(buttons, text="复制内容", command=self._copy_summary).pack(side="left")
        ttk.Button(buttons, text="另存为 Markdown", command=lambda: self._save_summary("md")).pack(side="left", padx=6)
        ttk.Button(buttons, text="另存为 TXT", command=lambda: self._save_summary("txt")).pack(side="left", padx=6)
        ttk.Button(buttons, text="打开历史目录", command=lambda: self.app.open_path(self.app.config.summary_history_dir)).pack(side="right")

        result_frame = ttk.LabelFrame(container, text="总结结果")
        result_frame.pack(fill="both", expand=True, pady=(12, 0))
        self.output_text = scrolledtext.ScrolledText(result_frame, wrap="word")
        self.output_text.pack(fill="both", expand=True, padx=12, pady=12)

    def on_show(self) -> None:
        if not self.sessions:
            self.refresh_sessions()
            self.refresh_history()

    def on_pipeline_reload(self) -> None:
        self.sessions.clear()
        self.refresh_sessions()
        self.refresh_history()

    def refresh_sessions(self) -> None:
        try:
            sessions = self.app.pipeline.list_sessions()
        except Exception as exc:
            messagebox.showerror("加载失败", str(exc))
            return
        self.sessions = sessions
        self._apply_session_filter()

    def refresh_history(self) -> None:
        try:
            history = self.app.pipeline.list_summary_history()
        except Exception as exc:
            messagebox.showerror("加载失败", str(exc))
            return
        self.history_entries = history
        self.history_combo["values"] = [entry.get("name") for entry in history]
        self.history_var.set("")

    def _apply_session_filter(self, *_args) -> None:
        keyword = self.session_filter_var.get().strip().lower()
        if keyword:
            filtered = [
                s for s in self.sessions if keyword in str(s.get("display_name", "")).lower()
            ]
        else:
            filtered = list(self.sessions)
        self.filtered_sessions = filtered
        for item in self.session_tree.get_children():
            self.session_tree.delete(item)
        for session in filtered:
            file_path = str(session.get("file"))
            label = session.get("display_name")
            self.session_tree.insert(
                "",
                "end",
                iid=file_path,
                values=(label, session.get("messages")),
            )

    def _toggle_prompt_state(self) -> None:
        state = "normal" if self.prompt_mode.get() == "custom" else "disabled"
        self.custom_prompt_text.configure(state=state)

    def _selected_sessions(self) -> List[str]:
        return list(self.session_tree.selection())

    def _run_summary(self) -> None:
        if self._running:
            return
        self._running = True
        self.status_var.set("正在生成总结...")
        sessions = self._selected_sessions()
        questions = [
            line.strip()
            for line in self.question_text.get("1.0", "end").splitlines()
            if line.strip()
        ]
        prompt = None
        if self.prompt_mode.get() == "custom":
            prompt = self.custom_prompt_text.get("1.0", "end").strip() or None

        def worker():
            try:
                result = self.app.pipeline.run(
                    start_date=self.start_var.get() or None,
                    end_date=self.end_var.get() or None,
                    incremental=self.incremental_var.get(),
                    questions=questions,
                    save_markdown=True,
                    summary_prompt=prompt,
                    sessions=sessions or None,
                )
            except Exception as exc:
                self.after(0, lambda: self._summary_failed(exc))
                return
            self.after(0, lambda r=result: self._summary_done(r))

        threading.Thread(target=worker, daemon=True).start()

    def _summary_failed(self, exc: Exception) -> None:
        self._running = False
        self.status_var.set("生成失败")
        messagebox.showerror("生成失败", str(exc))

    def _summary_done(self, result: Dict[str, object]) -> None:
        self._running = False
        text = result.get("summary") or ""
        qa = result.get("qa") or {}
        if qa:
            qa_lines = ["\n\n## 自定义问答"]
            for question, payload in qa.items():
                qa_lines.append(f"\n### {question}\n{payload.get('answer')}\n")
            text = f"{text}\n{''.join(qa_lines)}"
        self.output_text.delete("1.0", "end")
        self.output_text.insert("1.0", text)
        self.status_var.set("生成完成")
        self.refresh_history()

    def _load_history(self, _event) -> None:
        name = self.history_var.get()
        entry = next((item for item in getattr(self, "history_entries", []) if item.get("name") == name), None)
        if not entry:
            return
        try:
            content = self.app.pipeline.read_summary_history(entry.get("path"))
        except Exception as exc:
            messagebox.showerror("加载失败", str(exc))
            return
        self.output_text.delete("1.0", "end")
        self.output_text.insert("1.0", content)
        self.status_var.set(f"已加载历史文件：{name}")

    def _copy_summary(self) -> None:
        content = self.output_text.get("1.0", "end").strip()
        if not content:
            return
        self.clipboard_clear()
        self.clipboard_append(content)
        messagebox.showinfo("提示", "总结内容已复制。")

    def _save_summary(self, ext: str) -> None:
        content = self.output_text.get("1.0", "end").strip()
        if not content:
            return
        filetypes = [("Markdown", "*.md")] if ext == "md" else [("Text", "*.txt")]
        path = filedialog.asksaveasfilename(defaultextension=f".{ext}", filetypes=filetypes)
        if not path:
            return
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        messagebox.showinfo("提示", f"已保存：{path}")


class SettingsPage(BasePage):
    page_title = "设置"
    page_description = "配置导出路径与 LLM 参数，确保各功能能够正常运行。"

    def __init__(self, parent, app: WxAgentApp):
        super().__init__(parent, app)
        cfg = app.config
        self.export_dir_var = tk.StringVar(value=str(cfg.export_dir))
        self.summary_file_var = tk.StringVar(value=str(cfg.summary_output))
        self.summary_history_var = tk.StringVar(value=str(cfg.summary_history_dir))
        self.state_file_var = tk.StringVar(value=str(cfg.state_file))
        self.llm_model_var = tk.StringVar(value=str(cfg.llm_model))
        self.llm_base_var = tk.StringVar(value=str(cfg.llm_base_url or ""))
        self.llm_key_var = tk.StringVar(value=str(cfg.llm_api_key or ""))
        self.settings_status = tk.StringVar(value="")
        self._testing_llm = False

        container = ttk.Frame(self)
        container.pack(fill="both", expand=True, padx=12, pady=12)

        path_frame = ttk.LabelFrame(container, text="路径设置")
        path_frame.pack(fill="x", pady=(0, 12))
        self._build_path_row(path_frame, "聊天 JSON 目录", self.export_dir_var, True)
        self._build_path_row(path_frame, "总结输出文件", self.summary_file_var, False)
        self._build_path_row(path_frame, "总结历史目录", self.summary_history_var, True)
        self._build_path_row(path_frame, "状态文件", self.state_file_var, False)

        llm_frame = ttk.LabelFrame(container, text="大模型 API 设置")
        llm_frame.pack(fill="x")
        self._build_entry_row(llm_frame, "模型名称", self.llm_model_var)
        self._build_entry_row(llm_frame, "API Base URL", self.llm_base_var)
        self._build_entry_row(llm_frame, "API Key", self.llm_key_var, show="*")

        buttons = ttk.Frame(container)
        buttons.pack(fill="x", pady=(12, 0))
        ttk.Button(buttons, text="保存设置", command=self._save).pack(side="left")
        ttk.Button(buttons, text="测试 LLM 连接", command=self._test_llm).pack(side="left", padx=8)
        ttk.Label(buttons, textvariable=self.settings_status, foreground="#475467").pack(side="right")

    def _build_path_row(self, parent: ttk.Frame, label: str, var: tk.StringVar, is_dir: bool) -> None:
        row = ttk.Frame(parent)
        row.pack(fill="x", padx=12, pady=6)
        ttk.Label(row, text=label, width=16).pack(side="left")
        ttk.Entry(row, textvariable=var, width=60).pack(side="left", padx=(0, 8))
        if is_dir:
            ttk.Button(row, text="选择", command=lambda v=var: self._choose_dir(v)).pack(side="left")
        else:
            ttk.Button(row, text="选择", command=lambda v=var: self._choose_file(v)).pack(side="left")

    def _build_entry_row(self, parent: ttk.Frame, label: str, var: tk.StringVar, show: Optional[str] = None) -> None:
        row = ttk.Frame(parent)
        row.pack(fill="x", padx=12, pady=6)
        ttk.Label(row, text=label, width=16).pack(side="left")
        entry = ttk.Entry(row, textvariable=var, width=60, show=show)
        entry.pack(side="left", padx=(0, 8))

    def _choose_dir(self, var: tk.StringVar) -> None:
        path = filedialog.askdirectory()
        if path:
            var.set(path)

    def _choose_file(self, var: tk.StringVar) -> None:
        path = filedialog.asksaveasfilename()
        if path:
            var.set(path)

    def _save(self) -> None:
        cfg = self.app.config
        cfg.export_dir = Path(self.export_dir_var.get()).expanduser()
        cfg.summary_output = Path(self.summary_file_var.get()).expanduser()
        cfg.summary_history_dir = Path(self.summary_history_var.get()).expanduser()
        cfg.state_file = Path(self.state_file_var.get()).expanduser()
        cfg.llm_model = self.llm_model_var.get().strip() or cfg.llm_model
        cfg.llm_base_url = self.llm_base_var.get().strip() or None
        cfg.llm_api_key = self.llm_key_var.get().strip() or None
        cfg.save(self.app.config_path)
        self.app.reload_pipeline()
        self.settings_status.set("设置已保存。")

    def _test_llm(self) -> None:
        if getattr(self, "_testing_llm", False):
            return
        self._testing_llm = True
        self.settings_status.set("正在测试 LLM 接口...")

        def worker():
            ok, msg = self.app.pipeline.test_llm_connection()
            self.after(0, lambda: self._finish_llm_test(ok, msg))

        threading.Thread(target=worker, daemon=True).start()

    def _finish_llm_test(self, ok: bool, msg: str) -> None:
        self._testing_llm = False
        self.settings_status.set("LLM 测试完成" if ok else "LLM 测试失败")
        if ok:
            messagebox.showinfo("测试结果", msg)
        else:
            messagebox.showerror("测试失败", msg)




def launch(headless: bool = False, config_path: Optional[str] = None) -> None:
    if headless:
        print("UI headless 模式，未渲染窗口。")
        return
    root = tk.Tk()
    WxAgentApp(root, config_path=config_path)
    root.mainloop()


if __name__ == "__main__":
    launch()
