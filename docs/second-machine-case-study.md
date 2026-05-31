# 第二台电脑案例

这份案例来自另一台 Windows 机器：Codex++ / CodexUnhide 已经让插件入口显示出来，但 Browser、Chrome、Computer Use、LaTeX 仍然不可用。

## 发生了什么

Codex++ 用户脚本目录是：

```text
C:\Users\Administrator\AppData\Roaming\Codex++\user_scripts
```

一开始 `user_scripts.json` 不存在，后来创建并启用了：

```text
user:codex-feature-visibility-injector.js
```

这一步只让 UI 入口可见。设置页仍然显示 unavailable，根因不是按钮隐藏，而是 Codex 自带的 `openai-bundled` 插件源没有正确注册，内置插件也没有安装到用户 plugin cache。

## 关键发现

官方 bundled 插件源实际存在：

```text
resources\plugins\openai-bundled
```

但用户配置里最初只启用了 GitHub 相关插件，`openai-bundled` 没有作为可用 marketplace 正常进入当前用户配置。

同时 Codex 自动更新到了新版包。真实 WindowsApps 路径在另一个盘：

```text
E:\WindowsApps\OpenAI.Codex_26.527.3686.0_x64__2p2nqsd0c76g0\app\resources
```

直接运行 WindowsApps 里的 `codex.exe` 被系统拦截，普通复制也可能因为 `Encrypted` / `Application Protected` 属性失败。

这里最重要的区别是：

```text
插件源存在 != 插件已经安装
```

Computer Use 真正可用前，必须安装到类似 cache：

```text
%USERPROFILE%\.codex\plugins\cache\openai-bundled\computer-use\26.527.31326
```

helper 文件随后应该存在：

```text
node_modules\@oai\sky\bin\windows\codex-computer-use.exe
```

transport 相关代码在不同 Codex 版本里位置不完全一致，可能在 `scripts\computer-use-client.mjs` 或 `node_modules\@oai\sky\dist\...` 里。

## 最终可用状态

这台机器最后通过这些步骤修好：

1. 把 `resources\plugins\openai-bundled` 镜像到稳定用户目录
2. 把 `openai-bundled` 注册成本地 marketplace
3. 安装并启用：

```text
browser@openai-bundled
chrome@openai-bundled
computer-use@openai-bundled
latex@openai-bundled
```

4. 创建 resources 形状镜像：

```text
%USERPROFILE%\.codex\bundled-resources\plugins\openai-bundled
```

5. 避免在 marketplace source 里使用 `\\?\` 长路径前缀
6. 刷新运行中的 Codex 窗口，或直接重启 Codex

成功后日志里出现：

```text
computer-use native pipe startup ready
```

前端直接调用 `list-plugins` 时能看到 `openai-bundled`，并且 Browser、Chrome、Computer Use、LaTeX 都是 `installed: true`、`enabled: true`。

## UI 位置

这些插件没有出现在 Discover / All 的 `Built by OpenAI` 列表里，而是在：

```text
Plugins - Unlocked -> Manage
```

所以修复后“不在 Discover 里”本身不代表失败。
