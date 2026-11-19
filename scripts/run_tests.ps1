<#
.SYNOPSIS  Runs formatting check, static analysis, unit/database/widget tests and (optionally) the
           on-device integration test.
.PARAMETER Device  Device id for integration tests (e.g. emulator-5554). Omit to skip them.
#>
param([string]$Device)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = 'C:\flutter\bin\flutter.bat' }
$dart = Join-Path (Split-Path $flutter) 'cache\dart-sdk\bin\dart.exe'

& $flutter pub get; if ($LASTEXITCODE) { exit 1 }
& $dart format --line-length 140 --output none --set-exit-if-changed lib test integration_test
if ($LASTEXITCODE) { Write-Warning 'Formatting differs - run: dart format --line-length 140 lib test integration_test' }
& $flutter analyze; if ($LASTEXITCODE) { exit 1 }
& $flutter test --reporter expanded; if ($LASTEXITCODE) { exit 1 }
if ($Device) {
  & $flutter test integration_test/app_test.dart -d $Device; if ($LASTEXITCODE) { exit 1 }
}
Write-Host 'All test stages passed.' -ForegroundColor Green
