param(
    [string]$BuildDir = "build_switch",
    [string]$OutputName = "Lorealis.nro",
    [string]$AppName = "Lorealis",
    [string]$Author = "ns-chat"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildDirPath = Join-Path $repoRoot $BuildDir
$elfPath = Join-Path $buildDirPath "Lorealis.elf"
$nroPath = Join-Path $buildDirPath $OutputName
$iconPath = Join-Path $repoRoot "res\img\demo_icon.jpg"
$stageDir = Join-Path $buildDirPath "romfs_stage"

if (-not (Test-Path $elfPath)) {
    throw "ELF not found: $elfPath`nPlease build Switch once first."
}

if (-not (Get-Command elf2nro -ErrorAction SilentlyContinue)) {
    throw "elf2nro not found in PATH. Please open a devkitPro shell first."
}

Write-Host "[romfs] Staging assets to $stageDir"
if (Test-Path $stageDir) {
    Remove-Item $stageDir -Recurse -Force
}

New-Item -ItemType Directory -Path $stageDir | Out-Null
Copy-Item (Join-Path $repoRoot "res\*") $stageDir -Recurse -Force

$modTarget = Join-Path $stageDir "mod"
New-Item -ItemType Directory -Path $modTarget | Out-Null
Copy-Item (Join-Path $repoRoot "mod\*") $modTarget -Recurse -Force

Get-ChildItem $stageDir -Recurse -Force -Filter ".gitignore" | Remove-Item -Force

Write-Host "[romfs] Packing $nroPath"
& elf2nro $elfPath $nroPath `
    --icon=$iconPath `
    --name=$AppName `
    --author=$Author `
    --romfsdir=$stageDir

if ($LASTEXITCODE -ne 0) {
    throw "elf2nro failed with exit code $LASTEXITCODE"
}

Write-Host "[romfs] Done: $nroPath"
