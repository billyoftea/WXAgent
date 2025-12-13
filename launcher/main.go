// WXAgent Launcher - 同时启动后端和前端
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

var (
	backendPort  = flag.Int("port", 8000, "后端服务器端口")
	showConsole  = flag.Bool("console", false, "显示后端控制台")
	backendOnly  = flag.Bool("backend-only", false, "仅启动后端")
	frontendOnly = flag.Bool("frontend-only", false, "仅启动前端")
)

func main() {
	flag.Parse()

	// 获取可执行文件所在目录
	exePath, err := os.Executable()
	if err != nil {
		log.Fatalf("获取执行路径失败: %v", err)
	}
	baseDir := filepath.Dir(exePath)

	fmt.Println("========================================")
	fmt.Println("    WXAgent 启动器")
	fmt.Println("========================================")
	fmt.Printf("工作目录: %s\n", baseDir)
	fmt.Printf("后端端口: %d\n", *backendPort)
	fmt.Println()

	var backendCmd *exec.Cmd
	var frontendCmd *exec.Cmd

	// 启动后端
	if !*frontendOnly {
		backendPath := filepath.Join(baseDir, "wxagent_backend.exe")
		if _, err := os.Stat(backendPath); os.IsNotExist(err) {
			// 尝试其他可能的路径
			backendPath = filepath.Join(baseDir, "backend", "wxagent_backend.exe")
		}
		if _, err := os.Stat(backendPath); os.IsNotExist(err) {
			backendPath = filepath.Join(baseDir, "wx_agent.exe")
		}

		if _, err := os.Stat(backendPath); os.IsNotExist(err) {
			log.Printf("⚠️  警告: 未找到后端程序，尝试的路径: %s\n", backendPath)
		} else {
			fmt.Printf("🚀 启动后端: %s\n", backendPath)
			backendCmd = exec.Command(backendPath, "server", fmt.Sprintf("--port=%d", *backendPort))
			backendCmd.Dir = baseDir

			if *showConsole {
				backendCmd.Stdout = os.Stdout
				backendCmd.Stderr = os.Stderr
			}

			if err := backendCmd.Start(); err != nil {
				log.Printf("❌ 启动后端失败: %v\n", err)
			} else {
				fmt.Println("✅ 后端已启动")
			}

			// 等待后端启动
			time.Sleep(2 * time.Second)
		}
	}

	// 启动前端
	if !*backendOnly {
		// 尝试多个可能的前端路径
		frontendPaths := []string{
			filepath.Join(baseDir, "wx_agent_app.exe"),
			filepath.Join(baseDir, "frontend", "wx_agent_app.exe"),
			filepath.Join(baseDir, "bin", "wx_agent_app", "wx_agent_app.exe"),
		}

		var frontendPath string
		for _, p := range frontendPaths {
			if _, err := os.Stat(p); err == nil {
				frontendPath = p
				break
			}
		}

		if frontendPath == "" {
			log.Printf("⚠️  警告: 未找到前端程序\n")
		} else {
			fmt.Printf("🎨 启动前端: %s\n", frontendPath)
			frontendCmd = exec.Command(frontendPath)
			frontendCmd.Dir = filepath.Dir(frontendPath)

			// 前端始终显示窗口
			if err := frontendCmd.Start(); err != nil {
				log.Printf("❌ 启动前端失败: %v\n", err)
			} else {
				fmt.Println("✅ 前端已启动")
			}
		}
	}

	fmt.Println()
	fmt.Println("----------------------------------------")
	fmt.Println("WXAgent 已启动！按 Ctrl+C 退出")
	fmt.Println("----------------------------------------")

	// 等待中断信号
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// 等待前端关闭或中断信号
	done := make(chan struct{})

	if frontendCmd != nil && frontendCmd.Process != nil {
		go func() {
			frontendCmd.Wait()
			close(done)
		}()
	}

	select {
	case <-sigChan:
		fmt.Println("\n收到退出信号，正在关闭...")
	case <-done:
		fmt.Println("\n前端已关闭，正在退出...")
	}

	// 清理：关闭后端
	if backendCmd != nil && backendCmd.Process != nil {
		fmt.Println("正在关闭后端...")
		backendCmd.Process.Kill()
	}

	fmt.Println("WXAgent 已退出")
}
