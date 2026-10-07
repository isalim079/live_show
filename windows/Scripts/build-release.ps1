#Requires -Version 5.1
<#
.SYNOPSIS
  Publishes a self-contained win-x64 Live Show portable build into windows\Release_Build.

.DESCRIPTION
  Run from a Windows machine (or any host with the .NET 8 SDK and Windows targeting pack):

    powershell -ExecutionPolicy Bypass -File windows\Scripts\build-release.ps1

  Output:
    windows\Release_Build\LiveWallpaper.exe  (+ native WPF DLLs)
#>
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WindowsRoot = Resolve-Path (Join-Path $ScriptDir "..")
$Project = Join-Path $WindowsRoot "LiveWallpaper\LiveWallpaper.csproj"
$OutDir = Join-Path $WindowsRoot "Release_Build"

Write-Host "========================================="
Write-Host " Building Live Show (Windows portable)"
Write-Host "========================================="
Write-Host "Project: $Project"
Write-Host "Output:  $OutDir"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "dotnet SDK not found. Install .NET 8 SDK from https://dotnet.microsoft.com/download"
}

if (Test-Path $OutDir) {
    Remove-Item -Recurse -Force $OutDir
}
New-Item -ItemType Directory -Path $OutDir | Out-Null

dotnet publish $Project `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -o $OutDir

if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE"
}

# Drop debug symbols from the share folder
Get-ChildItem $OutDir -Filter *.pdb -ErrorAction SilentlyContinue | Remove-Item -Force

$RepoRoot = Resolve-Path (Join-Path $WindowsRoot "..")
$ExeTarget = Join-Path $RepoRoot "liveShow_v1.4.0.exe"
$ZipTarget = Join-Path $RepoRoot "liveShow_windows_v1.4.0.zip"
Copy-Item (Join-Path $OutDir "LiveWallpaper.exe") $ExeTarget -Force

if (Test-Path $ZipTarget) {
    Remove-Item -Force $ZipTarget
}
Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $ZipTarget -Force

Write-Host ""
Write-Host "Portable build ready:"
Get-ChildItem $OutDir | Format-Table Name, Length -AutoSize
Write-Host "Standalone EXE: $ExeTarget"
Write-Host "Release Zip:    $ZipTarget"
Write-Host ""
Write-Host "Optional: compile windows\Scripts\LiveShow.iss with Inno Setup to produce LiveShow_Setup.exe"
Write-Host "========================================="
