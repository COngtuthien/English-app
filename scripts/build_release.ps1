<#
.SYNOPSIS
  Full release pipeline for IELTS Vocabulary Master (Windows / PowerShell 5.1+).

  1. Check environment      2. Validate installed tools   3. Resolve dependencies
  4. Validate vocabulary    5. Static analysis            6. Automated tests
  7. Build release APK      8. Verify APK structure/signing
  9. Copy APK to release/   10. Generate checksums + build info

.PARAMETER SkipTests   Skip flutter analyze/test (not recommended).
.PARAMETER Aab         Also build an Android App Bundle.
#>
param([switch]$SkipTests, [switch]$Aab)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Release = Join-Path $Root 'release'
New-Item -ItemType Directory -Force $Release | Out-Null
$Log = Join-Path $Release 'build_log.txt'
"Build started $(Get-Date -Format o)" | Out-File -Encoding utf8 $Log

function Step($n, $msg) { Write-Host "`n[$n/10] $msg" -ForegroundColor Cyan; "[$n/10] $msg" | Out-File -Append -Encoding utf8 $Log }
function Run($exe, [string[]]$argList) {
  # Native tools write progress/warnings to stderr; judge success by exit code only.
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & $exe @argList 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $Log -Append | Out-Host
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  if ($code -ne 0) { throw "$exe $($argList -join ' ') failed with exit code $code" }
}
function Find-Tool($name, [string[]]$candidates) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  throw "$name not found. Run scripts/setup_environment.ps1 first."
}

Step 1 'Checking environment'
$Flutter = Find-Tool 'flutter' @('C:\flutter\bin\flutter.bat', "$env:USERPROFILE\flutter\bin\flutter.bat")
$Sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { "$env:LOCALAPPDATA\Android\Sdk" }
if (-not (Test-Path $Sdk)) { throw "Android SDK not found at $Sdk" }
$BuildTools = Get-ChildItem "$Sdk\build-tools" -Directory | Where-Object { $_.Name -notmatch 'rc' } | Sort-Object Name -Descending | Select-Object -First 1
$Aapt = Join-Path $BuildTools.FullName 'aapt.exe'
$ApkSigner = Join-Path $BuildTools.FullName 'apksigner.bat'
$Python = Find-Tool 'python' @()
"Flutter: $Flutter`nAndroid SDK: $Sdk`nBuild tools: $($BuildTools.Name)" | Tee-Object -FilePath $Log -Append | Out-Host

Step 2 'Validating tools'
Run $Flutter @('--version')
$jdkLine = (& $Flutter config --list 2>$null | Select-String 'jdk-dir')
"JDK config: $jdkLine" | Tee-Object -FilePath $Log -Append | Out-Host
if (-not (Test-Path 'android\key.properties')) {
  Write-Warning 'android/key.properties not found - the APK will be signed with the DEBUG key. Run scripts/setup_environment.ps1 to create a release key.'
}

Step 3 'Resolving dependencies'
Run $Flutter @('pub', 'get')

Step 4 'Validating vocabulary database'
New-Item -ItemType Directory -Force 'tools\data\out' | Out-Null
Run $Python @('-I', 'tools/data/validate_database.py', 'assets/db/vocab.db', 'tools/data/out/validation.json')

if (-not $SkipTests) {
  Step 5 'Static analysis'
  Run $Flutter @('analyze')
  Step 6 'Automated tests'
  & $Flutter test --reporter expanded 2>&1 | Tee-Object -FilePath (Join-Path $Release 'test_output.txt') | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }
} else {
  Step 5 'Static analysis (skipped)'; Step 6 'Automated tests (skipped)'
}

Step 7 'Building release APK'
Run $Flutter @('build', 'apk', '--release')
if ($Aab) { Run $Flutter @('build', 'appbundle', '--release') }

Step 8 'Verifying APK'
$Apk = 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $Apk)) { throw "APK not found at $Apk" }
if ((Get-Item $Apk).Length -lt 1MB) { throw 'APK is suspiciously small' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $Apk))
$names = $zip.Entries | ForEach-Object FullName
$zip.Dispose()
foreach ($required in @('AndroidManifest.xml', 'classes.dex', 'assets/flutter_assets/assets/db/vocab.db', 'lib/arm64-v8a/libapp.so')) {
  if ($names -notcontains $required) { throw "APK is missing $required" }
}
$ErrorActionPreference = 'Continue'
& $Aapt dump badging $Apk 2>&1 | ForEach-Object { "$_" } | Select-String "package:|sdkVersion|targetSdkVersion|uses-permission|application-label:|native-code" | Tee-Object -FilePath $Log -Append | Out-Host
$perms = (& $Aapt dump permissions $Apk 2>&1 | ForEach-Object { "$_" }) -join "`n"
if ($perms -match 'android.permission.INTERNET') { throw 'Release APK unexpectedly requests INTERNET permission' }
$jdkDir = ((& $Flutter config --list 2>$null | Select-String 'jdk-dir: (.+)').Matches | Select-Object -First 1).Groups[1].Value.Trim()
if ($jdkDir -and (Test-Path $jdkDir)) { $env:JAVA_HOME = $jdkDir; $env:Path = "$jdkDir\bin;$env:Path" }
& $ApkSigner verify --verbose --print-certs $Apk 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -notmatch '^WARNING: (A restricted|java.lang.System|Use --enable-native|Restricted methods)' } | Tee-Object -FilePath $Log -Append | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'apksigner verification failed' }
$ErrorActionPreference = 'Stop'

Step 9 'Copying artifacts to release/'
Copy-Item $Apk (Join-Path $Release 'IELTS_Vocabulary_Master.apk') -Force
if ($Aab -and (Test-Path 'build\app\outputs\bundle\release\app-release.aab')) {
  Copy-Item 'build\app\outputs\bundle\release\app-release.aab' (Join-Path $Release 'IELTS_Vocabulary_Master.aab') -Force
}

Step 10 'Generating checksums'
$lines = Get-ChildItem $Release -File | Where-Object { $_.Extension -in '.apk', '.aab' } | ForEach-Object {
  "{0}  {1}  ({2:N0} bytes)" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name, $_.Length
}
$lines | Out-File -Encoding utf8 (Join-Path $Release 'SHA256.txt')
$lines | Out-Host
"Build finished $(Get-Date -Format o)" | Out-File -Append -Encoding utf8 $Log
Write-Host "`nDone. APK: $Release\IELTS_Vocabulary_Master.apk" -ForegroundColor Green
