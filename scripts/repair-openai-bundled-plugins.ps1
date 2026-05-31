#requires -Version 5.1
[CmdletBinding()]
param(
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex"),
  [string]$CodexInstallRoot,
  [string[]]$Plugins = @("browser", "computer-use", "chrome")
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

  $windowsAppsRoots = @(
    (Join-Path $env:ProgramFiles "WindowsApps"),
    "C:\WindowsApps",
    "D:\WindowsApps",
    "E:\WindowsApps",
    "F:\WindowsApps"
  ) | Select-Object -Unique

  foreach ($root in $windowsAppsRoots) {
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

  $bundled = Join-Path $ResourcesRoot "codex.exe"
  if (Test-Path -LiteralPath $bundled) {
    return $bundled
  }

  $fromPath = Get-Command "codex" -ErrorAction SilentlyContinue
  if ($fromPath) {
    return $fromPath.Source
  }

  throw "Could not find codex.exe."
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

Write-Step "Registering marketplace"
Invoke-Codex -CodexCli $codexCli -Arguments @("plugin", "marketplace", "remove", "openai-bundled") -AllowFailure
Invoke-Codex -CodexCli $codexCli -Arguments @("plugin", "marketplace", "add", $mirror)

Write-Step "Installing bundled plugins"
foreach ($plugin in $Plugins) {
  Invoke-Codex -CodexCli $codexCli -Arguments @("plugin", "add", "$plugin@openai-bundled")
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

Write-Host ""
Write-Host "Done. Restart Codex Desktop or refresh its window if the settings page still shows unavailable."
