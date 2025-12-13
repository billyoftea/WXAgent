# 微信聊天记录分析测试脚本

Write-Host "=== 微信聊天记录智能分析测试 ===" -ForegroundColor Cyan
Write-Host ""

# 切换到后端目录
Set-Location "C:\Users\Lenovo\Desktop\WXAgent\backend"

# 检查编译文件是否存在
if (-not (Test-Path "wxagent_backend.exe")) {
    Write-Host "❌ wxagent_backend.exe 不存在，开始编译..." -ForegroundColor Red
    go build -o wxagent_backend.exe ./cmd/wxagent_backend
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ 编译失败" -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ 编译成功" -ForegroundColor Green
}

Write-Host ""
Write-Host "请选择测试场景：" -ForegroundColor Yellow
Write-Host "1. 分析所有聊天记录（最近导出的）"
Write-Host "2. 分析最近3天的消息"
Write-Host "3. 分析特定会话（手动输入会话名）"
Write-Host "4. 查看可用的会话列表"
Write-Host "5. 自定义参数测试"
Write-Host ""

$choice = Read-Host "请输入选项 (1-5)"

switch ($choice) {
    "1" {
        Write-Host ""
        Write-Host "📊 开始分析所有聊天记录..." -ForegroundColor Cyan
        .\wxagent_backend.exe analyze-chat
    }
    
    "2" {
        $today = Get-Date
        $startDate = $today.AddDays(-3).ToString("yyyy-MM-dd")
        $endDate = $today.ToString("yyyy-MM-dd")
        
        Write-Host ""
        Write-Host "📊 分析日期范围: $startDate 到 $endDate" -ForegroundColor Cyan
        .\wxagent_backend.exe analyze-chat --start-date $startDate --end-date $endDate
    }
    
    "3" {
        Write-Host ""
        Write-Host "请输入会话名称（支持多个，用逗号分隔）：" -ForegroundColor Yellow
        $sessions = Read-Host "会话名称"
        
        if ($sessions) {
            Write-Host ""
            Write-Host "📊 开始分析会话: $sessions" -ForegroundColor Cyan
            .\wxagent_backend.exe analyze-chat --sessions $sessions
        } else {
            Write-Host "❌ 未输入会话名称" -ForegroundColor Red
        }
    }
    
    "4" {
        Write-Host ""
        Write-Host "📋 可用的会话列表（JSON文件）：" -ForegroundColor Cyan
        Write-Host ""
        
        $jsonFiles = Get-ChildItem "..\output\*.json" -File | Where-Object { $_.Name -notlike "*.export_state" }
        
        if ($jsonFiles.Count -eq 0) {
            Write-Host "❌ 未找到任何聊天记录文件" -ForegroundColor Red
            Write-Host "提示：请先运行 export-auto 命令导出聊天记录" -ForegroundColor Yellow
        } else {
            $index = 1
            foreach ($file in $jsonFiles) {
                $fileName = $file.Name -replace '\.json$', ''
                Write-Host "$index. $fileName" -ForegroundColor Green
                $index++
            }
            Write-Host ""
            Write-Host "总共 $($jsonFiles.Count) 个会话" -ForegroundColor Cyan
        }
        
        Write-Host ""
        $analyze = Read-Host "是否要分析这些会话？(y/n)"
        if ($analyze -eq "y") {
            .\wxagent_backend.exe analyze-chat
        }
    }
    
    "5" {
        Write-Host ""
        Write-Host "📝 自定义参数设置：" -ForegroundColor Yellow
        
        $startDate = Read-Host "开始日期 (YYYY-MM-DD, 回车跳过)"
        $endDate = Read-Host "结束日期 (YYYY-MM-DD, 回车跳过)"
        $sessions = Read-Host "会话名称 (多个用逗号分隔, 回车跳过)"
        $maxTokens = Read-Host "最大tokens (回车使用默认100000)"
        $output = Read-Host "输出文件路径 (回车使用默认)"
        
        $args = @("analyze-chat")
        
        if ($startDate) { $args += "--start-date"; $args += $startDate }
        if ($endDate) { $args += "--end-date"; $args += $endDate }
        if ($sessions) { $args += "--sessions"; $args += $sessions }
        if ($maxTokens) { $args += "--max-tokens"; $args += $maxTokens }
        if ($output) { $args += "--output"; $args += $output }
        
        Write-Host ""
        Write-Host "📊 执行命令: .\wxagent_backend.exe $($args -join ' ')" -ForegroundColor Cyan
        Write-Host ""
        
        & .\wxagent_backend.exe $args
    }
    
    default {
        Write-Host "❌ 无效的选项" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "=== 测试完成 ===" -ForegroundColor Cyan

# 询问是否打开报告
Write-Host ""
$openReport = Read-Host "是否打开生成的报告？(y/n)"
if ($openReport -eq "y") {
    $reportPath = "..\output\chat_analysis.md"
    if (Test-Path $reportPath) {
        notepad $reportPath
    } else {
        Write-Host "❌ 报告文件不存在" -ForegroundColor Red
    }
}
