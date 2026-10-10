# Harvest dev setup, part 1 (Windows). Run from an ADMIN PowerShell:
#   powershell -ExecutionPolicy Bypass -File "C:\path\to\harvest\setup\1-windows-setup.ps1"
# Reboot when it finishes, then run part 2 inside Ubuntu.

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "Run this from an admin PowerShell." }

Write-Host "`n[1/3] Installing WSL + Ubuntu 24.04..." -ForegroundColor Cyan
wsl --install -d Ubuntu-24.04 --no-launch

Write-Host "`n[2/3] Turning on WSL mirrored networking (lets Ubuntu reach the iPhone service on 127.0.0.1)..." -ForegroundColor Cyan
$cfg = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path $cfg) {
    $text = Get-Content $cfg -Raw
    if ($text -notmatch 'networkingMode') {
        if ($text -match '\[wsl2\]') { $text = $text -replace '\[wsl2\]', "[wsl2]`r`nnetworkingMode=mirrored" }
        else { $text += "`r`n[wsl2]`r`nnetworkingMode=mirrored`r`n" }
        Set-Content -Path $cfg -Value $text -Encoding ascii
    }
} else {
    Set-Content -Path $cfg -Value "[wsl2]`r`nnetworkingMode=mirrored`r`n" -Encoding ascii
}
Get-Content $cfg

Write-Host "`n[3/3] Installing Apple Devices (provides the iPhone connection service xtool uses)..." -ForegroundColor Cyan
winget install --id 9NP83LWLPZ9K --source msstore --accept-package-agreements --accept-source-agreements

Write-Host "`nDone. Next:" -ForegroundColor Green
Write-Host "  1. Reboot."
Write-Host "  2. Open 'Ubuntu 24.04' from Start, create a username + password."
Write-Host "  3. Plug the iPhone in, open Apple Devices, tap Trust on the iPhone."
Write-Host "  4. In Ubuntu run:  bash '/mnt/c/path/to/harvest/setup/2-wsl-setup.sh'"
Write-Host "  5. Download Xcode 27 (.xip) from https://developer.apple.com/download/all/?q=Xcode into your Downloads folder."
