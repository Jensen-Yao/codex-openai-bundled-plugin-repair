# Codex openai-bundled 插件修复指南

这个仓库记录一套 Windows 上修复 Codex Desktop 内置插件不可用的流程。

适用现象：

- `Settings -> Computer use` 显示 `Computer Use plugins unavailable`
- `Settings -> Browser` 显示 `In-app browser plugin unavailable`
- 插件列表里找不到或不能调用 `Browser`、`Computer Use`、`Chrome`、`LaTeX`
- Codex++ / CodexUnhide 已经让插件入口显示出来，但点击后仍然提示 unavailable
- `~/.codex/config.toml` 里 `openai-bundled` 指向已经不存在的临时目录
- 日志里出现 `Windows Computer Use helper paths are unavailable`

## 修复范围

这里要区分两层问题：

1. UI 可见性：CodexUnhide 这类脚本可以恢复隐藏按钮或设置入口。
2. 插件真实可用性：Codex 仍然需要有效的 `openai-bundled` marketplace、已安装的 plugin cache、以及启用状态。

本仓库修第二层。它不绕过账号权限、服务端开关、Chrome 扩展配对、Windows 授权等要求。

## 原因

Codex Desktop 自带一组 `openai-bundled` 插件，例如：

- `browser@openai-bundled`
- `computer-use@openai-bundled`
- `chrome@openai-bundled`
- `latex@openai-bundled`

如果本机配置里的 `openai-bundled` marketplace 没注册，或指向失效路径，例如：

```toml
[marketplaces.openai-bundled]
source = '\\?\C:\Users\<you>\.codex\.tmp\bundled-marketplaces\openai-bundled'
```

Codex 就读不到这些内置插件，设置页会显示 unavailable。

另一个常见问题是 WindowsApps 目录里的 Codex 文件带有 `Encrypted` / `Application Protected` 属性。直接用 `Copy-Item`、`robocopy` 或 `codex plugin add` 从 WindowsApps 复制时可能失败：

```text
The specified file could not be encrypted. (os error 6000)
```

本仓库脚本会用逐字节读取再写入的方式，把内置插件源镜像到用户目录，再让 Codex 从稳定路径注册、安装、启用插件。

## 快速修复

在 PowerShell 中进入本仓库后运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\repair-openai-bundled-plugins.ps1
.\scripts\verify-openai-bundled-plugins.ps1
```

脚本会做这些事：

1. 自动定位 Codex Desktop 安装目录里的 `resources\plugins\openai-bundled`
2. 镜像到稳定目录：`%USERPROFILE%\.codex\bundled-marketplaces\openai-bundled`
3. 同时镜像到 resources 形状目录：`%USERPROFILE%\.codex\bundled-resources\plugins\openai-bundled`
4. 备份 `%USERPROFILE%\.codex\config.toml`
5. 重新注册 `openai-bundled` marketplace
6. 安装并启用 `browser`、`computer-use`、`chrome`、`latex`
7. 清理旧的错误项 `browser-use@openai-bundled`
8. 打印 marketplace、插件、Computer Use helper 验证结果

完成后重启 Codex Desktop，或刷新 Codex 窗口，让设置页重新读取插件列表。

## 手工流程

1. 找到 Codex 自带插件源：

```text
C:\Program Files\WindowsApps\OpenAI.Codex_<version>_x64__2p2nqsd0c76g0\app\resources\plugins\openai-bundled
```

有些机器实际路径在其他盘：

```text
D:\WindowsApps\OpenAI.Codex_<version>_x64__2p2nqsd0c76g0\app\resources\plugins\openai-bundled
E:\WindowsApps\OpenAI.Codex_<version>_x64__2p2nqsd0c76g0\app\resources\plugins\openai-bundled
```

2. 镜像到稳定目录：

```text
%USERPROFILE%\.codex\bundled-marketplaces\openai-bundled
%USERPROFILE%\.codex\bundled-resources\plugins\openai-bundled
```

如果普通复制遇到 `os error 6000`，需要用逐字节复制方式。

3. 用 Codex CLI 注册并安装：

```powershell
codex plugin marketplace remove openai-bundled
codex plugin marketplace add "$env:USERPROFILE\.codex\bundled-marketplaces\openai-bundled"
codex plugin add browser@openai-bundled
codex plugin add computer-use@openai-bundled
codex plugin add chrome@openai-bundled
codex plugin add latex@openai-bundled
```

如果 WindowsApps 里的 `codex.exe` 不能直接运行，可以使用 PATH 里的 Codex CLI，或先把 bundled CLI 复制到用户目录再运行。

4. 删除 `config.toml` 里的旧错误项：

```toml
[plugins."browser-use@openai-bundled"]
enabled = true
```

5. 验证：

```powershell
codex plugin marketplace list
codex plugin list
```

期望看到：

```text
browser@openai-bundled        installed, enabled
computer-use@openai-bundled   installed, enabled
chrome@openai-bundled         installed, enabled
latex@openai-bundled          installed, enabled
```

Computer Use 的 helper 必须存在于类似路径：

```text
%USERPROFILE%\.codex\plugins\cache\openai-bundled\computer-use\<version>\node_modules\@oai\sky\bin\windows\codex-computer-use.exe
```

transport 代码的文件位置会随版本变化，可能在 `scripts\computer-use-client.mjs` 或 `node_modules\@oai\sky\dist\...` 下，不建议把 `helper_transport.js` 写死成唯一判断条件。

运行中的 Codex 成功拉起后，日志里可能出现：

```text
computer-use native pipe startup ready
```

## UI 里在哪里看

内置 bundled 插件不一定出现在 `Discover` / `All` / `Built by OpenAI` 列表里。安装后更可能出现在：

```text
Plugins - Unlocked -> Manage
```

如果命令行验证通过但 UI 还停留在旧状态，重启 Codex Desktop 最直接。部分版本也可以从 renderer 触发内部刷新：

```javascript
window.electronBridge.sendMessageFromView({ type: "reload-bundled-plugins" })
```

这更适合调试；普通使用建议重启。

## 可选的持久 resources 路径

部分 Codex Desktop 版本支持通过下面的用户环境变量读取 resources 形状的稳定镜像：

```powershell
[Environment]::SetEnvironmentVariable(
  "CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH",
  "$env:USERPROFILE\.codex\bundled-resources",
  "User"
)
```

修复脚本会打印这个路径。一般情况下注册 marketplace 并安装插件已经足够；这个环境变量主要用于让未来启动的 Codex 从稳定镜像执行 bundled reconcile，而不是再依赖 WindowsApps 临时同步。

## 限制

这只修复本地插件源和插件安装状态。实际使用 `Chrome` 或 `Computer Use` 时，仍可能需要：

- Codex 账号/服务端能力支持
- Chrome 扩展已安装并启用
- Native Host 配对正常
- Windows 权限确认
- 网络能连到 Codex/OpenAI 相关服务

## 相关文档

- [故障排查](docs/troubleshooting.md)
- [第二台电脑案例](docs/second-machine-case-study.md)
- [回滚方式](docs/rollback.md)
