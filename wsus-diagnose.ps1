# WSUS Installation Diagnostics Script
# Run this script to diagnose WSUS installation issues

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "WSUS Installation Diagnostics" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Check Windows Features
Write-Host "[1] Checking WSUS Windows Features..." -ForegroundColor Yellow
$wsusFeatures = Get-WindowsFeature | Where-Object { $_.Name -like "UpdateServices*" }

Write-Host "`nAll UpdateServices Features:" -ForegroundColor Green
foreach ($feature in $wsusFeatures) {
    $status = if ($feature.Installed) { "INSTALLED" } else { "Not Installed" }
    $color = if ($feature.Installed) { "Green" } else { "Gray" }
    Write-Host "  $($feature.Name.PadRight(30)) : " -NoNewline
    Write-Host "$status" -ForegroundColor $color
    Write-Host "    DisplayName: $($feature.DisplayName)" -ForegroundColor DarkGray
    Write-Host "    InstallState: $($feature.InstallState)" -ForegroundColor DarkGray
}

# Check if UpdateServices-DB is installed (conflict)
$sqlConnectivity = Get-WindowsFeature -Name "UpdateServices-DB"
if ($sqlConnectivity.Installed) {
    Write-Host "`n[!] WARNING: UpdateServices-DB (SQL Server Connectivity) is INSTALLED" -ForegroundColor Red
    Write-Host "    This will conflict with WID installation" -ForegroundColor Red
    Write-Host "    To fix: Uninstall-WindowsFeature -Name UpdateServices-DB" -ForegroundColor Yellow
}

Write-Host ""

# Check for wsusutil.exe
Write-Host "[2] Searching for wsusutil.exe..." -ForegroundColor Yellow
$wsusUtilLocations = @(
    "C:\Program Files\Update Services\Tools\wsusutil.exe",
    "C:\Program Files (x86)\Update Services\Tools\wsusutil.exe",
    "$env:ProgramFiles\Update Services\Tools\wsusutil.exe"
)

$found = $false
foreach ($location in $wsusUtilLocations) {
    if (Test-Path $location) {
        Write-Host "  [FOUND] $location" -ForegroundColor Green
        $found = $true

        # Get file details
        $fileInfo = Get-Item $location
        Write-Host "    Version: $($fileInfo.VersionInfo.FileVersion)" -ForegroundColor DarkGray
        Write-Host "    Size: $([math]::Round($fileInfo.Length/1KB,2)) KB" -ForegroundColor DarkGray
        Write-Host "    Modified: $($fileInfo.LastWriteTime)" -ForegroundColor DarkGray
    } else {
        Write-Host "  [NOT FOUND] $location" -ForegroundColor DarkGray
    }
}

if (-not $found) {
    Write-Host "`n  Performing deep search..." -ForegroundColor Yellow
    $searchResult = Get-ChildItem -Path "C:\Program Files" -Recurse -Filter "wsusutil.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($searchResult) {
        Write-Host "  [FOUND] $($searchResult.FullName)" -ForegroundColor Green
    } else {
        Write-Host "  [NOT FOUND] wsusutil.exe not found anywhere" -ForegroundColor Red
    }
}

Write-Host ""

# Check WSUS Service
Write-Host "[3] Checking WSUS Services..." -ForegroundColor Yellow
$wsusServices = @("WsusService", "MSSQL`$MICROSOFT##WID")

foreach ($serviceName in $wsusServices) {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        $color = switch ($service.Status) {
            "Running" { "Green" }
            "Stopped" { "Yellow" }
            default { "Red" }
        }
        Write-Host "  $($serviceName.PadRight(30)) : " -NoNewline
        Write-Host "$($service.Status)" -ForegroundColor $color
        Write-Host "    StartType: $($service.StartType)" -ForegroundColor DarkGray
    } else {
        Write-Host "  $($serviceName.PadRight(30)) : " -NoNewline
        Write-Host "Not Found" -ForegroundColor DarkGray
    }
}

Write-Host ""

# Check IIS and related services
Write-Host "[4] Checking IIS..." -ForegroundColor Yellow
$iisFeature = Get-WindowsFeature -Name "Web-Server"
if ($iisFeature.Installed) {
    Write-Host "  IIS is INSTALLED" -ForegroundColor Green

    # Check IIS service
    $iisService = Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    if ($iisService) {
        Write-Host "  W3SVC Status: $($iisService.Status)" -ForegroundColor $(if ($iisService.Status -eq "Running") { "Green" } else { "Yellow" })
    }
} else {
    Write-Host "  IIS is NOT INSTALLED" -ForegroundColor Red
    Write-Host "  WSUS requires IIS to be installed" -ForegroundColor Yellow
}

Write-Host ""

# Check disk space
Write-Host "[5] Checking Disk Space..." -ForegroundColor Yellow
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 } | ForEach-Object {
    $total = [math]::Round(($_.Used + $_.Free) / 1GB, 2)
    $free = [math]::Round($_.Free / 1GB, 2)
    $usedPercent = [math]::Round(($_.Used / ($_.Used + $_.Free)) * 100, 1)

    $color = if ($free -lt 10) { "Red" } elseif ($free -lt 20) { "Yellow" } else { "Green" }

    Write-Host "  Drive $($_.Name): " -NoNewline
    Write-Host "$free GB free of $total GB ($usedPercent% used)" -ForegroundColor $color
}

Write-Host ""

# Check for pending reboot
Write-Host "[6] Checking for Pending Reboot..." -ForegroundColor Yellow
$rebootPending = $false
$rebootReasons = @()

if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
    $rebootPending = $true
    $rebootReasons += "Component Based Servicing"
}

if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
    $rebootPending = $true
    $rebootReasons += "Windows Update"
}

if (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue) {
    $rebootPending = $true
    $rebootReasons += "Pending File Rename Operations"
}

try {
    $pendingReboot = Invoke-WmiMethod -Namespace "root\ccm\clientsdk" -Class CCM_ClientUtilities -Name DetermineIfRebootPending -ErrorAction SilentlyContinue
    if ($pendingReboot -and $pendingReboot.RebootPending) {
        $rebootPending = $true
        $rebootReasons += "SCCM Client"
    }
} catch { }

if ($rebootPending) {
    Write-Host "  [WARNING] Reboot is PENDING" -ForegroundColor Red
    Write-Host "  Reasons:" -ForegroundColor Yellow
    foreach ($reason in $rebootReasons) {
        Write-Host "    - $reason" -ForegroundColor Yellow
    }
    Write-Host "`n  You should REBOOT before continuing with WSUS setup" -ForegroundColor Yellow
} else {
    Write-Host "  No pending reboot detected" -ForegroundColor Green
}

Write-Host ""

# Check WSUS directories
Write-Host "[7] Checking WSUS Directories..." -ForegroundColor Yellow
$wsusDirs = @(
    "C:\Program Files\Update Services",
    "C:\WSUS",
    "C:\Windows\WID"
)

foreach ($dir in $wsusDirs) {
    if (Test-Path $dir) {
        $size = (Get-ChildItem -Path $dir -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $sizeMB = [math]::Round($size / 1MB, 2)
        Write-Host "  [EXISTS] $dir ($sizeMB MB)" -ForegroundColor Green
    } else {
        Write-Host "  [NOT FOUND] $dir" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Diagnosis Complete" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Summary and recommendations
Write-Host "SUMMARY & RECOMMENDATIONS:" -ForegroundColor Yellow
Write-Host ""

$installedCount = ($wsusFeatures | Where-Object { $_.Installed }).Count
if ($installedCount -eq 0) {
    Write-Host "[!] ISSUE: No WSUS features are installed" -ForegroundColor Red
    Write-Host "    Fix: Install-WindowsFeature -Name UpdateServices -IncludeManagementTools" -ForegroundColor Yellow
} elseif ($installedCount -lt 3) {
    Write-Host "[!] WARNING: Only $installedCount WSUS feature(s) installed (partial installation)" -ForegroundColor Yellow
    Write-Host "    You may need to complete the installation or reinstall" -ForegroundColor Yellow
} else {
    Write-Host "[OK] WSUS features are installed" -ForegroundColor Green
}

if ($sqlConnectivity.Installed) {
    Write-Host "[!] ISSUE: SQL Server Connectivity conflict detected" -ForegroundColor Red
    Write-Host "    Fix: Uninstall-WindowsFeature -Name UpdateServices-DB" -ForegroundColor Yellow
}

if (-not $found) {
    Write-Host "[!] ISSUE: wsusutil.exe not found" -ForegroundColor Red
    Write-Host "    This suggests WSUS binaries were not installed" -ForegroundColor Yellow
    if ($rebootPending) {
        Write-Host "    Possible cause: Reboot is pending" -ForegroundColor Yellow
        Write-Host "    Action: REBOOT the server and check again" -ForegroundColor Yellow
    }
}

if ($rebootPending) {
    Write-Host "[!] ACTION REQUIRED: Reboot the server before continuing" -ForegroundColor Red
}

Write-Host ""
Write-Host "After addressing any issues, you can run:" -ForegroundColor Cyan
Write-Host "  wsusutil.exe postinstall CONTENT_DIR=C:\WSUS" -ForegroundColor White
Write-Host ""
