# 故障排查

## 设置页仍显示 plugin unavailable

先运行：

```powershell
.\scripts\verify-openai-bundled-plugins.ps1
```

如果命令行显示三项都是 `installed, enabled`，但 Codex UI 仍显示 unavailable，通常是前端还在用旧缓存。重启 Codex Desktop 或刷新窗口后再看。

## `os error 6000`

错误示例：

```text
failed to copy plugin file: The specified file could not be encrypted. (os error 6000)
```

原因通常是 WindowsApps 目录里的 Codex 插件带有 `Encrypted` / `Application Protected` 属性。直接复制会失败。

解决方式：使用本仓库的 `repair-openai-bundled-plugins.ps1`。脚本不会用 `robocopy` 复制受保护文件，而是逐字节读取源文件，再写入用户目录。

## 找不到 Codex 安装目录

脚本会自动扫描：

```text
C:\Program Files\WindowsApps\OpenAI.Codex_*\app\resources
C:\WindowsApps\OpenAI.Codex_*\app\resources
D:\WindowsApps\OpenAI.Codex_*\app\resources
E:\WindowsApps\OpenAI.Codex_*\app\resources
F:\WindowsApps\OpenAI.Codex_*\app\resources
```

如果 Codex 安装在其他位置，可以手动传参：

```powershell
.\scripts\repair-openai-bundled-plugins.ps1 -CodexInstallRoot "D:\WindowsApps\OpenAI.Codex_26.527.3686.0_x64__2p2nqsd0c76g0\app\resources"
```

## `codex` 命令不可用

脚本优先使用安装目录里的：

```text
resources\codex.exe
```

如果找不到，会回退到 PATH 里的 `codex`。如果两者都没有，说明 Codex Desktop 安装不完整，或路径没有被脚本扫描到。

## 插件已安装但 Chrome 仍不可控

`chrome@openai-bundled` 安装成功只代表 Codex 插件存在。实际控制 Chrome 还依赖：

- Chrome 已安装
- Codex Chrome Extension 已安装并启用
- Native Host 正常
- 当前 Chrome Profile 是扩展所在的 Profile

这种情况应在 Codex 的 Chrome 插件设置页重新安装/连接扩展。

## Computer Use 入口可见但无法使用

`computer-use@openai-bundled` 安装成功后，仍可能被以下条件拦住：

- 账号或服务端未开放能力
- 系统权限未授权
- 当前 Codex 后端连接异常
- Windows helper 程序被安全软件拦截

本仓库只处理本地插件源和插件安装，不绕过服务端权限。
