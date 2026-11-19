<#
.SYNOPSIS
  Detects and prepares the development environment for IELTS Vocabulary Master (Windows).
  Everything is installed user-scoped (no administrator rights needed):
    * Flutter SDK (stable)          -> %USERPROFILE%\flutter          (only if flutter is missing)
    * Eclipse Temurin JDK 21        -> %LOCALAPPDATA%\Programs\temurin (only if no JDK 17-21 is found)
    * Android SDK command-line tools -> %LOCALAPPDATA%\Android\Sdk     (only if the SDK is missing)
    * Release signing key           -> android\keystore\ + android\key.properties (git-ignored)
  Downloads come only from official sources (storage.googleapis.com/flutter_infra, dl.google.com,
  api.adoptium.net) and the Temurin archive is verified against Adoptium's published SHA-256.

.PARAMETER AcceptLicenses  Run `flutter doctor --android-licenses` (you will be asked to accept each licence).
#>
param([switch]$AcceptLicenses)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Info($m) { Write-Host "  $m" }
Write-Host "== System" -ForegroundColor Cyan
Info "OS: $((Get-CimInstance Win32_OperatingSystem).Caption)  PowerShell $($PSVersionTable.PSVersion)"
$drive = (Get-Item $Root).PSDrive
Info ("Free space on {0}: {1:N1} GB" -f $drive.Name, ($drive.Free / 1GB))
Info ("RAM: {0:N1} GB, CPUs: {1}" -f ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB), (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors)

# ---------------------------------------------------------------- Flutter
Write-Host "== Flutter" -ForegroundColor Cyan
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter -and (Test-Path 'C:\flutter\bin\flutter.bat')) { $flutter = 'C:\flutter\bin\flutter.bat' }
if (-not $flutter) {
  $releases = Invoke-RestMethod 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
  $stable = $releases.releases | Where-Object { $_.hash -eq $releases.current_release.stable } | Select-Object -First 1
  $zip = "$env:TEMP\flutter_stable.zip"
  Info "Downloading Flutter $($stable.version)…"
  Invoke-WebRequest "$($releases.base_url)/$($stable.archive)" -OutFile $zip
  if ((Get-FileHash $zip -Algorithm SHA256).Hash.ToLower() -ne $stable.sha256) { throw 'Flutter archive checksum mismatch' }
  Expand-Archive $zip -DestinationPath $env:USERPROFILE -Force
  $flutter = "$env:USERPROFILE\flutter\bin\flutter.bat"
  Info "Installed Flutter to $env:USERPROFILE\flutter (add $env:USERPROFILE\flutter\bin to PATH)"
}
Info "flutter: $flutter"
& $flutter --version

# ---------------------------------------------------------------- JDK
Write-Host "== Java (JDK 17-21 required by Gradle 8.x)" -ForegroundColor Cyan
function Get-JavaMajor($javaExe) {
  try { $v = (& $javaExe -version 2>&1 | Select-Object -First 1) -replace '.*version "([0-9]+).*', '$1'; return [int]$v } catch { return 0 }
}
$jdk = $null
$candidates = @("$env:LOCALAPPDATA\Programs\temurin", "$env:ProgramFiles\Android\Android Studio\jbr", "$env:ProgramFiles\Eclipse Adoptium", "$env:ProgramFiles\Java")
foreach ($c in $candidates) {
  if (-not (Test-Path $c)) { continue }
  foreach ($j in @($c) + (Get-ChildItem $c -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)) {
    $exe = Join-Path $j 'bin\java.exe'
    if ((Test-Path $exe) -and ((Get-JavaMajor $exe) -in 17..21)) { $jdk = $j; break }
  }
  if ($jdk) { break }
}
if (-not $jdk) {
  $dest = "$env:LOCALAPPDATA\Programs\temurin"
  New-Item -ItemType Directory -Force $dest | Out-Null
  $meta = (Invoke-RestMethod 'https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse')[0]
  $zip = Join-Path $dest $meta.binary.package.name
  Info "Downloading $($meta.binary.package.name)…"
  Invoke-WebRequest $meta.binary.package.link -OutFile $zip
  if ((Get-FileHash $zip -Algorithm SHA256).Hash.ToLower() -ne $meta.binary.package.checksum) { throw 'JDK checksum mismatch' }
  Expand-Archive $zip -DestinationPath $dest -Force
  $jdk = (Get-ChildItem $dest -Directory | Where-Object Name -like 'jdk-21*' | Select-Object -First 1).FullName
}
Info "JDK: $jdk"
& $flutter config --jdk-dir="$jdk" | Out-Null

# ---------------------------------------------------------------- Android SDK
Write-Host "== Android SDK" -ForegroundColor Cyan
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
if (-not (Test-Path "$sdk\cmdline-tools\latest\bin\sdkmanager.bat")) {
  New-Item -ItemType Directory -Force "$sdk\cmdline-tools" | Out-Null
  $zip = "$env:TEMP\cmdline-tools.zip"
  Info 'Downloading Android command-line tools…'
  Invoke-WebRequest 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip' -OutFile $zip
  Expand-Archive $zip -DestinationPath "$sdk\cmdline-tools\tmp" -Force
  Move-Item "$sdk\cmdline-tools\tmp\cmdline-tools" "$sdk\cmdline-tools\latest" -Force
  Remove-Item "$sdk\cmdline-tools\tmp" -Recurse -Force
}
$env:JAVA_HOME = $jdk
$sdkmanager = "$sdk\cmdline-tools\latest\bin\sdkmanager.bat"
& $sdkmanager --sdk_root=$sdk 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' | Out-Host
& $flutter config --android-sdk="$sdk" | Out-Null
Info "Android SDK: $sdk"
if ($AcceptLicenses) { & $flutter doctor --android-licenses }

# ---------------------------------------------------------------- signing key
Write-Host "== Release signing key" -ForegroundColor Cyan
$ks = 'android\keystore\ielts-release.jks'
if (-not (Test-Path $ks)) {
  New-Item -ItemType Directory -Force 'android\keystore' | Out-Null
  $bytes = New-Object byte[] 24
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $pw = [Convert]::ToBase64String($bytes) -replace '[+/=]', 'x'
  & "$jdk\bin\keytool.exe" -genkeypair -keystore $ks -storetype PKCS12 -alias ieltsvocab -keyalg RSA -keysize 4096 -validity 10000 `
    -storepass $pw -keypass $pw -dname 'CN=IELTS Vocabulary Master, OU=Personal, O=IELTS Vocabulary Master, C=VN' | Out-Null
  [IO.File]::WriteAllText((Join-Path $Root 'android\key.properties'), "storePassword=$pw`nkeyPassword=$pw`nkeyAlias=ieltsvocab`nstoreFile=../keystore/ielts-release.jks`n")
  Info 'Created android/keystore/ielts-release.jks and android/key.properties (both git-ignored).'
  Info 'BACK THEM UP: future updates of the app must be signed with the same key.'
} else { Info 'Release key already present.' }

Write-Host "== flutter doctor" -ForegroundColor Cyan
& $flutter doctor
