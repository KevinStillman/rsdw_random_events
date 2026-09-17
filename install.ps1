<#
.SYNOPSIS
    Installs RSDWRandomEvents into a local UE4SS-modded copy of RuneScape: Dragonwilds.

.DESCRIPTION
    Locates the game's UE4SS Mods folder (auto-detecting common Steam install locations,
    or using -GamePath if provided), creates a directory junction pointing
    Mods\RSDWRandomEvents at this repo (so edits here take effect immediately), and
    registers the mod in mods.txt.

    Requires UE4SS to already be installed for the game - run tools\Install-UE4SS.ps1
    first if Binaries\Win64\ue4ss doesn't exist yet.

.PARAMETER GamePath
    Path to the RSDragonwilds installation folder (the folder containing
    "Binaries\Win64\ue4ss"). If not provided, common Steam library locations are searched.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -GamePath "C:\Program Files (x86)\Steam\steamapps\common\RSDragonwilds\RSDragonwilds"
#>
param(
    [string]$GamePath
)

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
    Write-Error "Could not locate the RSDragonwilds installation. Re-run with -GamePath pointing at your 'RSDragonwilds' folder, e.g.:`n  .\install.ps1 -GamePath `"C:\Program Files (x86)\Steam\steamapps\common\RSDragonwilds\RSDragonwilds`""
    exit 1
}

$ue4ssDir = Join-Path $GamePath "Binaries\Win64\ue4ss"
if (-not (Test-Path $ue4ssDir)) {
    Write-Error "UE4SS doesn't appear to be installed at '$ue4ssDir'. Run tools\Install-UE4SS.ps1 first."
    exit 1
}

$modsDir  = Join-Path $ue4ssDir "Mods"
$modLink  = Join-Path $modsDir "RSDWRandomEvents"
$repoRoot = $PSScriptRoot
$modsFile = Join-Path $modsDir "mods.txt"

Write-Host "Installing to: $modsDir"

if (Test-Path $modLink) {
    Remove-Item $modLink -Force -Recurse
}

# Directory junction (no admin rights required) so edits in this repo take
# effect immediately without re-copying files.
$result = cmd /c mklink /J "$modLink" "$repoRoot" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create junction: $result"
    exit 1
}
Write-Host "Junction created: $modLink -> $repoRoot"

$entry = "RSDWRandomEvents : 1"
$content = Get-Content $modsFile -Raw -ErrorAction SilentlyContinue
if ($content -notmatch "RSDWRandomEvents") {
    if ($content -and -not $content.EndsWith("`n")) {
        Add-Content -Path $modsFile -Value ""
    }
    Add-Content -Path $modsFile -Value $entry
    Write-Host "Added '$entry' to mods.txt"
} else {
    Write-Host "mods.txt already contains RSDWRandomEvents entry"
}

Write-Host "Install complete. Launch the game and check UE4SS.log for '[RSDWRandomEvents] Loaded'."
