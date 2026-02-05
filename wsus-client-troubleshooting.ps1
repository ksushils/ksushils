# WSUS Client Troubleshooting Script
# Run this on the CLIENT to diagnose why it's not appearing in WSUS console

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "WSUS Client Troubleshooting" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$WSUSServer = "10.50.5.96"
$WSUSPort = "8530"

# Check 1: Registry Configuration
Write-Host "[1] Checking Registry Configuration..." -ForegroundColor Yellow
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$regPathAU = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

$checks = @{
    "WUServer" = (Get-ItemProperty -Path $regPath -Name "WUServer" -ErrorAction SilentlyContinue).WUServer
    "WUStatusServer" = (Get-ItemProperty -Path $regPath -Name "WUStatusServer" -ErrorAction SilentlyContinue).WUStatusServer
    "UseWUServer" = (Get-ItemProperty -Path $regPathAU -Name "UseWUServer" -ErrorAction SilentlyContinue).UseWUServer
    "NoAutoUpdate" = (Get-ItemProperty -Path $regPathAU -Name "NoAutoUpdate" -ErrorAction SilentlyContinue).NoAutoUpdate
    "AUOptions" = (Get-ItemProperty -Path $regPathAU -Name "AUOptions" -ErrorAction SilentlyContinue).AUOptions
}

foreach ($key in $checks.Keys) {
    $value = $checks[$key]
    if ($null -ne $value) {
        Write-Host "  [OK] $key = $value" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $key not set" -ForegroundColor Red
    }
}

Write-Host ""

# Check 2: Windows Update Service
Write-Host "[2] Checking Windows Update Service..." -ForegroundColor Yellow
$service = Get-Service -Name wuauserv
Write-Host "  Status: $($service.Status)" -ForegroundColor $(if ($service.Status -eq "Running") { "Green" } else { "Red" })
Write-Host "  StartType: $($service.StartType)" -ForegroundColor $(if ($service.StartType -eq "Automatic") { "Green" } else { "Yellow" })

if ($service.Status -ne "Running") {
    Write-Host "  [ACTION] Service is not running. Starting..." -ForegroundColor Yellow
    Start-Service -Name wuauserv
    Start-Sleep -Seconds 3
    $service = Get-Service -Name wuauserv
    Write-Host "  New Status: $($service.Status)" -ForegroundColor Green
}

Write-Host ""

# Check 3: Network Connectivity
Write-Host "[3] Testing Network Connectivity to WSUS Server..." -ForegroundColor Yellow
$connection = Test-NetConnection -ComputerName $WSUSServer -Port $WSUSPort
if ($connection.TcpTestSucceeded) {
    Write-Host "  [OK] Successfully connected to ${WSUSServer}:${WSUSPort}" -ForegroundColor Green
} else {
    Write-Host "  [FAILED] Cannot connect to ${WSUSServer}:${WSUSPort}" -ForegroundColor Red
    Write-Host "  Check: Security groups, firewall, WSUS service on server" -ForegroundColor Yellow
}

Write-Host ""

# Check 4: Windows Update Client Status
Write-Host "[4] Checking Windows Update Client Status..." -ForegroundColor Yellow

# Check last successful scan time
$auKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect"
$lastSuccess = (Get-ItemProperty -Path $auKey -Name "LastSuccessTime" -ErrorAction SilentlyContinue).LastSuccessTime
if ($lastSuccess) {
    Write-Host "  Last Successful Detection: $lastSuccess" -ForegroundColor Green
} else {
    Write-Host "  Last Successful Detection: Never" -ForegroundColor Yellow
}

# Check for server selection
$serverSelection = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services"
if (Test-Path $serverSelection) {
    Write-Host "  [OK] Windows Update services registered" -ForegroundColor Green
}

Write-Host ""

# Check 5: Windows Update Logs
Write-Host "[5] Generating Windows Update Log..." -ForegroundColor Yellow
Write-Host "  This may take 1-2 minutes..." -ForegroundColor DarkGray

try {
    Get-WindowsUpdateLog -ErrorAction Stop | Out-Null
    Write-Host "  [OK] Log generated: $env:USERPROFILE\Desktop\WindowsUpdate.log" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Opening last 50 lines of log..." -ForegroundColor Yellow
    Write-Host ""

    $logPath = "$env:USERPROFILE\Desktop\WindowsUpdate.log"
    if (Test-Path $logPath) {
        $lastLines = Get-Content $logPath -Tail 50

        # Look for WSUS server references
        $wsusLines = $lastLines | Select-String -Pattern "10.50.5.96|8530|WSUS|AU|UpdateServer" -Context 0,2
        if ($wsusLines) {
            Write-Host "  Recent WSUS-related log entries:" -ForegroundColor Cyan
            $wsusLines | ForEach-Object {
                Write-Host "    $_" -ForegroundColor White
            }
        } else {
            Write-Host "  No recent WSUS references found in log" -ForegroundColor Yellow
        }

        # Look for errors
        Write-Host ""
        $errorLines = $lastLines | Select-String -Pattern "ERROR|FAILED|WARNING" -Context 0,1
        if ($errorLines) {
            Write-Host "  Recent errors/warnings:" -ForegroundColor Red
            $errorLines | ForEach-Object {
                Write-Host "    $_" -ForegroundColor Red
            }
        }
    }
} catch {
    Write-Host "  [WARNING] Could not generate log: $_" -ForegroundColor Yellow
}

Write-Host ""

# Check 6: Force Detection and Reporting
Write-Host "[6] Forcing Detection and Reporting..." -ForegroundColor Yellow

# Method 1: wuauclt
Write-Host "  Running: wuauclt /resetauthorization" -ForegroundColor DarkGray
Start-Process -FilePath "wuauclt.exe" -ArgumentList "/resetauthorization" -NoNewWindow -Wait
Start-Sleep -Seconds 2

Write-Host "  Running: wuauclt /detectnow" -ForegroundColor DarkGray
Start-Process -FilePath "wuauclt.exe" -ArgumentList "/detectnow" -NoNewWindow
Start-Sleep -Seconds 2

Write-Host "  Running: wuauclt /reportnow" -ForegroundColor DarkGray
Start-Process -FilePath "wuauclt.exe" -ArgumentList "/reportnow" -NoNewWindow
Start-Sleep -Seconds 2

# Method 2: UsoClient (Windows 10/Server 2016+)
$osVersion = [System.Environment]::OSVersion.Version
if ($osVersion.Major -ge 10) {
    Write-Host "  Running: usoclient StartScan" -ForegroundColor DarkGray
    Start-Process -FilePath "usoclient.exe" -ArgumentList "StartScan" -NoNewWindow -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Write-Host "  Running: usoclient RefreshSettings" -ForegroundColor DarkGray
    Start-Process -FilePath "usoclient.exe" -ArgumentList "RefreshSettings" -NoNewWindow -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

Write-Host "  [OK] Detection and reporting commands executed" -ForegroundColor Green

Write-Host ""

# Check 7: Event Logs
Write-Host "[7] Checking Windows Update Event Logs..." -ForegroundColor Yellow

# Check Windows Update events
$events = Get-WinEvent -LogName "System" -MaxEvents 20 -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -like "*WindowsUpdate*" -or $_.ProviderName -like "*WUAUENG*" }

if ($events) {
    Write-Host "  Recent Windows Update events:" -ForegroundColor Cyan
    $events | Select-Object -First 5 | ForEach-Object {
        $color = switch ($_.LevelDisplayName) {
            "Error" { "Red" }
            "Warning" { "Yellow" }
            default { "Green" }
        }
        Write-Host "    [$($_.TimeCreated)] $($_.LevelDisplayName): $($_.Message.Substring(0, [Math]::Min(100, $_.Message.Length)))..." -ForegroundColor $color
    }
} else {
    Write-Host "  No recent Windows Update events found" -ForegroundColor Yellow
}

Write-Host ""

# Summary and Recommendations
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Determine issues
$issues = @()
if ($checks["WUServer"] -ne "http://${WSUSServer}:${WSUSPort}") {
    $issues += "WUServer registry not set correctly"
}
if ($checks["UseWUServer"] -ne 1) {
    $issues += "UseWUServer not enabled"
}
if ($service.Status -ne "Running") {
    $issues += "Windows Update service not running"
}
if (-not $connection.TcpTestSucceeded) {
    $issues += "Cannot connect to WSUS server"
}

if ($issues.Count -eq 0) {
    Write-Host "[OK] All checks passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Client is properly configured." -ForegroundColor Green
    Write-Host ""
    Write-Host "If client still doesn't appear in WSUS console:" -ForegroundColor Yellow
    Write-Host "  1. Wait 20-30 minutes - initial registration can take time" -ForegroundColor White
    Write-Host "  2. Check WSUS Console > Computers > 'Unassigned Computers'" -ForegroundColor White
    Write-Host "  3. Review the Windows Update log on desktop" -ForegroundColor White
    Write-Host "  4. Check WSUS server IIS Application Pool is running" -ForegroundColor White
    Write-Host "  5. Restart WSUS service on server: Restart-Service WsusService" -ForegroundColor White
} else {
    Write-Host "[ISSUES FOUND]" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  - $issue" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Run the wsus-client-userdata.ps1 script again to reconfigure." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Additional diagnostic commands
Write-Host "ADDITIONAL DIAGNOSTIC COMMANDS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "Check registry:" -ForegroundColor White
Write-Host '  reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"' -ForegroundColor DarkGray
Write-Host ""
Write-Host "Force immediate scan:" -ForegroundColor White
Write-Host "  wuauclt /detectnow /reportnow" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Check Windows Update log:" -ForegroundColor White
Write-Host "  Get-WindowsUpdateLog" -ForegroundColor DarkGray
Write-Host "  (Log will be on desktop)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Verify connectivity:" -ForegroundColor White
Write-Host "  Test-NetConnection $WSUSServer -Port $WSUSPort" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Check service:" -ForegroundColor White
Write-Host "  Get-Service wuauserv | Format-List *" -ForegroundColor DarkGray
Write-Host ""
