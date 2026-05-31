# 回滚方式

修复脚本每次运行都会备份：

```text
%USERPROFILE%\.codex\config.toml
```

备份文件格式类似：

```text
config.toml.bak-openai-bundled-20260531-152828
```

## 恢复配置

关闭 Codex Desktop 后执行：

```powershell
$codexHome = Join-Path $env:USERPROFILE ".codex"
$backup = Get-ChildItem $codexHome -Filter "config.toml.bak-openai-bundled-*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

Copy-Item $backup.FullName (Join-Path $codexHome "config.toml") -Force
```

然后重启 Codex Desktop。

## 删除镜像目录

如果要完全清理本仓库创建的镜像：

```powershell
Remove-Item "$env:USERPROFILE\.codex\bundled-marketplaces\openai-bundled" -Recurse -Force
```

如果之后要继续使用内置插件，不建议删除这个目录。
