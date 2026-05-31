#requires -Version 5.1
[CmdletBinding()]
param(
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex"),
  [string[]]$Plugins = @("browser", "computer-use", "chrome")
)

$ErrorActionPreference = "Stop"

function Resolve-CodexCli {
  $fromPath = Get-Command "codex" -ErrorAction SilentlyContinue
  if ($fromPath) { return $fromPath.Source }

  $roots = @(
    (Join-Path $env:ProgramFiles "WindowsApps"),
    "C:\WindowsApps",
    "D:\WindowsApps",
    "E:\WindowsApps",
    "F:\WindowsApps"
  ) | Select-Object -Unique

  foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $candidate = Get-ChildItem -LiteralPath $root -Directory -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      ForEach-Object { Join-Path $_.FullName "app\resources\codex.exe" } |
      Where-Object { Test-Path -LiteralPath $_ } |
      Select-Object -First 1
    if ($candidate) { return $candidate }
  }

  throw "Could not find codex.exe."
}

$codexCli = Resolve-CodexCli
$configPath = Join-Path $CodexHome "config.toml"
$mirror = Join-Path $CodexHome "bundled-marketplaces\openai-bundled"

Write-Host "Codex CLI: $codexCli"
Write-Host "Expected marketplace mirror: $mirror"
Write-Host ""

$marketplaces = & $codexCli plugin marketplace list
$marketplacesText = $marketplaces -join "`n"
$pluginsOutput = & $codexCli plugin list

$failed = $false

if (-not $marketplacesText.Contains("bundled-marketplaces\openai-bundled")) {
  Write-Host "FAIL: openai-bundled marketplace does not point to the expected mirror."
  $failed = $true
} else {
  Write-Host "OK: openai-bundled marketplace points to the expected mirror."
}

foreach ($plugin in $Plugins) {
  $id = "$plugin@openai-bundled"
  $line = $pluginsOutput | Where-Object { $_ -match [regex]::Escape($id) } | Select-Object -First 1
  if ($line -and $line -match "installed, enabled") {
    Write-Host "OK: $id is installed and enabled."
  } else {
    Write-Host "FAIL: $id is not installed and enabled."
    $failed = $true
  }
}

if (Test-Path -LiteralPath $configPath) {
  $configText = Get-Content -Raw -LiteralPath $configPath
  if ($configText -match '\[plugins\."browser-use@openai-bundled"\]') {
    Write-Host 'FAIL: stale [plugins."browser-use@openai-bundled"] entry still exists.'
    $failed = $true
  } else {
    Write-Host 'OK: stale [plugins."browser-use@openai-bundled"] entry is absent.'
  }
}

Write-Host ""
if ($failed) {
  Write-Host "Verification failed."
  exit 1
}

Write-Host "Verification passed."
