WXAgent：wx_key + echotrace + LLM 汇总流水线
============================================

本仓库整合了三套能力：

1. **wx_key**：通过 DLL Hook 提取微信数据库与图片解密密钥。
2. **echotrace**：借助密钥拉取微信数据库并导出结构化 JSON（支持增量导出及 `.export_state`）。
3. **wx_agent**：Python 调度层，负责自动读取新增聊天记录、调用大模型做多群聊总结，并提供 CLI / 桌面 UI。

目标：一键生成“每日新增聊天纪要”，并支持自定义问题问答，可进一步打包为单一 EXE 分发。

----------------------------------------------------------

快速开始
--------

1. **准备运行环境**
   - Windows 10/11，Python 3.10+。
   - `pip install -r wx_agent/requirements.txt`。
   - 设置 LLM API Key（目前默认 DeepSeek V3/字节火山方舟接口）：  
     `set ARK_API_KEY=xxxx`（或 `LLM_API_KEY/OPENAI_API_KEY` 等）。

2. **配置路径**
   - 复制 `wx_agent/config.example.json` 为 `wx_agent/config.json`，根据实际环境调整：
     - `export_dir`：echotrace 导出 JSON 所在目录（默认 `../output_test`）。
     - `wx_key_shared_prefs`：wx_key 输出的 `shared_preferences.json` 路径，默认 `%APPDATA%\com.example\wx_key\shared_preferences.json`。
     - （可选）`echotrace_command`：若有 CLI 版 echotrace，可写入 `path` 与 `args`，在 CLI/UI 中一键触发导出。

3. **运行 CLI**

```
# 读取最近一次的数据库密钥
python -m wx_agent.cli refresh-key

# 手动（可选）启动一次 echotrace 导出
python -m wx_agent.cli export

# 生成增量总结（默认写入 summary_result.md）
set ARK_API_KEY=xxxxx
python -m wx_agent.cli summarize --start-date 2025-11-10 --end-date 2025-11-13 --question "今天有哪些招聘信息？"

# 启动桌面 UI
python -m wx_agent.cli ui
```

4. **打包为 EXE（可选）**
   - wx_key / echotrace 按各自仓库指引用 Flutter/Go 构建 Windows Release。
   - wx_agent 可使用 `pyinstaller -F wx_agent\cli.py` 等方式打包（注意将 `config.json`、依赖 dll 等放在同目录）。

----------------------------------------------------------

新增流水线能力
--------------

| 能力 | 描述 |
| --- | --- |
| wx_key 桥接 | 默认读取 `%APPDATA%\com.example\wx_key\shared_preferences.json`，解析 `flutter.wechat_db_key` 及图片密钥，可在 CLI/UI 一键查看。 |
| echotrace 增量读取 | 直接消费 `output_test/*.json` 及 `.export_state`，结合 `.wx_agent_state.json` 跳过已处理消息，并支持时间过滤。 |
| LLM 总结 | `wx_agent/summarizer.py` 提供 Map-Reduce Summarizer + 自定义问答引擎，可配置 Prompt、token 限额与并发度。 |
| CLI & UI | `python -m wx_agent.cli summarize` 便于自动化；`python -m wx_agent.cli ui` 提供 Tkinter 界面（日期筛选、增量开关、自定义问题、滚动查看结果）。 |

----------------------------------------------------------

配置字段速览（`wx_agent/config.json`）
--------------------------------------

| 字段 | 说明 |
| --- | --- |
| `export_dir` | echotrace 导出的 JSON 目录 |
| `state_file` | 增量状态文件（默认 `../.wx_agent_state.json`） |
| `wx_key_shared_prefs` | wx_key SharedPreferences 路径 |
| `llm_model` / `llm_temperature` / `max_tokens` 等 | LLM 相关参数 |
| `custom_questions` / `questions_file` | 预置问答模板，可与 CLI/UI 输入合并 |

> 提示：若要自动调起 echotrace，可在 `echotrace_command.path` 中写入 `echotrace.exe`，并根据自身编译版本追加 `args`（例如 `["--auto-export", "--output", "../output_test"]`）。

----------------------------------------------------------

CLI 指令一览
------------

| 命令 | 作用 |
| --- | --- |
| `python -m wx_agent.cli refresh-key` | 读取 wx_key 的最新密钥（可带 `--ensure` 自动拉起 wx_key） |
| `python -m wx_agent.cli launch-wx-key` | 直接启动 wx_key GUI，便于独立操作 |
| `python -m wx_agent.cli export` | 触发配置中的 echotrace 命令 |
| `python -m wx_agent.cli summarize [参数]` | 生成总结；支持 `--full` 全量分析、`--question` 追加问答、`--json` 机器可读输出 |
| `python -m wx_agent.cli ui` | 启动桌面 UI，支持日期/增量/问题配置与结果预览 |

----------------------------------------------------------

单 EXE 打包
-----------

项目提供 `scripts/build_bundle.ps1`，可在 Windows 上一键编译 wx_key / echotrace / wx_agent 并生成单文件 EXE：

```
pwsh -ExecutionPolicy Bypass -File scripts/build_bundle.ps1 `
    -Configuration Release `
    -OutputName wx_agent_bundle
```

脚本会执行：
1. `flutter build windows --release`（分别在 `wx_key/` 与 `echotrace/`）。
2. 将生成的 `wx_key.exe` / `echotrace.exe` 拷贝到 `wx_agent/bin/`，供 Python 层调用或与 PyInstaller 一起打包。
3. `pip install -r wx_agent/requirements.txt` 并确保安装 `pyinstaller`。
4. 使用 `pyinstaller --onefile wx_agent/cli.py --add-data wx_agent/bin;bin` 生成 `dist/<OutputName>.exe`，同时把当前 `config.json` 复制到 `dist/config.json`。

最终使用方式：

```
cd dist
.\wx_agent_bundle.exe refresh-key --ensure
.\wx_agent_bundle.exe summarize --start-date 2025-11-10 --end-date 2025-11-13
```

> 注意：由于 wx_key / echotrace 仍然是 UI 程序，当它们由打包后的 EXE 调用时依旧需要人工完成 GUI 操作，只是所有组件已经封装在一个入口中。

----------------------------------------------------------

桌面 UI 功能
------------

`wx_agent/ui.py` 通过 Tkinter 实现：
- 日期范围输入、增量分析开关。
- 多个自定义问题（逐行输入）。
- 按钮功能：
  - “刷新密钥”：读取 wx_key SharedPreferences。
  - “拉取聊天”：执行配置中的 echotrace 命令。
  - “生成总结”：后台线程跑流水线，完成后把总结、问答写入滚动文本框，并保存到 `summary_output`。
- 运行过程中禁用按钮 + 状态栏提示，避免 UI 卡死。

----------------------------------------------------------

架构摘要
--------

```
wx_key (Flutter + DLL) ──> shared_preferences.json
                                 │
                                 v
                          WxAgent Pipeline
                                 │
echotrace (Flutter/Go) ──> output_test/*.json + .export_state
                                 │
                                 v
                      Tokenizer / LLM  ──> summary_result.md
                                 │
                                 v
                         CLI / Tk UI / EXE
```

wx_agent 充当“粘合层”，把密钥抓取、数据库解密、增量筛选、LLM 总结、问题问答、桌面 UI 统一打包，落地 README 最初提出的场景需求。
