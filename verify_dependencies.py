#!/usr/bin/env python3
"""
WXAgent 依赖项验证脚本
检查所有必需的外部依赖项是否可用
"""

import json
import os
import platform
import subprocess
import sys
from pathlib import Path

def check_file_exists(file_path: str, description: str) -> bool:
    """检查文件是否存在"""
    path = Path(file_path).expanduser()
    exists = path.exists()
    status = "[OK]" if exists else "[MISSING]"
    print(f"{status} {description}: {file_path}")
    if exists:
        size = path.stat().st_size
        print(f"   Size: {size} bytes")
    return exists

def check_directory_exists(dir_path: str, description: str) -> bool:
    """检查目录是否存在"""
    path = Path(dir_path).expanduser()
    exists = path.exists() and path.is_dir()
    status = "[OK]" if exists else "[MISSING]"
    print(f"{status} {description}: {dir_path}")
    if exists:
        try:
            file_count = len(list(path.iterdir()))
            print(f"   Contains {file_count} entries")
        except PermissionError:
            print(f"   WARNING: No permission to access")
    return exists

def check_executable(file_path: str, description: str) -> bool:
    """检查可执行文件是否可用"""
    path = Path(file_path).expanduser()
    exists = path.exists() and path.is_file()
    status = "[OK]" if exists else "[MISSING]"
    print(f"{status} {description}: {file_path}")
    if exists:
        if platform.system() == "Windows":
            try:
                result = subprocess.run(
                    [str(path), "--version"],
                    capture_output=True,
                    timeout=5,
                    creationflags=subprocess.CREATE_NO_WINDOW
                )
                if result.returncode == 0:
                    print(f"   Executable (return code: {result.returncode})")
                    return True
            except Exception as e:
                print(f"   WARNING: Not executable: {e}")
        return exists
    return False

def load_config() -> dict:
    """加载配置文件"""
    config_path = Path(__file__).parent / "wx_agent" / "config.json"
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"❌ 无法加载配置文件: {e}")
        return {}

def main():
    """主函数"""
    print("=" * 60)
    print("WXAgent Dependency Verification")
    print("=" * 60)
    print()

    config = load_config()

    print("Directory Checks")
    print("-" * 60)
    check_directory_exists(
        config.get("export_dir", "../output_test"),
        "Export Output Directory"
    )
    check_directory_exists(
        config.get("summary_history_dir", "../summary_history"),
        "Summary History Directory"
    )
    check_directory_exists(
        config.get("wechat_data_path", ""),
        "WeChat Data Directory"
    )
    print()

    print("Key File Checks")
    print("-" * 60)
    check_file_exists(
        config.get("wx_key_shared_prefs", ""),
        "wx_key Shared Preferences"
    )
    print()

    print("Executable Checks")
    print("-" * 60)
    wx_key_cmd = config.get("wx_key_command", {})
    check_executable(
        wx_key_cmd.get("path", ""),
        "wx_key.exe"
    )
    echotrace_cmd = config.get("echotrace_command", {})
    check_executable(
        echotrace_cmd.get("path", ""),
        "echotrace.exe"
    )
    print()

    print("DLL File Checks")
    print("-" * 60)
    dll_paths = [
        ("../echotrace/windows/runner/go_decrypt.dll", "go_decrypt.dll (runner)"),
        ("../echotrace/build/windows/x64/runner/Release/go_decrypt.dll", "go_decrypt.dll (build)"),
        ("wx_agent/bin/echotrace/go_decrypt.dll", "go_decrypt.dll (bin)"),
    ]

    dll_found = False
    for dll_path, description in dll_paths:
        if check_file_exists(dll_path, description):
            dll_found = True
            break

    if not dll_found:
        print("WARNING: go_decrypt.dll not found, Flutter app will try multiple paths")
    print()

    print("=" * 60)
    print("Verification Complete")
    print("=" * 60)

    print("\nRepair Suggestions:")
    print("1. If DLL loading fails, Flutter app will automatically try multiple paths")
    print("2. If executables are unavailable, check if paths are correct")
    print("3. If directories don't exist, create them or update config.json")
    print("4. Ensure Visual C++ Redistributable is installed (for DLL runtime)")

if __name__ == "__main__":
    main()
