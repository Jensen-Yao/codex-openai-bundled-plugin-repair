# Codex openai-bundled 插件修复指南

这个仓库记录一套 Windows 上修复 Codex Desktop 内置插件不可用的流程。

适用现象：

- `Settings -> Computer use` 显示 `Computer Use plugins unavailable`
- `Settings -> Browser` 显示 `In-app browser plugin unavailable`
- 插件列表里找不到 `Browser`、`Computer Use`、`Chrome`
- `~/.codex/config.toml` 里 `openai-bundled` 指向已经不存在的临时目录

## 原因

Codex Desktop 自带一组 `openai-bundled` 插件，例如：

- `browser@openai-bundled`
- `computer-use@openai-bundled`
- `chrome@openai-bundled`

如果本机配置里的 `openai-bundled` marketplace 指向失效路径，例如：

```toml
[marketplaces.openai-bundled]
source = '\\?\C:\Users\<you>\.codex\.tmp\bundled-marketplaces\openai-bundled'
```

Codex 就读不到这些内置插件，设置页会显示 unavailable。

另一个常见问题是 WindowsApps 目录的插件文件带有 `Encrypted` / `Application Protected` 属性，直接用 `copy`、`robocopy` 或 `codex plugin add` 从 WindowsApps 复制时可能失败：

```text
The specified file could not be encrypted. (os error 6000)
```

本仓库的脚本会用逐字节读取再写入的方式，把内置插件源镜像到用户目录，然后让 Codex 从稳定路径安装插件。

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
3. 备份 `%USERPROFILE%\.codex\config.toml`
4. 重新注册 `openai-bundled` marketplace
5. 安装并启用 `browser`、`computer-use`、`chrome`
6. 清理旧的错误项 `browser-use@openai-bundled`
7. 打印验证结果

完成后重启 Codex Desktop，或刷新 Codex 窗口，让设置页重新读取插件列表。

## 手工流程

如果不想运行脚本，可以按下面的思路手工处理：

1. 找到 Codex 自带插件源：

```text
C:\Program Files\WindowsApps\OpenAI.Codex_<version>_x64__2p2nqsd0c76g0\app\resources\plugins\openai-bundled
```

有些机器实际路径在：

```text
D:\WindowsApps\OpenAI.Codex_<version>_x64__2p2nqsd0c76g0\app\resources\plugins\openai-bundled
```

2. 镜像到稳定目录：

```text
%USERPROFILE%\.codex\bundled-marketplaces\openai-bundled
```

3. 用 Codex CLI 注册并安装：

```powershell
codex plugin marketplace remove openai-bundled
codex plugin marketplace add "$env:USERPROFILE\.codex\bundled-marketplaces\openai-bundled"
codex plugin add browser@openai-bundled
codex plugin add computer-use@openai-bundled
codex plugin add chrome@openai-bundled
```

4. 删除 `config.toml` 里旧的错误项：

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
browser@openai-bundled       installed, enabled
computer-use@openai-bundled  installed, enabled
chrome@openai-bundled        installed, enabled
```

## 限制

这只修复本地插件源和插件安装状态。实际使用 `Chrome` 或 `Computer Use` 时，仍可能需要：

- Codex 账号/服务端能力支持
- Chrome 扩展已安装并启用
- Native Host 配对正常
- Windows 权限确认
- 网络能连到 Codex/OpenAI 相关服务

## 相关文档

- [故障排查](docs/troubleshooting.md)
- [回滚方式](docs/rollback.md)
