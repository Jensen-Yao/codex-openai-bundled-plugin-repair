#requires -Version 5.1
[CmdletBinding()]
param(
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex"),
  [string[]]$Plugins = @("browser", "computer-use", "chrome", "latex")
)

$ErrorActionPreference = "Stop"

function Resolve-CodexCli {
  $candidates = New-Object System.Collections.Generic.List[string]

  $fromPath = Get-Command "codex" -ErrorAction SilentlyContinue
  if ($fromPath) { $candidates.Add($fromPath.Source) }

  $roots = New-Object System.Collections.Generic.List[string]
  if ($env:ProgramFiles) {
    $roots.Add((Join-Path $env:ProgramFiles "WindowsApps"))
  }
  Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    $roots.Add((Join-Path $_.Root "WindowsApps"))
  }

  foreach ($root in ($roots | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root -Directory -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      ForEach-Object { Join-Path $_.FullName "app\resources\codex.exe" } |
      Where-Object { Test-Path -LiteralPath $_ } |
      ForEach-Object { $candidates.Add($_) }
  }

  foreach ($candidate in ($candidates | Select-Object -Unique)) {
    try {
      & $candidate "--version" *> $null
      if ($LASTEXITCODE -eq 0) {
        return $candidate
      }
    } catch {
      continue
    }
  }

  throw "Could not find a runnable codex CLI."
}

$codexCli = Resolve-CodexCli
$configPath = Join-Path $CodexHome "config.toml"
$mirror = Join-Path $CodexHome "bundled-marketplaces\openai-bundled"
$resourcesMirror = Join-Path $CodexHome "bundled-resources\plugins\openai-bundled"

Write-Host "Codex CLI: $codexCli"
Write-Host "Expected marketplace mirror: $mirror"
Write-Host "Expected resources mirror: $resourcesMirror"
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

if (Test-Path -LiteralPath (Join-Path $resourcesMirror ".agents\plugins\marketplace.json")) {
  Write-Host "OK: resources-shaped bundled mirror exists."
} else {
  Write-Host "FAIL: resources-shaped bundled mirror is missing."
  $failed = $true
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

  $openAiBundledMarketplaceBlock = [regex]::Match($configText, '(?ms)^\[marketplaces\.openai-bundled\]\s*(.*?)(?=^\[|\z)')
  if ($openAiBundledMarketplaceBlock.Success -and $openAiBundledMarketplaceBlock.Value.Contains("\\?\")) {
    Write-Host 'WARN: [marketplaces.openai-bundled] contains a \\?\ long path. Prefer a normal C:\... path if the UI behaves differently from the CLI.'
  }
}

if ($Plugins -contains "computer-use") {
  $computerUseCache = Join-Path $CodexHome "plugins\cache\openai-bundled\computer-use"
  $computerUseVersion = $null
  if (Test-Path -LiteralPath $computerUseCache) {
    $computerUseVersion = Get-ChildItem -LiteralPath $computerUseCache -Directory |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
  }

  if ($computerUseVersion) {
    $helper = Join-Path $computerUseVersion.FullName "node_modules\@oai\sky\bin\windows\codex-computer-use.exe"

    if (Test-Path -LiteralPath $helper) {
      Write-Host "OK: Computer Use helper exists."
    } else {
      Write-Host "FAIL: Computer Use helper is missing: $helper"
      $failed = $true
    }

    $transport = Get-ChildItem -LiteralPath $computerUseVersion.FullName -Recurse -Force -File -Filter "*transport*.js" -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($transport) {
      Write-Host "OK: Computer Use transport implementation exists."
    } else {
      Write-Host "WARN: Computer Use transport implementation was not found by filename scan. This can be normal if the version bundles transport code differently."
    }
  } else {
    Write-Host "FAIL: computer-use plugin cache is missing."
    $failed = $true
  }
}

Write-Host ""
if ($failed) {
  Write-Host "Verification failed."
  exit 1
}

Write-Host "Verification passed."
Write-Host "If Codex Desktop is already open, restart it or refresh the window so it reloads the plugin list."
