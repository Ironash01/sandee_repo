# Downloads the open-source SFX packs used by cue_source_map.csv.
# Writes only to a local cache outside the repo by default.
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\fetch_and_stage.ps1
#   powershell -ExecutionPolicy Bypass -File .\fetch_and_stage.ps1 -CacheDir "D:\sfx_cache"
#   powershell -ExecutionPolicy Bypass -File .\fetch_and_stage.ps1 -SkipFire

param(
    [string]$CacheDir = (Join-Path $env:TEMP 'sandee_sfx_libs'),
    [switch]$SkipFire
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

$packs = @(
    @{
        Id = 'OGA512'
        Url = 'https://opengameart.org/sites/default/files/The%20Essential%20Retro%20Video%20Game%20Sound%20Effects%20Collection%20%5B512%20sounds%5D.zip'
        Zip = 'subspace_512.zip'
        Dir = 'subspace_512'
    },
    @{
        Id = 'PHX8'
        Url = 'https://opengameart.org/sites/default/files/SFX-%20The%20Ultimate%202017%208%20bit%20Mini%20pack.zip'
        Zip = 'phoenix_mini.zip'
        Dir = 'phoenix_mini'
    },
    @{
        Id = 'LRSF8'
        Url = 'https://opengameart.org/sites/default/files/8-Bit%20Sound%20Library.zip'
        Zip = 'littlerobot_8bit.zip'
        Dir = 'littlerobot_8bit'
    },
    @{
        Id = 'LUNAR8'
        Url = 'https://opengameart.org/sites/default/files/Lunar%20Lander.zip'
        Zip = 'lunar_lander.zip'
        Dir = 'lunar_lander'
    },
    @{
        Id = 'LOOPS30'
        Url = 'https://opengameart.org/sites/default/files/sfx_loops.zip'
        Zip = 'loops30.zip'
        Dir = 'loops30'
    }
)

foreach ($pack in $packs) {
    $zipPath = Join-Path $CacheDir $pack.Zip
    $outDir = Join-Path $CacheDir $pack.Dir
    if (-not (Test-Path -LiteralPath $zipPath)) {
        Write-Host "Downloading $($pack.Id)..."
        Invoke-WebRequest -Uri $pack.Url -OutFile $zipPath
    } else {
        Write-Host "Using cached $($pack.Zip)"
    }
    if (Test-Path -LiteralPath $outDir) {
        Remove-Item -LiteralPath $outDir -Recurse -Force
    }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $outDir -Force
    Write-Host "  -> $outDir"
}

$singleFiles = @(
    @{
        Id = 'DUNGEON'
        Url = 'https://opengameart.org/sites/default/files/dungeon_ambient_1_0.ogg'
        File = 'dungeon_ambient_1.ogg'
    }
)
if (-not $SkipFire) {
    $singleFiles += @{
        Id = 'FIRE'
        Url = 'https://opengameart.org/sites/default/files/fire.wav'
        File = 'fire.wav'
    }
}

foreach ($item in $singleFiles) {
    $dest = Join-Path $CacheDir $item.File
    if (-not (Test-Path -LiteralPath $dest)) {
        Write-Host "Downloading $($item.Id)..."
        Invoke-WebRequest -Uri $item.Url -OutFile $dest
    } else {
        Write-Host "Using cached $($item.File)"
    }
    Write-Host "  -> $dest"
}

Write-Host ''
Write-Host "Cache ready: $CacheDir"
Write-Host 'Pack roots expected by cue_source_map.csv:'
Write-Host "  OGA512  -> $CacheDir\subspace_512\The Essential Retro Video Game Sound Effects Collection [512 sounds] By Juhani Junkala"
Write-Host "  PHX8    -> $CacheDir\phoenix_mini\SFX- The Ultimate 2017 8 bit sound Mini pack"
Write-Host "  LRSF8   -> $CacheDir\littlerobot_8bit\8-Bit Sound Library"
Write-Host "  LUNAR8  -> $CacheDir\lunar_lander"
Write-Host "  LOOPS30 -> $CacheDir\loops30"
Write-Host "  DUNGEON -> $CacheDir\dungeon_ambient_1.ogg"
Write-Host "  FIRE    -> $CacheDir\fire.wav"
