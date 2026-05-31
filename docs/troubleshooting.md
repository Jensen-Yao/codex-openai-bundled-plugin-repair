# 故障排查

## UI 已显示但插件仍 unavailable

CodexUnhide / Codex++ 用户脚本只恢复隐藏入口，不负责安装或启用 Codex 插件。

先运行：

```powershell
.\scripts\verify-openai-bundled-plugins.ps1
```

如果命令行没有显示 bundled 插件为 `installed, enabled`，运行修复脚本。如果命令行验证通过但 Codex UI 仍显示 unavailable，通常是前端还在用旧缓存，重启 Codex Desktop 或刷新窗口后再看。

## Discover 或 Built by OpenAI 里找不到

`openai-bundled` 是 Codex 自带的本地插件源，不一定作为普通远程市场条目展示。安装后这些插件可能在：

```text
Plugins - Unlocked -> Manage
```

它们不一定出现在 `Discover`、`All` 或 `Built by OpenAI`。

## `Windows Computer Use helper paths are unavailable`

这说明 Codex 已经走到 Computer Use 功能路径，但无法从已安装插件 cache 里解析 helper 文件。

检查这个文件是否存在：

```text
%USERPROFILE%\.codex\plugins\cache\openai-bundled\computer-use\<version>\node_modules\@oai\sky\bin\windows\codex-computer-use.exe
```

transport 代码也需要存在，但路径会随版本变化。可能在：

```text
%USERPROFILE%\.codex\plugins\cache\openai-bundled\computer-use\<version>\scripts\computer-use-client.mjs
%USERPROFILE%\.codex\plugins\cache\openai-bundled\computer-use\<version>\node_modules\@oai\sky\dist\...
```

不要把 `bin\windows\helper_transport.js` 当成固定路径；有些版本只有 `codex-computer-use.exe` 在 `bin\windows` 下。

如果 helper exe 缺失，说明插件源可能注册了，但 `computer-use@openai-bundled` 没有真正安装进 plugin cache。重新运行：

```powershell
.\scripts\repair-openai-bundled-plugins.ps1
```

刷新或重启成功后，日志里可能出现：

```text
computer-use native pipe startup ready
```

## 设置页仍显示 plugin unavailable

如果验证脚本显示所有插件都是 `installed, enabled`，但 Codex UI 仍显示 unavailable，通常是当前 Electron 进程还在用旧插件列表。

按顺序尝试：

1. 重启 Codex Desktop
2. 刷新 Codex 窗口
3. 调试场景下触发内部刷新：

```javascript
window.electronBridge.sendMessageFromView({ type: "reload-bundled-plugins" })
```

如果仍失败，查看最新 Codex 日志里的 `openai-bundled`、`marketplace`、`computer-use`、`plugin` 关键字。

## `os error 6000`

错误示例：

```text
failed to copy plugin file: The specified file could not be encrypted. (os error 6000)
```

原因通常是 WindowsApps 目录里的 Codex 插件带有 `Encrypted` / `Application Protected` 属性。普通复制会尝试保留无法在用户目录重建的属性。

解决方式：使用本仓库的 `repair-openai-bundled-plugins.ps1`。脚本不会用 `robocopy` 复制受保护文件，而是逐字节读取源文件，再写入用户目录。

## Codex 更新后旧路径消失

Codex Desktop 可能自动更新，真实路径会随版本变化，例如：

```text
OpenAI.Codex_26.527.31326.0_x64__2p2nqsd0c76g0
OpenAI.Codex_26.527.3686.0_x64__2p2nqsd0c76g0
```

WindowsApps 包也可能在其他盘：

```text
D:\WindowsApps
E:\WindowsApps
F:\WindowsApps
```

`C:\Program Files\WindowsApps` 有时只是重解析或虚拟入口。脚本会扫描常见 WindowsApps 根目录，并选择最新的有效 Codex resources 目录。

## `codex.exe` 不能直接运行

Windows 可能阻止直接执行 WindowsApps 包里的程序。修复脚本会优先使用 PATH 里可运行的 `codex`，再尝试 bundled CLI。

如果你的机器阻止 bundled CLI，可以把 CLI 复制到用户可写目录，或在 PATH 已有可用 `codex` 的环境里运行。

## `\\?\` 长路径前缀导致 UI 不一致

某些 CLI 流程能接受这种长路径：

```text
\\?\C:\Users\<you>\.codex\bundled-marketplaces\openai-bundled
```

但 Electron UI 未必完全按同一方式解析。建议 `config.toml` 里使用普通路径：

```text
C:\Users\<you>\.codex\bundled-marketplaces\openai-bundled
```

## 找不到 Codex 安装目录

脚本会自动扫描所有文件系统盘的 `WindowsApps`，典型路径包括：

```text
C:\Program Files\WindowsApps\OpenAI.Codex_*\app\resources
C:\WindowsApps\OpenAI.Codex_*\app\resources
D:\WindowsApps\OpenAI.Codex_*\app\resources
E:\WindowsApps\OpenAI.Codex_*\app\resources
F:\WindowsApps\OpenAI.Codex_*\app\resources
```

如果 Codex 安装在其他位置，可以手动传参：

```powershell
.\scripts\repair-openai-bundled-plugins.ps1 -CodexInstallRoot "E:\WindowsApps\OpenAI.Codex_26.527.3686.0_x64__2p2nqsd0c76g0\app\resources"
```

## 插件已安装但 Chrome 仍不可控

`chrome@openai-bundled` 安装成功只代表 Codex 插件存在。实际控制 Chrome 还依赖：

- Chrome 已安装
- Codex Chrome Extension 已安装并启用
- Native Host 正常
- 当前 Chrome Profile 是扩展所在的 Profile

这种情况应在 Codex 的 Chrome 插件设置页重新安装或连接扩展。

## Computer Use 入口可见但无法使用

`computer-use@openai-bundled` 安装成功后，仍可能被以下条件拦住：

- 账号或服务端未开放能力
- 系统权限未授权
- 当前 Codex 后端连接异常
- Windows helper 程序被安全软件拦截

本仓库只处理本地插件源和插件安装，不绕过服务端权限。
