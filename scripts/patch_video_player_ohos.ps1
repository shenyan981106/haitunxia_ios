# Fix video_player_ohos compilation error on HarmonyOS SDK 5.1.0(18)
# This script copies the fixed VideoPlayer.ets to PubCache
# Usage: Run this script before flutter build hap
#   Windows (PowerShell): .\scripts\patch_video_player_ohos.ps1
#   macOS/Linux: ./scripts/patch_video_player_ohos.sh

param(
    [string]$ProjectRoot
)

# If ProjectRoot not specified, use grandparent of script directory
# (script is in scripts/, project root is parent of scripts/)
if (-not $ProjectRoot) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent $scriptDir
}

Write-Host "Project root: $ProjectRoot"

# 1. Find Flutter PubCache path
# Check PUB_CACHE environment variable first
if ($env:PUB_CACHE) {
    $pubCachePath = $env:PUB_CACHE
} else {
    $pubCachePath = $env:LOCALAPPDATA + "\Pub\Cache"
}

# If the path still doesn't exist, warn the user
if (-not (Test-Path $pubCachePath)) {
    Write-Error "PubCache path not found: $pubCachePath"
    Write-Error "Set PUB_CACHE environment variable or verify Flutter installation."
    exit 1
}

Write-Host "PubCache path: $pubCachePath"

# 2. Find video_player_ohos in PubCache
$gitCachePath = Join-Path $pubCachePath "git"
if (-not (Test-Path $gitCachePath)) {
    Write-Host "Git cache directory not found. Git dependencies may not be used."
    exit 0
}

$targetRelativePath = "ohos\src\main\ets\components\videoplayer\VideoPlayer.ets"
$sourceFile = Join-Path $ProjectRoot "third_party\video_player_ohos\ohos\src\main\ets\components\videoplayer\VideoPlayer.ets"

if (-not (Test-Path $sourceFile)) {
    Write-Error "Source file not found: $sourceFile"
    Write-Error "Make sure the fixed video_player_ohos is in the third_party directory."
    exit 1
}

Write-Host "Source file: $sourceFile"
Write-Host ""

# Search git cache for video_player_ohos
# video_player_ohos is a sub-package inside flutter_packages repository
$foundPaths = @()
$dirs = Get-ChildItem -Path $gitCachePath -Directory
foreach ($dir in $dirs) {
    # Check if this is the flutter_packages repo containing video_player_ohos
    $ohosDir = Join-Path $dir.FullName "packages\video_player\video_player_ohos"
    if (Test-Path $ohosDir) {
        $pubspecPath = Join-Path $ohosDir "pubspec.yaml"
        if (Test-Path $pubspecPath) {
            $content = Get-Content $pubspecPath -Raw
            if ($content -match "name:\s*video_player_ohos") {
                $foundPaths += $ohosDir
                Write-Host "Found video_player_ohos: $ohosDir"
            }
        }
    }
}

if ($foundPaths.Count -eq 0) {
    Write-Host ""
    Write-Host "video_player_ohos not found in PubCache."
    Write-Host "Run 'flutter pub get' first to download dependencies."
    exit 0
}

# 3. Copy the fixed file
Write-Host ""
foreach ($targetDir in $foundPaths) {
    # targetDir is already the video_player_ohos directory
    $destFile = Join-Path $targetDir "ohos\src\main\ets\components\videoplayer\VideoPlayer.ets"
    Write-Host "Copying fix to: $destFile"
    Copy-Item -Path $sourceFile -Destination $destFile -Force
    
    if (Test-Path $destFile) {
        Write-Host "Fix applied: $destFile"
    } else {
        Write-Error "Copy failed: $destFile"
        exit 1
    }
}

Write-Host ""
Write-Host "All video_player_ohos instances have been patched."
Write-Host "You can now run flutter build hap."
