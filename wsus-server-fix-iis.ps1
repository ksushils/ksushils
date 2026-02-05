# WSUS Server - Fix IIS and Check for Client Registration Issues
# Run this on WSUS SERVER

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "WSUS Server - IIS Fix & Diagnostics" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check and fix IIS Application Pools
Write-Host "[1] Checking IIS Application Pools..." -ForegroundColor Yellow

# Use appcmd instead of PowerShell WebAdministration module
$appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"

Write-Host "  Listing all application pools:" -ForegroundColor DarkGray
& $appcmd list apppool

Write-Host ""
Write-Host "  Checking WsusPool status..." -ForegroundColor DarkGray
$wsusPoolStatus = & $appcmd list apppool "WsusPool"

if ($wsusPoolStatus -match "state:Stopped") {
    Write-Host "  [WARNING] WsusPool is STOPPED! Starting..." -ForegroundColor Red
    & $appcmd start apppool "WsusPool"
    Start-Sleep -Seconds 3
    Write-Host "  [OK] WsusPool started" -ForegroundColor Green
} elseif ($wsusPoolStatus -match "state:Started") {
    Write-Host "  [OK] WsusPool is running" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] WsusPool status unknown" -ForegroundColor Yellow
}

# Step 2: Check IIS websites
Write-Host ""
Write-Host "[2] Checking IIS Websites..." -ForegroundColor Yellow
& $appcmd list site

# Step 3: Restart IIS completely
Write-Host ""
Write-Host "[3] Restarting IIS..." -ForegroundColor Yellow
iisreset /stop
Start-Sleep -Seconds 3
iisreset /start
Start-Sleep -Seconds 5
Write-Host "  [OK] IIS restarted" -ForegroundColor Green

# Step 4: Restart WSUS service
Write-Host ""
Write-Host "[4] Restarting WSUS service..." -ForegroundColor Yellow
Restart-Service WsusService -Force
Start-Sleep -Seconds 5

$wsusService = Get-Service WsusService
Write-Host "  WSUS Service Status: $($wsusService.Status)" -ForegroundColor $(if ($wsusService.Status -eq "Running") { "Green" } else { "Red" })

# Step 5: Restart WID (Database)
Write-Host ""
Write-Host "[5] Restarting Windows Internal Database..." -ForegroundColor Yellow
Restart-Service "MSSQL`$MICROSOFT##WID" -Force
Start-Sleep -Seconds 5

$widService = Get-Service "MSSQL`$MICROSOFT##WID"
Write-Host "  WID Service Status: $($widService.Status)" -ForegroundColor $(if ($widService.Status -eq "Running") { "Green" } else { "Red" })

# Step 6: Verify port 8530 is listening
Write-Host ""
Write-Host "[6] Verifying port 8530..." -ForegroundColor Yellow
$listening = Get-NetTCPConnection -LocalPort 8530 -State Listen -ErrorAction SilentlyContinue
if ($listening) {
    Write-Host "  [OK] Port 8530 is listening" -ForegroundColor Green
    $listening | Format-Table LocalAddress, LocalPort, State, OwningProcess
} else {
    Write-Host "  [FAILED] Port 8530 is NOT listening!" -ForegroundColor Red
    Write-Host "  This means IIS is not serving WSUS properly!" -ForegroundColor Red
}

# Step 7: Test WSUS URL locally
Write-Host ""
Write-Host "[7] Testing WSUS URL locally..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8530" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Host "  [OK] WSUS URL responds: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "  [FAILED] Cannot access WSUS URL: $_" -ForegroundColor Red
    Write-Host "  This indicates IIS or WSUS site configuration issue!" -ForegroundColor Red
}

# Step 8: Check IIS logs for recent client connections
Write-Host ""
Write-Host "[8] Checking IIS logs for client connections..." -ForegroundColor Yellow

$iisLogPath = "C:\inetpub\logs\LogFiles\W3SVC1"
if (Test-Path $iisLogPath) {
    $latestLog = Get-ChildItem $iisLogPath -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($latestLog) {
        Write-Host "  Latest log: $($latestLog.Name)" -ForegroundColor DarkGray
        Write-Host "  Last modified: $($latestLog.LastWriteTime)" -ForegroundColor DarkGray

        # Get last 50 lines
        $logLines = Get-Content $latestLog.FullName -Tail 50

        # Look for client connections (10.50.5.x addresses)
        $clientConnections = $logLines | Select-String -Pattern "10\.50\.5\." | Select-Object -Last 10

        if ($clientConnections) {
            Write-Host ""
            Write-Host "  Recent client connections found:" -ForegroundColor Green
            $clientConnections | ForEach-Object {
                Write-Host "    $_" -ForegroundColor White
            }
        } else {
            Write-Host ""
            Write-Host "  [WARNING] No client connections found in recent logs!" -ForegroundColor Yellow
            Write-Host "  This means clients are NOT reaching the WSUS server via IIS!" -ForegroundColor Red
        }

        # Look for errors
        $errors = $logLines | Select-String -Pattern " 500 | 503 | 404 "
        if ($errors) {
            Write-Host ""
            Write-Host "  [WARNING] HTTP errors found:" -ForegroundColor Red
            $errors | Select-Object -Last 5 | ForEach-Object {
                Write-Host "    $_" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "  [WARNING] IIS log directory not found: $iisLogPath" -ForegroundColor Yellow
}

# Step 9: Check WSUS-specific IIS logs
Write-Host ""
Write-Host "[9] Checking WSUS-specific logs..." -ForegroundColor Yellow

$wsusLogPath = "C:\Program Files\Update Services\LogFiles\SoftwareDistribution.log"
if (Test-Path $wsusLogPath) {
    Write-Host "  Found WSUS log: $wsusLogPath" -ForegroundColor DarkGray
    $wsusLogLines = Get-Content $wsusLogPath -Tail 30

    # Look for client registration
    $clientRegistration = $wsusLogLines | Select-String -Pattern "client|register|computer" -Context 0,1

    if ($clientRegistration) {
        Write-Host "  Recent client activity:" -ForegroundColor Cyan
        $clientRegistration | Select-Object -Last 10 | ForEach-Object {
            Write-Host "    $_" -ForegroundColor White
        }
    } else {
        Write-Host "  No recent client activity in WSUS log" -ForegroundColor Yellow
    }
} else {
    Write-Host "  WSUS log not found at: $wsusLogPath" -ForegroundColor Yellow
}

# Step 10: Check Windows Event Log
Write-Host ""
Write-Host "[10] Checking Windows Event Logs..." -ForegroundColor Yellow

$wsusEvents = Get-WinEvent -LogName "Application" -MaxEvents 20 -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -like "*WSUS*" -or $_.ProviderName -like "*UpdateServices*" }

if ($wsusEvents) {
    Write-Host "  Recent WSUS events:" -ForegroundColor Cyan
    $wsusEvents | Select-Object -First 5 | ForEach-Object {
        $color = switch ($_.LevelDisplayName) {
            "Error" { "Red" }
            "Warning" { "Yellow" }
            default { "Green" }
        }
        Write-Host "    [$($_.TimeCreated)] $($_.LevelDisplayName): $($_.Message.Substring(0, [Math]::Min(120, $_.Message.Length)))..." -ForegroundColor $color
    }
} else {
    Write-Host "  No recent WSUS events found" -ForegroundColor Yellow
}

# Step 11: Final service check
Write-Host ""
Write-Host "[11] Final service status check..." -ForegroundColor Yellow
Get-Service WsusService, "MSSQL`$MICROSOFT##WID", W3SVC | Format-Table Name, Status, StartType -AutoSize

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DIAGNOSTICS COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  - All services restarted" -ForegroundColor White
Write-Host "  - IIS restarted" -ForegroundColor White
Write-Host "  - Port 8530 checked" -ForegroundColor White
Write-Host "  - IIS logs analyzed" -ForegroundColor White
Write-Host ""
Write-Host "If port 8530 is NOT listening:" -ForegroundColor Yellow
Write-Host "  1. Check IIS Manager - ensure WSUS Administration site is started" -ForegroundColor White
Write-Host "  2. Check Windows Firewall is not blocking port 8530" -ForegroundColor White
Write-Host "  3. Run: netsh http show servicestate" -ForegroundColor White
Write-Host ""
Write-Host "If no client connections in IIS logs:" -ForegroundColor Yellow
Write-Host "  1. Verify security groups allow port 8530 between client and server" -ForegroundColor White
Write-Host "  2. On client, run: Test-NetConnection 10.50.5.96 -Port 8530" -ForegroundColor White
Write-Host "  3. Check network ACLs and routing" -ForegroundColor White
Write-Host ""
