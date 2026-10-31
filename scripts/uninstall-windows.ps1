<# 
.SYNOPSIS
    X Messenger Terminal — Windows uninstaller
.DESCRIPTION
    Removes installed files, Start Menu shortcuts, PATH entry, and optionally user data.
    Run in PowerShell as Administrator if installed system-wide.
.EXAMPLE
    .\scripts\uninstall-windows.ps1
.EXAMPLE
    .\scripts\uninstall-windows.ps1 -SystemWide -Purge
#>
[CmdletBinding()]
param(
    [switch]$SystemWide,
    [switch]$Purge,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Log { Write-Host "[$(Get-Date -Format HH:mm:ss)] $($args[0])" }
function Run {
    param([string]$cmd)
    if ($DryRun) { Write-Host "DRY: $cmd" } else { Invoke-Expression $cmd }
}

Log "Uninstalling X Messenger Terminal"

# Determine install directory
if ($SystemWide) {
    $targetDir = "$env:ProgramFiles\X Messenger Terminal"
    $startMenuDir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\X Messenger Terminal"
    $pathScope = 'Machine'
} else {
    $targetDir = "$env:LOCALAPPDATA\X Messenger Terminal"
    $startMenuDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\X Messenger Terminal"
    $pathScope = 'User'
}

# Remove install directory
if (Test-Path $targetDir) {
    Log "Removing $targetDir"
    Run "Remove-Item -Path '$targetDir' -Recurse -Force"
} else {
    Log "Install directory not found: $targetDir"
}

# Remove Start Menu shortcuts
if (Test-Path $startMenuDir) {
    Log "Removing Start Menu shortcuts"
    Run "Remove-Item -Path '$startMenuDir' -Recurse -Force"
}

# Remove from PATH
$currentPath = [Environment]::GetEnvironmentVariable('PATH', $pathScope)
$newPath = ($currentPath -split ';' | Where-Object { $_ -notlike "*X Messenger Terminal*" -and $_ -notlike "*x-messenger*" }) -join ';'
if ($newPath -ne $currentPath) {
    Log "Removing from $pathScope PATH"
    Run "[Environment]::SetEnvironmentVariable('PATH', '$newPath', '$pathScope')"
}

# Remove user data
if ($Purge) {
    $confirm = 'YES, I understand this cannot be undone'
} else {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "  REMOVE USER DATA?"
    Write-Host "=========================================="
    Write-Host "This will DELETE ALL local data:"
    Write-Host "  - Vault history (locked messages)"
    Write-Host "  - Local contacts (profiles)"
    Write-Host "  - Settings & preferences"
    Write-Host "  - Device identity (signing key)"
    Write-Host "  - Replay protection cache"
    Write-Host "  - Session messages"
    Write-Host ""
    Write-Host "Type exactly:  YES, I understand this cannot be undone"
    $confirm = Read-Host
}

if ($confirm -eq 'YES, I understand this cannot be undone') {
    Log "Wiping user data..."
    $dataDirs = @(
        "$env:APPDATA\x-messenger",
        "$env:LOCALAPPDATA\x-messenger",
        "$env:USERPROFILE\.xcourier"
    )
    foreach ($dir in $dataDirs) {
        if (Test-Path $dir) {
            Log "Removing $dir"
            Run "Remove-Item -Path '$dir' -Recurse -Force"
        }
    }
    Log "User data wiped."
} else {
    Log "User data preserved (use -Purge to remove)."
}

Log "Uninstall complete."