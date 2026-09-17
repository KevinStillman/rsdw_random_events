<#
.SYNOPSIS
    Downloads and installs UE4SS (the Lua modding loader) directly into the
    RuneScape: Dragonwilds game install.

.DESCRIPTION
    Unlike this repo's own mod (installed via a junction under ue4ss\Mods),
    UE4SS itself is a loader that has to live inside the game's own
    Binaries\Win64 folder (it proxies dwmapi.dll to hook the game on launch).
    This downloads the "experimental" build line - the reference DragonwildsHUD
    mod's README notes older/stable UE4SS builds crash this game on certain
    UMG calls, so experimental-latest is what's known to work - and extracts
    it into Binaries\Win64, preserving folder structure, matching the manual
    steps documented at https://blog.curseforge.com/how-to-mod-runescape-dragonwilds/.

    Requires the `gh` CLI, installed and authenticated (used to fetch the
    release asset without scraping GitHub's web UI).

.PARAMETER GamePath
    Path to the RSDragonwilds installation folder (the folder containing
    "Binaries\Win64"). If not provided, common Steam library locations are searched.

.NOTES
    This modifies files inside your Steam game install, outside this repo.
    It's reversible - delete Binaries\Win64\ue4ss and Binaries\Win64\dwmapi.dll
    to remove it - but review before running if that matters to you.

    After this completes, launch RSDragonwilds once, reach the main menu, and
    close it - that first run is what makes UE4SS create ue4ss\Mods and the
    rest of its folder structure. Confirm Binaries\Win64\ue4ss\Mods exists
    before running .\install.ps1 in this repo.

.EXAMPLE
    .\tools\Install-UE4SS.ps1

.EXAMPLE
    .\tools\Install-UE4SS.ps1 -GamePath "C:\Program Files (x86)\Steam\steamapps\common\RSDragonwilds\RSDragonwilds"
#>
param(
    [string]$GamePath
)

$ErrorActionPreference = "Stop"

function Find-GamePath {
    $candidates = [System.Collections.Generic.List[string]]::new()

    $steamRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam")) {
        $steamPath = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).SteamPath
        if ($steamPath) { $steamRoots.Add($steamPath) }
    }

    foreach ($steamRoot in $steamRoots) {
        $steamRoot = $steamRoot -replace '/', '\'
        $candidates.Add($steamRoot)

        $libraryFile = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
        if (Test-Path $libraryFile) {
            $matches = Select-String -Path $libraryFile -Pattern '"path"\s+"(.+?)"'
            foreach ($m in $matches) {
                $libPath = $m.Matches[0].Groups[1].Value -replace '\\\\', '\'
                $candidates.Add($libPath)
            }
        }
    }

    foreach ($root in $candidates) {
        $gamePath = Join-Path $root "steamapps\common\RSDragonwilds\RSDragonwilds"
        if (Test-Path $gamePath) {
            return $gamePath
        }
    }

    return $null
}

if (-not $GamePath) {
    $GamePath = Find-GamePath
}
if (-not $GamePath -or -not (Test-Path $GamePath)) {
    Write-Error "Could not locate the RSDragonwilds installation. Re-run with -GamePath pointing at your 'RSDragonwilds' folder."
    exit 1
}

$win64Dir = Join-Path $GamePath "Binaries\Win64"
if (-not (Test-Path $win64Dir)) {
    Write-Error "Expected folder not found: $win64Dir - is -GamePath correct?"
    exit 1
}

if (Test-Path (Join-Path $win64Dir "dwmapi.dll")) {
    Write-Host "UE4SS's dwmapi.dll proxy is already present at $win64Dir - remove it first if you want to reinstall."
    exit 0
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "This script requires the GitHub CLI ('gh'), installed and authenticated (gh auth login)."
    exit 1
}

$work = Join-Path $env:TEMP "ue4ss_install"
New-Item -ItemType Directory -Force -Path $work | Out-Null
Get-ChildItem $work -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

Write-Host "Fetching UE4SS experimental-latest release info ..."
$release = gh api repos/UE4SS-RE/RE-UE4SS/releases/tags/experimental-latest | ConvertFrom-Json
$asset = $release.assets | Where-Object { $_.name -like "UE4SS_v*.zip" } | Select-Object -First 1
if (-not $asset) {
    Write-Error "Could not find a 'UE4SS_v*.zip' asset on the experimental-latest release."
    exit 1
}

Write-Host "Downloading $($asset.name) ..."
Push-Location $work
try {
    gh release download experimental-latest --repo UE4SS-RE/RE-UE4SS --pattern $asset.name --clobber
} finally {
    Pop-Location
}

$zipPath = Join-Path $work $asset.name
if (-not (Test-Path $zipPath)) {
    Write-Error "Download did not produce $zipPath"
    exit 1
}

Write-Host "Extracting into $win64Dir ..."
Expand-Archive -Path $zipPath -DestinationPath $win64Dir -Force

Write-Host ""
Write-Host "UE4SS files extracted into $win64Dir."
Write-Host "Next: launch RSDragonwilds once, reach the main menu, then close it - this lets"
Write-Host "UE4SS create its Mods folder. Confirm $win64Dir\ue4ss\Mods exists, then run .\install.ps1"
Write-Host "from this repo to link RSDWRandomEvents in."
