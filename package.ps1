<#
.SYNOPSIS
    Builds a distributable zip of RSDWRandomEvents for Nexus Mods.

.DESCRIPTION
    Packages Scripts/*.lua (and LICENSE) into an RSDWRandomEvents/ folder matching the
    layout expected under <Game>\Binaries\Win64\ue4ss\Mods\, and zips it to
    dist\RSDWRandomEvents-vX.Y.Z.zip. The version is read from the VERSION file.

.EXAMPLE
    .\package.ps1
#>

$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$version  = (Get-Content (Join-Path $repoRoot "VERSION") -Raw).Trim()

$distDir   = Join-Path $repoRoot "dist"
$stageRoot = Join-Path $distDir "stage"
$modStage  = Join-Path $stageRoot "RSDWRandomEvents"
$zipPath   = Join-Path $distDir "RSDWRandomEvents-v$version.zip"

if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
if (Test-Path $zipPath)   { Remove-Item $zipPath -Force }
New-Item -ItemType Directory -Path $modStage -Force | Out-Null

$scriptsSrc = Join-Path $repoRoot "Scripts"
$scriptsDst = Join-Path $modStage "Scripts"
New-Item -ItemType Directory -Path $scriptsDst -Force | Out-Null
Copy-Item (Join-Path $scriptsSrc "main.lua")      $scriptsDst
Copy-Item (Join-Path $scriptsSrc "config.lua")    $scriptsDst
Copy-Item (Join-Path $scriptsSrc "events.lua")    $scriptsDst
Copy-Item (Join-Path $scriptsSrc "notify.lua")    $scriptsDst
Copy-Item (Join-Path $scriptsSrc "discovery.lua") $scriptsDst
Copy-Item (Join-Path $scriptsSrc "encounter.lua") $scriptsDst
Copy-Item (Join-Path $scriptsSrc "prompt.lua")    $scriptsDst

Copy-Item (Join-Path $repoRoot "LICENSE") $modStage

Compress-Archive -Path $modStage -DestinationPath $zipPath -Force

Remove-Item $stageRoot -Recurse -Force

Write-Host "Packaged RSDWRandomEvents v$version -> $zipPath"
