<# 
.SYNOPSIS
    X Messenger Terminal — Windows installer
.DESCRIPTION
    Installs the portable ZIP, creates Start Menu shortcuts, and adds to PATH.
    Run in PowerShell as Administrator for system-wide install, or as user for per-user install.
.EXAMPLE
    .\scripts\install-windows.ps1
.EXAMPLE
    .\scripts\install-windows.ps1 -SystemWide
#>
[CmdletBinding()]
param(
    [switch]$SystemWide,
    [switch]$DryRun,
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'

function Log { Write-Host "[$(Get-Date -Format HH:mm:ss)] $($args[0])" }
function Run {
    param([string]$cmd)
    if ($DryRun) { Write-Host "DRY: $cmd" } else { Invoke-Expression $cmd }
}

$version = (Get-Content package.json | ConvertFrom-Json).version
Log "Installing X Messenger Terminal v$version"

# Check prerequisites
$nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodePath) { Write-Error "Node.js not found. Install Node 20+ from https://nodejs.org"; exit 1 }
$nodeVer = [int](node -p "process.version.slice(1).split('.')[0]")
if ($nodeVer -lt 20) { Write-Error "Node >=20 required (found $nodeVer)"; exit 1 }

$opensslPath = (Get-Command openssl -ErrorAction SilentlyContinue).Source
if (-not $opensslPath) { Write-Error "OpenSSL not found. Install from https://slproweb.com/products/Win32OpenSSL.html"; exit 1 }

# Determine install directory
if ($InstallDir) {
    $targetDir = $InstallDir
} elseif ($SystemWide) {
    $targetDir = "$env:ProgramFiles\X Messenger Terminal"
} else {
    $targetDir = "$env:LOCALAPPDATA\X Messenger Terminal"
}

# Find artifact
$distDir = if ($env:X_MESSENGER_DIST) { $env:X_MESSENGER_DIST } else { Join-Path $PSScriptRoot "..\dist" }
$zipFiles = Get-ChildItem "$distDir\X-Messenger-*-Windows-*.zip" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
if (-not $zipFiles) {
    Write-Error "No Windows ZIP found in $distDir. Run 'npm run build:windows' first."
    exit 1
}
$zipFile = $zipFiles[0]
Log "Using artifact: $($zipFile.Name)"

# Extract
Log "Extracting to $targetDir"
if (-not $DryRun) {
    if (Test-Path $targetDir) { Remove-Item $targetDir -Recurse -Force }
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Expand-Archive -Path $zipFile.FullName -DestinationPath $targetDir -Force
}

# Find the extracted folder (may have version in name)
$extractedDir = Get-ChildItem $targetDir -Directory | Select-Object -First 1
if ($extractedDir.FullName -ne $targetDir) {
    # Move contents up one level
    Get-ChildItem $extractedDir.FullName | Move-Item -Destination $targetDir -Force
    Remove-Item $extractedDir.FullName -Recurse -Force
}

# Create Start Menu shortcuts
$startMenuDir = if ($SystemWide) { "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\X Messenger Terminal" } else { "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\X Messenger Terminal" }
Log "Creating Start Menu shortcuts in $startMenuDir"
Run "New-Item -ItemType Directory -Path '$startMenuDir' -Force"

$guiExe = Get-ChildItem "$targetDir\*GUI*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
$cliExe = Get-ChildItem "$targetDir\cipherlink*" -ErrorAction SilentlyContinue | Where-Object { -not $_.Name.EndsWith(".exe") } | Select-Object -First 1

if ($guiExe) {
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("$startMenuDir\X Messenger Terminal.lnk")
    $shortcut.TargetPath = $guiExe.FullName
    $shortcut.WorkingDirectory = $targetDir
    $shortcut.Description = "X Messenger Terminal - Offline encrypted QR courier"
    $shortcut.Save()
}

if ($cliExe) {
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("$startMenuDir\X Messenger CLI.lnk")
    $shortcut.TargetPath = "cmd.exe"
    $shortcut.Arguments = "/k `"$targetDir\$($cliExe.Name)`""
    $shortcut.WorkingDirectory = $targetDir
    $shortcut.Description = "X Messenger CLI"
    $shortcut.Save()
}

# Add to PATH (user or system)
$pathScope = if ($SystemWide) { 'Machine' } else { 'User' }
$currentPath = [Environment]::GetEnvironmentVariable('PATH', $pathScope)
if ($currentPath -notlike "*$targetDir*") {
    Log "Adding $targetDir to $pathScope PATH"
    Run "[Environment]::SetEnvironmentVariable('PATH', '$currentPath;$targetDir', '$pathScope')"
}

# Set restrictive permissions on key material
Log "Setting restrictive permissions on key/cert files"
Get-ChildItem $targetDir -Recurse -Include *.pem,*.key,*.crt -ErrorAction SilentlyContinue | ForEach-Object {
    Run "icacls '$($_.FullName)' /inheritance:r /grant:r `'$env:USERNAME:(R)`' /grant:r `'Administrators:(F)`' /grant:r `'SYSTEM:(F)`'"
}

Log "Installation complete."
Write-Host ""
Write-Host "Run 'X Messenger Terminal' from Start Menu, or:"
Write-Host "  cipherlink-gui        # GUI (opens https://127.0.0.1:443)"
Write-Host "  cipherlink encrypt ... # CLI"
Write-Host ""
Write-Host "Note: You may need to restart your shell for PATH changes to take effect."