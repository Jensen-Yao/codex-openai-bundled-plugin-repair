#requires -Version 5.1
[CmdletBinding()]
param(
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex"),
  [string]$CodexInstallRoot,
  [string[]]$Plugins = @("browser", "computer-use", "chrome", "latex"),
  [switch]$SetUserResourcesEnvironmentVariable
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "==> $Message"
}

function Resolve-CodexResourcesRoot {
  param([string]$InstallRoot)

  $candidates = New-Object System.Collections.Generic.List[string]

  if ($InstallRoot) {
    $full = [IO.Path]::GetFullPath($InstallRoot)
    if (Test-Path -LiteralPath (Join-Path $full "plugins\openai-bundled\.agents\plugins\marketplace.json")) {
      $candidates.Add($full)
    }
    if (Test-Path -LiteralPath (Join-Path $full "app\resources\plugins\openai-bundled\.agents\plugins\marketplace.json")) {
      $candidates.Add((Join-Path $full "app\resources"))
    }
  }

  $windowsAppsRoots = New-Object System.Collections.Generic.List[string]
  if ($env:ProgramFiles) {
    $windowsAppsRoots.Add((Join-Path $env:ProgramFiles "WindowsApps"))
  }
  Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    $windowsAppsRoots.Add((Join-Path $_.Root "WindowsApps"))
  }

  foreach ($root in ($windowsAppsRoots | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root -Directory -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      ForEach-Object {
        $resources = Join-Path $_.FullName "app\resources"
        if (Test-Path -LiteralPath (Join-Path $resources "plugins\openai-bundled\.agents\plugins\marketplace.json")) {
          $candidates.Add($resources)
        }
      }
  }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath (Join-Path $candidate "codex.exe")) {
      return [IO.Path]::GetFullPath($candidate)
    }
  }

  throw "Could not locate Codex resources root. Pass -CodexInstallRoot manually."
}

function Resolve-CodexCli {
  param([string]$ResourcesRoot)

  $candidates = New-Object System.Collections.Generic.List[string]

  $fromPath = Get-Command "codex" -ErrorAction SilentlyContinue
  if ($fromPath) {
    $candidates.Add($fromPath.Source)
  }

  $bundled = Join-Path $ResourcesRoot "codex.exe"
  if (Test-Path -LiteralPath $bundled) {
    $candidates.Add($bundled)
  }

  foreach ($candidate in ($candidates | Select-Object -Unique)) {
    try {
      & $candidate "--version" *> $null
      if ($LASTEXITCODE -eq 0) {
        return $candidate
      }
      Write-Host "Skipping unusable Codex CLI: $candidate"
    } catch {
      Write-Host "Skipping blocked Codex CLI: $candidate"
    }
  }

  throw "Could not find a runnable codex CLI. If WindowsApps blocks direct execution, copy the CLI to a user-owned directory or put codex on PATH."
}

function Copy-DirectoryByBytes {
  param(
    [string]$Source,
    [string]$Destination
  )

  $sourceRoot = (Resolve-Path -LiteralPath $Source).Path.TrimEnd("\")
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $destinationRoot = (Resolve-Path -LiteralPath $Destination).Path.TrimEnd("\")

  Get-ChildItem -LiteralPath $sourceRoot -Recurse -Force -Directory | ForEach-Object {
    $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart("\")
    New-Item -ItemType Directory -Force -Path (Join-Path $destinationRoot $relative) | Out-Null
  }

  $count = 0
  Get-ChildItem -LiteralPath $sourceRoot -Recurse -Force -File | ForEach-Object {
    $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart("\")
    $target = Join-Path $destinationRoot $relative
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent)) {
      New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [IO.File]::WriteAllBytes($target, [IO.File]::ReadAllBytes($_.FullName))
    (Get-Item -LiteralPath $target).LastWriteTimeUtc = $_.LastWriteTimeUtc
    $count += 1
  }

  return $count
}

function Invoke-Codex {
  param(
    [string]$CodexCli,
    [string[]]$Arguments,
    [switch]$AllowFailure
  )

  Write-Host "codex $($Arguments -join ' ')"
  & $CodexCli @Arguments
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0 -and -not $AllowFailure) {
    throw "codex command failed with exit code ${exitCode}: $($Arguments -join ' ')"
  }
}

function Get-CodexPluginListText {
  param([string]$CodexCli)

  $output = & $CodexCli plugin list
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "codex plugin list failed with exit code ${exitCode}"
  }
  return ($output -join "`n")
}

function Test-PluginInstalledEnabled {
  param(
    [string]$PluginListText,
    [string]$PluginId
  )

  $pattern = [regex]::Escape($PluginId) + ".*installed, enabled"
  return $PluginListText -match $pattern
}

function Ensure-PluginEnabledConfig {
  param(
    [string]$ConfigPath,
    [string]$PluginId
  )

  $section = '[plugins."{0}"]' -f $PluginId
  if (-not (Test-Path -LiteralPath $ConfigPath)) {
    [IO.File]::WriteAllLines($ConfigPath, @($section, "enabled = true", ""), [Text.UTF8Encoding]::new($false))
    return
  }

  $lines = [System.Collections.Generic.List[string]]::new()
  $inSection = $false
  $seenSection = $false
  $seenEnabled = $false

  foreach ($line in [IO.File]::ReadAllLines($ConfigPath)) {
    if ($line -eq $section) {
      $inSection = $true
      $seenSection = $true
      $seenEnabled = $false
      $lines.Add($line)
      continue
    }

    if ($inSection -and $line -match '^\s*\[.+\]\s*$') {
      if (-not $seenEnabled) {
        $lines.Add("enabled = true")
      }
      $inSection = $false
    }

    if ($inSection -and $line -match '^\s*enabled\s*=') {
      $lines.Add("enabled = true")
      $seenEnabled = $true
      continue
    }

    $lines.Add($line)
  }

  if ($inSection -and -not $seenEnabled) {
    $lines.Add("enabled = true")
  }

  if (-not $seenSection) {
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne "") {
      $lines.Add("")
    }
    $lines.Add($section)
    $lines.Add("enabled = true")
  }

  [IO.File]::WriteAllLines($ConfigPath, $lines, [Text.UTF8Encoding]::new($false))
}

function Normalize-OpenAiBundledMarketplacePath {
  param(
    [string]$ConfigPath,
    [string]$Mirror
  )

  if (-not (Test-Path -LiteralPath $ConfigPath)) { return $false }

  $normalMirror = [IO.Path]::GetFullPath($Mirror).TrimEnd("\")
  $longMirror = "\\?\" + $normalMirror
  $text = Get-Content -Raw -LiteralPath $ConfigPath
  $updated = $text.Replace($longMirror, $normalMirror)

  if ($updated -ne $text) {
    [IO.File]::WriteAllText($ConfigPath, $updated, [Text.UTF8Encoding]::new($false))
    return $true
  }

  return $false
}

function Remove-StaleBrowserUseConfig {
  param([string]$ConfigPath)

  if (-not (Test-Path -LiteralPath $ConfigPath)) { return $false }

  $lines = [System.Collections.Generic.List[string]]::new()
  $skip = $false
  $changed = $false

  foreach ($line in [IO.File]::ReadAllLines($ConfigPath)) {
    if ($line -eq '[plugins."browser-use@openai-bundled"]') {
      $skip = $true
      $changed = $true
      continue
    }
    if ($skip -and $line -match '^\s*\[.+\]\s*$') {
      $skip = $false
    }
    if (-not $skip) {
      $lines.Add($line)
    }
  }

  if ($changed) {
    [IO.File]::WriteAllLines($ConfigPath, $lines, [Text.UTF8Encoding]::new($false))
  }

  return $changed
}

New-Item -ItemType Directory -Force -Path $CodexHome | Out-Null

$configPath = Join-Path $CodexHome "config.toml"
if (Test-Path -LiteralPath $configPath) {
  $backupPath = Join-Path $CodexHome ("config.toml.bak-openai-bundled-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
  Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
  Write-Step "Backed up config.toml"
  Write-Host $backupPath
}

Write-Step "Locating Codex bundled plugins"
$resourcesRoot = Resolve-CodexResourcesRoot -InstallRoot $CodexInstallRoot
$codexCli = Resolve-CodexCli -ResourcesRoot $resourcesRoot
$sourceMarketplace = Join-Path $resourcesRoot "plugins\openai-bundled"
Write-Host "Resources: $resourcesRoot"
Write-Host "Codex CLI: $codexCli"
Write-Host "Source marketplace: $sourceMarketplace"

Write-Step "Mirroring openai-bundled marketplace into Codex home"
$mirror = Join-Path $CodexHome "bundled-marketplaces\openai-bundled"
$copied = Copy-DirectoryByBytes -Source $sourceMarketplace -Destination $mirror
Write-Host "Mirror: $mirror"
Write-Host "Files copied: $copied"

Write-Step "Mirroring resources-shaped bundled plugin source"
$resourcesMirrorRoot = Join-Path $CodexHome "bundled-resources"
$resourcesMirror = Join-Path $resourcesMirrorRoot "plugins\openai-bundled"
$resourcesCopied = Copy-DirectoryByBytes -Source $sourceMarketplace -Destination $resourcesMirror
Write-Host "Resources mirror: $resourcesMirror"
Write-Host "Files copied: $resourcesCopied"

Write-Step "Registering marketplace"
Invoke-Codex -CodexCli $codexCli -Arguments @("plugin", "marketplace", "remove", "openai-bundled") -AllowFailure
Invoke-Codex -CodexCli $codexCli -Arguments @("plugin", "marketplace", "add", $mirror)
if (Normalize-OpenAiBundledMarketplacePath -ConfigPath $configPath -Mirror $mirror) {
  Write-Host "Normalized openai-bundled marketplace path in config.toml."
}

Write-Step "Installing bundled plugins"
$pluginListText = Get-CodexPluginListText -CodexCli $codexCli
foreach ($plugin in $Plugins) {
  $pluginId = "$plugin@openai-bundled"
  if (Test-PluginInstalledEnabled -PluginListText $pluginListText -PluginId $pluginId) {
    Write-Host "Already installed and enabled: $pluginId"
    Ensure-PluginEnabledConfig -ConfigPath $configPath -PluginId $pluginId
    continue
  }

  Invoke-Codex -CodexCli $codexCli -Arguments @("plugin", "add", $pluginId)
  Ensure-PluginEnabledConfig -ConfigPath $configPath -PluginId $pluginId
  $pluginListText = Get-CodexPluginListText -CodexCli $codexCli
}

Write-Step "Cleaning stale plugin key"
if (Remove-StaleBrowserUseConfig -ConfigPath $configPath) {
  Write-Host 'Removed stale [plugins."browser-use@openai-bundled"] entry.'
} else {
  Write-Host "No stale browser-use entry found."
}

Write-Step "Current plugin status"
Invoke-Codex -CodexCli $codexCli -Arguments @("plugin", "marketplace", "list")
Invoke-Codex -CodexCli $codexCli -Arguments @("plugin", "list")

Write-Step "Persistent resources path"
Write-Host "Resources root: $resourcesMirrorRoot"
Write-Host "Optional user environment variable:"
Write-Host ('[Environment]::SetEnvironmentVariable("CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH", "{0}", "User")' -f $resourcesMirrorRoot)
if ($SetUserResourcesEnvironmentVariable) {
  [Environment]::SetEnvironmentVariable("CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH", $resourcesMirrorRoot, "User")
  Write-Host "Set CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH for future user sessions."
}

Write-Host ""
Write-Host "Done. Restart Codex Desktop or refresh its window if the settings page still shows unavailable."
