# WSUS Server Checks - Why Clients Aren't Appearing

Run these checks on the **WSUS SERVER** (10.50.5.96) to ensure it's ready to accept clients.

## 1. Check WSUS Console for Unassigned Computers

**Why**: Clients may appear in "Unassigned Computers" before appearing in "All Computers"

**Steps**:
1. Open Server Manager
2. Tools → Windows Server Update Services
3. Expand: **Computers** → **Unassigned Computers**
4. Look for your client machine here

## 2. Verify IIS Application Pool is Running

**Why**: Clients connect via IIS, if the app pool is stopped, clients can't register

```powershell
# Check IIS Application Pool status
Import-Module WebAdministration

# Check WSUS app pool
$pool = Get-WebAppPoolState -Name "WsusPool"
if ($pool.Value -ne "Started") {
    Write-Host "[WARNING] WsusPool is not running!" -ForegroundColor Red
    Start-WebAppPool -Name "WsusPool"
    Write-Host "Started WsusPool" -ForegroundColor Green
} else {
    Write-Host "[OK] WsusPool is running" -ForegroundColor Green
}

# Check all app pools
Get-WebAppPoolState | Format-Table
```

## 3. Restart WSUS Service

**Why**: Sometimes WSUS service needs restart to accept new clients

```powershell
# Restart WSUS service
Write-Host "Restarting WSUS service..." -ForegroundColor Yellow
Restart-Service WsusService -Force

# Wait for service to start
Start-Sleep -Seconds 10

# Verify it's running
$wsusService = Get-Service WsusService
Write-Host "WSUS Service Status: $($wsusService.Status)" -ForegroundColor Green

# Also restart IIS
iisreset /restart
```

## 4. Check WID (Windows Internal Database) Service

**Why**: WSUS stores client registrations in WID database

```powershell
# Check WID service
$widService = Get-Service "MSSQL`$MICROSOFT##WID"
Write-Host "WID Service Status: $($widService.Status)" -ForegroundColor $(if ($widService.Status -eq "Running") { "Green" } else { "Red" })

if ($widService.Status -ne "Running") {
    Write-Host "Starting WID service..." -ForegroundColor Yellow
    Start-Service "MSSQL`$MICROSOFT##WID"
    Start-Sleep -Seconds 10
    $widService = Get-Service "MSSQL`$MICROSOFT##WID"
    Write-Host "WID Service Status: $($widService.Status)" -ForegroundColor Green
}
```

## 5. Verify Firewall Rules

```powershell
# Check firewall rules for WSUS
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*WSUS*" } | Format-Table DisplayName, Enabled, Direction, Action

# If not found, create them:
New-NetFirewallRule -DisplayName "WSUS HTTP (8530)" -Direction Inbound -LocalPort 8530 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WSUS HTTPS (8531)" -Direction Inbound -LocalPort 8531 -Protocol TCP -Action Allow
```

## 6. Check WSUS Server Listening on Port 8530

```powershell
# Check if port 8530 is listening
$listening = Get-NetTCPConnection -LocalPort 8530 -ErrorAction SilentlyContinue

if ($listening) {
    Write-Host "[OK] WSUS is listening on port 8530" -ForegroundColor Green
    $listening | Format-Table LocalAddress, LocalPort, State
} else {
    Write-Host "[ERROR] WSUS is NOT listening on port 8530" -ForegroundColor Red
    Write-Host "Check IIS and WSUS service" -ForegroundColor Yellow
}
```

## 7. Check IIS Website for WSUS

```powershell
# Check IIS websites
Import-Module WebAdministration
Get-Website | Format-Table Name, State, Bindings

# Check WSUS Administration site
$wsusAdmin = Get-Website | Where-Object { $_.Name -like "*WSUS*" }
if ($wsusAdmin) {
    Write-Host "[OK] WSUS website found: $($wsusAdmin.Name)" -ForegroundColor Green
    Write-Host "State: $($wsusAdmin.State)" -ForegroundColor Green

    if ($wsusAdmin.State -ne "Started") {
        Write-Host "Starting WSUS website..." -ForegroundColor Yellow
        Start-Website -Name $wsusAdmin.Name
    }
} else {
    Write-Host "[WARNING] WSUS website not found" -ForegroundColor Yellow
}
```

## 8. Test WSUS Server from Server Itself

```powershell
# Test connection to self
Test-NetConnection -ComputerName localhost -Port 8530

# Try to access WSUS via PowerShell
try {
    [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()

    Write-Host "[OK] WSUS PowerShell connection successful" -ForegroundColor Green
    Write-Host "Server Name: $($wsus.Name)" -ForegroundColor Green
    Write-Host "Server Version: $($wsus.Version)" -ForegroundColor Green
    Write-Host "Port: $($wsus.PortNumber)" -ForegroundColor Green

    # Get computer statistics
    $computerScope = New-Object Microsoft.UpdateServices.Administration.ComputerTargetScope
    $computers = $wsus.GetComputerTargets($computerScope)
    Write-Host "Total Computers: $($computers.Count)" -ForegroundColor Cyan

    if ($computers.Count -gt 0) {
        Write-Host ""
        Write-Host "Registered Computers:" -ForegroundColor Cyan
        $computers | ForEach-Object {
            Write-Host "  - $($_.FullDomainName) (Last Contact: $($_.LastReportedStatusTime))" -ForegroundColor White
        }
    } else {
        Write-Host "No computers registered yet." -ForegroundColor Yellow
    }

} catch {
    Write-Host "[ERROR] Cannot connect to WSUS via PowerShell: $_" -ForegroundColor Red
    Write-Host "This is OK if GUI console works - it's a PowerShell API issue" -ForegroundColor Yellow
}
```

## 9. Check WSUS Synchronization Status

**Why**: WSUS must complete initial sync before clients can get updates

```powershell
# In WSUS console, check:
# - Synchronizations → Synchronization Status
# - Should show "Succeeded" with a recent date
# - If still synchronizing, wait for it to complete

# Via PowerShell (if working):
try {
    [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()
    $subscription = $wsus.GetSubscription()
    $syncStatus = $subscription.GetSynchronizationStatus()

    Write-Host "Synchronization Status: $syncStatus" -ForegroundColor Green
    Write-Host "Last Sync Time: $($subscription.LastSynchronizationTime)" -ForegroundColor Green
} catch {
    Write-Host "Check synchronization status in GUI console" -ForegroundColor Yellow
}
```

## 10. Common Issues and Solutions

### Issue: Clients don't appear even after 30 minutes

**Solution**:
1. Restart WSUS service on server
2. Restart IIS on server: `iisreset /restart`
3. Check IIS Application Pool is running (step 2 above)
4. On client, stop Windows Update service, delete cache, restart:
   ```powershell
   Stop-Service wuauserv
   Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Recurse -Force
   Start-Service wuauserv
   wuauclt /resetauthorization /detectnow /reportnow
   ```

### Issue: PowerShell API fails but GUI works

**This is OK** - it's a COM registration issue that doesn't affect functionality. The GUI console working means WSUS is functional.

### Issue: Port 8530 not listening

**Solution**:
1. Check IIS is running: `Get-Service W3SVC`
2. Check WSUS website is started (step 7 above)
3. Restart IIS: `iisreset /restart`
4. Check Windows Firewall isn't blocking port

---

## Quick Diagnostic Script for Server

Run this all-in-one check:

```powershell
Write-Host "=== WSUS Server Quick Diagnostic ===" -ForegroundColor Cyan
Write-Host ""

# 1. Services
Write-Host "[1] Services:" -ForegroundColor Yellow
Get-Service WsusService, "MSSQL`$MICROSOFT##WID", W3SVC | Format-Table Name, Status, StartType

# 2. Port
Write-Host "[2] Listening on port 8530:" -ForegroundColor Yellow
$port = Get-NetTCPConnection -LocalPort 8530 -ErrorAction SilentlyContinue
if ($port) { Write-Host "  [OK]" -ForegroundColor Green } else { Write-Host "  [FAILED]" -ForegroundColor Red }

# 3. IIS App Pool
Write-Host "[3] IIS Application Pools:" -ForegroundColor Yellow
Import-Module WebAdministration
Get-WebAppPoolState | Format-Table

# 4. Firewall
Write-Host "[4] Firewall Rules:" -ForegroundColor Yellow
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*WSUS*" -or $_.DisplayName -like "*8530*" } | Format-Table DisplayName, Enabled, Action

Write-Host ""
Write-Host "=== END ===" -ForegroundColor Cyan
```

---

## Next Steps After Fixing Server Issues

Once all server checks pass:
1. Wait 20-30 minutes for clients to appear
2. Check "Unassigned Computers" in WSUS console
3. If still not appearing, run client troubleshooting script on client
4. Check Windows Update logs on client (Get-WindowsUpdateLog)

---

**Last Updated**: February 5, 2026
