<#
.SYNOPSIS
  Publishes verified Android APKs as GitHub Releases for existing version tags.

.DESCRIPTION
  For every requested version this script:
    1. checks that the tag already exists on origin (tags are never created, moved or overwritten here);
    2. verifies the local APK: versionName/versionCode match the tag, the APK Signature Scheme v2
       certificate is the project's release certificate, no INTERNET permission;
    3. stages a copy as release/dist/<tag>/IELTS_Vocabulary_Master_<tag>.apk plus a .sha256 file
       (the original APKs in release/ are never modified);
    4. creates the GitHub Release with the CHANGELOG.md section as notes and uploads both files
       (an existing Release is left untouched except for uploading missing assets);
    5. downloads every published asset again and compares the SHA-256;
    6. optionally marks the newest version as "Latest" and rewrites the README download block.

  Requires the GitHub CLI (`gh`) authenticated with `gh auth login` (repo scope).
  Use -DryRun to run all local checks without touching GitHub.

.EXAMPLE
  scripts\publish_release.ps1 -All -DryRun        # verify the whole backlog locally
  scripts\publish_release.ps1 -All -UpdateReadme  # publish v1.0.0..v1.0.5, newest = Latest
  scripts\publish_release.ps1 -Tag v1.0.6 -Apk release\IELTS_Vocabulary_Master_v1.0.6.apk -Latest -UpdateReadme
#>
[CmdletBinding()]
param(
  [string]$Tag,
  [string]$Apk,
  [switch]$Latest,
  [switch]$All,
  [switch]$UpdateReadme,
  [switch]$DryRun,
  [string]$Repo = 'COngtuthien/English-app'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

# Release signing certificate of com.ieltsvocabulary.master (public fingerprint, not a secret).
$ExpectedCert = 'e7f0e58a4854d365fecf97fff7d82bfaee4739a0b8d6a6ac466e440ebccdc2b2'
$AssetPrefix = 'IELTS_Vocabulary_Master'

# APKs built before the naming convention was fixed.
$Backlog = [ordered]@{
  'v1.0.0' = 'release\IELTS_Vocabulary_Master.apk'
  'v1.0.1' = 'release\IELTS_Vocabulary_Master_flashcard_fix.apk'
  'v1.0.2' = 'release\IELTS_Vocabulary_Master_v1.0.2.apk'
  'v1.0.3' = 'release\IELTS_Vocabulary_Master_v1.0.3.apk'
  'v1.0.4' = 'release\IELTS_Vocabulary_Master_v1.0.4.apk'
  'v1.0.5' = 'release\IELTS_Vocabulary_Master_v1.0.5.apk'
}

function Fail([string]$msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
function Info([string]$msg) { Write-Host $msg -ForegroundColor Cyan }

function Find-Tool([string]$name, [string[]]$candidates) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  return $null
}

$Git = Find-Tool 'git' @("$env:LOCALAPPDATA\Programs\PortableGit\cmd\git.exe", "$env:ProgramFiles\Git\cmd\git.exe")
if (-not $Git) { Fail 'git not found' }
$BuildTools = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Directory -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
if (-not $BuildTools) { Fail 'Android build-tools not found (aapt/apksigner)' }
$Aapt = Join-Path $BuildTools.FullName 'aapt.exe'
$ApkSigner = Join-Path $BuildTools.FullName 'apksigner.bat'
if (-not $env:JAVA_HOME) {
  $jdk = Get-ChildItem "$env:LOCALAPPDATA\Programs\temurin" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($jdk) { $env:JAVA_HOME = $jdk.FullName; $env:Path = "$($jdk.FullName)\bin;$env:Path" }
}

$Gh = $null
if (-not $DryRun) {
  $Gh = Find-Tool 'gh' @("$env:ProgramFiles\GitHub CLI\gh.exe", "$env:LOCALAPPDATA\Programs\gh\bin\gh.exe")
  if (-not $Gh) { Fail 'GitHub CLI (gh) not found. Install it (winget install GitHub.cli) and run: gh auth login' }
  & $Gh auth status --hostname github.com *> $null
  if ($LASTEXITCODE -ne 0) { Fail 'gh is not authenticated. Run: gh auth login' }
}

function Get-ChangelogSection([string]$version) {
  $lines = Get-Content (Join-Path $Root 'CHANGELOG.md') -Encoding UTF8
  $out = New-Object System.Collections.Generic.List[string]
  $inside = $false
  foreach ($l in $lines) {
    if ($l -match '^## \[') {
      if ($inside) { break }
      if ($l.StartsWith("## [$version]")) { $inside = $true; continue }
    } elseif ($inside) {
      if ($l -match '^\[[0-9.]+\]: ') { break }
      $out.Add($l)
    }
  }
  if (-not $inside) { Fail "CHANGELOG.md has no section for [$version]" }
  return ($out -join "`n").Trim()
}

function Test-Apk([string]$tag, [string]$apkPath) {
  if (-not (Test-Path $apkPath)) { Fail "$tag : APK not found: $apkPath" }
  $version = $tag.TrimStart('v')
  $badging = & $Aapt dump badging $apkPath 2>$null | Select-Object -First 1
  $vn = [regex]::Match($badging, "versionName='([^']+)'").Groups[1].Value
  $vc = [regex]::Match($badging, "versionCode='([^']+)'").Groups[1].Value
  if ($vn -ne $version) { Fail "$tag : APK versionName is '$vn'" }
  $signer = (& $ApkSigner verify --print-certs $apkPath 2>&1 | Out-String)
  if ($signer -notmatch 'certificate SHA-256 digest: ([0-9a-f]+)') { Fail "$tag : apksigner verification failed`n$signer" }
  if ($Matches[1] -ne $ExpectedCert) { Fail "$tag : APK signed with an unexpected certificate $($Matches[1])" }
  $perms = & $Aapt dump permissions $apkPath 2>$null | Out-String
  if ($perms -match 'android.permission.INTERNET') { Fail "$tag : APK requests INTERNET permission" }
  $sha = (Get-FileHash $apkPath -Algorithm SHA256).Hash.ToLower()
  return [pscustomobject]@{ Tag = $tag; Version = $version; VersionCode = $vc; Path = $apkPath; Sha256 = $sha; Size = (Get-Item $apkPath).Length }
}

function Test-RemoteTag([string]$tag) {
  $ref = & $Git ls-remote --tags origin "refs/tags/$tag" 2>$null
  if (-not $ref) { Fail "$tag : tag does not exist on origin (create and push it first; this script never creates tags)" }
}

function Stage-Assets($info) {
  $dir = Join-Path $Root "release\dist\$($info.Tag)"
  New-Item -ItemType Directory -Force $dir | Out-Null
  $name = "${AssetPrefix}_$($info.Tag).apk"
  $dest = Join-Path $dir $name
  Copy-Item $info.Path $dest -Force
  if ((Get-FileHash $dest -Algorithm SHA256).Hash.ToLower() -ne $info.Sha256) { Fail "$($info.Tag) : staged copy hash mismatch" }
  $shaFile = "$dest.sha256"
  [IO.File]::WriteAllText($shaFile, "$($info.Sha256)  $name`n")
  return [pscustomobject]@{ Apk = $dest; Sha = $shaFile; Name = $name }
}

function Get-Notes($info, $assets) {
  $section = Get-ChangelogSection $info.Version
  $notes = @"
$section

---
### Download & verify
* Android APK: **$($assets.Name)** (versionCode $($info.VersionCode), $([math]::Round($info.Size / 1MB, 1)) MB)
* SHA-256: ``$($info.Sha256)``
* Signing certificate SHA-256: ``$ExpectedCert``

Install over any earlier version to keep your learning progress (same signing key).
Verify on Windows: ``Get-FileHash $($assets.Name) -Algorithm SHA256`` | macOS/Linux: ``shasum -a 256 $($assets.Name)``
"@
  $file = Join-Path (Split-Path $assets.Apk) 'RELEASE_NOTES.md'
  [IO.File]::WriteAllText($file, $notes)
  return $file
}

function Test-PublishedAsset([string]$url, [string]$expectedSha) {
  $tmp = Join-Path $env:TEMP ("asset_" + [guid]::NewGuid().ToString('N'))
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp -Headers @{ 'User-Agent' = 'release-verify' }
    $actual = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
    return ($actual -eq $expectedSha)
  } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}

function Publish($info, [bool]$markLatest) {
  Test-RemoteTag $info.Tag
  $assets = Stage-Assets $info
  $notes = Get-Notes $info $assets
  $title = "IELTS Vocabulary Master $($info.Version)"
  Info "$($info.Tag): verified $($info.Path) -> $($assets.Name) sha256=$($info.Sha256)"
  if ($DryRun) {
    Info "  [dry-run] gh release create $($info.Tag) --verify-tag --title `"$title`" --latest=$($markLatest.ToString().ToLower()) $($assets.Name) $($assets.Name).sha256"
    return
  }
  & $Gh release view $info.Tag --repo $Repo *> $null
  if ($LASTEXITCODE -eq 0) {
    Info "  Release $($info.Tag) already exists: uploading only missing assets (no overwrite)"
    $existing = (& $Gh release view $info.Tag --repo $Repo --json assets | ConvertFrom-Json).assets | ForEach-Object { $_.name }
    foreach ($f in @($assets.Apk, $assets.Sha)) {
      if ($existing -notcontains (Split-Path $f -Leaf)) {
        & $Gh release upload $info.Tag $f --repo $Repo
        if ($LASTEXITCODE -ne 0) { Fail "$($info.Tag): upload failed" }
      }
    }
    if ($markLatest) { & $Gh release edit $info.Tag --repo $Repo --latest; if ($LASTEXITCODE -ne 0) { Fail "$($info.Tag): could not mark as latest" } }
  } else {
    & $Gh release create $info.Tag $assets.Apk $assets.Sha --repo $Repo --verify-tag --title $title --notes-file $notes "--latest=$($markLatest.ToString().ToLower())"
    if ($LASTEXITCODE -ne 0) { Fail "$($info.Tag): gh release create failed" }
  }
  # verify what is actually published
  $rel = & $Gh release view $info.Tag --repo $Repo --json url,assets,isDraft,isPrerelease | ConvertFrom-Json
  if ($rel.isDraft) { Fail "$($info.Tag): release is a draft" }
  $apkAsset = $rel.assets | Where-Object { $_.name -eq $assets.Name }
  if (-not $apkAsset) { Fail "$($info.Tag): APK asset missing after upload" }
  if (-not (Test-PublishedAsset $apkAsset.url $info.Sha256)) { Fail "$($info.Tag): downloaded APK hash does not match" }
  Info "  Published and verified: $($rel.url)"
  Info "  APK: $($apkAsset.url)"
}

function Update-Readme($info) {
  $readme = Join-Path $Root 'README.md'
  $text = [IO.File]::ReadAllText($readme)
  $name = "${AssetPrefix}_$($info.Tag).apk"
  $apkUrl = "https://github.com/$Repo/releases/download/$($info.Tag)/$name"
  $block = @"
<!-- download:start -->
<p align="center">
  <a href="$apkUrl"><img src="https://img.shields.io/badge/Download%20Latest%20Android%20APK-v$($info.Version)-16A34A?style=for-the-badge&logo=android&logoColor=white" alt="Download Latest Android APK" /></a>
</p>

**[Download Latest Android APK ($($info.Tag), $([math]::Round($info.Size / 1MB, 1)) MB)]($apkUrl)**  |
[SHA-256]($apkUrl.sha256)  |
[Release notes](https://github.com/$Repo/releases/tag/$($info.Tag))  |
[All releases](https://github.com/$Repo/releases)
<!-- download:end -->
"@
  if ($DryRun) {
    Info "  [dry-run] README download block would point to $apkUrl (not written: the release is not published)"
    return
  }
  if ($text -match '(?s)<!-- download:start -->.*?<!-- download:end -->') {
    $text = [regex]::Replace($text, '(?s)<!-- download:start -->.*?<!-- download:end -->', [System.Text.RegularExpressions.MatchEvaluator] { param($m) $block })
  } else {
    Fail 'README.md has no <!-- download:start --> ... <!-- download:end --> block'
  }
  [IO.File]::WriteAllText($readme, $text)
  Info "README download block now points to $apkUrl"
  if (-not $DryRun) {
    foreach ($u in @($apkUrl, "$apkUrl.sha256", "https://github.com/$Repo/releases/tag/$($info.Tag)")) {
      $r = Invoke-WebRequest -UseBasicParsing -Uri $u -Method Head -Headers @{ 'User-Agent' = 'release-verify' }
      if ($r.StatusCode -ne 200) { Fail "link check failed ($($r.StatusCode)): $u" }
      Info "  link OK: $u"
    }
    $latest = Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'release-verify' }
    if ($latest.BaseResponse.ResponseUri.AbsoluteUri -notlike "*/releases/tag/$($info.Tag)") {
      Fail "releases/latest resolves to $($latest.BaseResponse.ResponseUri.AbsoluteUri), expected $($info.Tag)"
    }
    Info "  releases/latest -> $($info.Tag)"
  }
}

# ---------------------------------------------------------------- main
$jobs = New-Object System.Collections.Generic.List[object]
if ($All) {
  foreach ($k in $Backlog.Keys) { $jobs.Add(@($k, $Backlog[$k])) }
} elseif ($Tag) {
  if (-not $Apk) { $Apk = "release\${AssetPrefix}_$Tag.apk" }
  $jobs.Add(@($Tag, $Apk))
} else {
  Fail 'Specify -Tag <vX.Y.Z> [-Apk <path>] or -All'
}

# verify everything locally before publishing anything
$infos = @()
foreach ($j in $jobs) { $infos += Test-Apk $j[0] $j[1] }
Info "Local verification passed for: $(($infos | ForEach-Object { $_.Tag }) -join ', ')"

for ($i = 0; $i -lt $infos.Count; $i++) {
  $isNewest = ($i -eq $infos.Count - 1)
  Publish $infos[$i] ($isNewest -and ($All -or $Latest))
}
if ($UpdateReadme) { Update-Readme $infos[$infos.Count - 1] }
Info 'Done.'
