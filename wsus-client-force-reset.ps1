# WSUS Client Force Reset and Registration
# Run this on CLIENT to completely reset and force registration

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "WSUS Client Force Reset & Registration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$WSUSServer = "10.50.5.96"
$WSUSPort = "8530"

# Step 1: Stop Windows Update service
Write-Host "[1] Stopping Windows Update service..." -ForegroundColor Yellow
Stop-Service wuauserv -Force
Start-Sleep -Seconds 3
Write-Host "  Service stopped" -ForegroundColor Green

# Step 2: Delete SusClientID (forces new registration)
Write-Host "[2] Deleting SusClientID (force new registration)..." -ForegroundColor Yellow
$susClientIdPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate"
Remove-ItemProperty -Path $susClientIdPath -Name "SusClientId" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $susClientIdPath -Name "SusClientIdValidation" -ErrorAction SilentlyContinue
Write-Host "  SusClientID deleted" -ForegroundColor Green

# Step 3: Clear Windows Update cache
Write-Host "[3] Clearing Windows Update cache..." -ForegroundColor Yellow
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\SoftwareDistribution\DataStore\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  Cache cleared" -ForegroundColor Green

# Step 4: Re-create registry keys
Write-Host "[4] Re-creating registry configuration..." -ForegroundColor Yellow

$registryPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
)

foreach ($path in $registryPaths) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }
}

$wsusURL = "http://${WSUSServer}:${WSUSPort}"

# WSUS Server settings
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer" -Value $wsusURL -Type String
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUStatusServer" -Value $wsusURL -Type String

# Auto Update settings
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "UseWUServer" -Value 1 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value 0 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Value 4 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ScheduledInstallDay" -Value 0 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ScheduledInstallTime" -Value 3 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "DetectionFrequencyEnabled" -Value 1 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "DetectionFrequency" -Value 1 -Type DWord  # Changed to 1 hour for faster detection

Write-Host "  Registry configured" -ForegroundColor Green

# Step 5: Set service to Automatic and start
Write-Host "[5] Starting Windows Update service..." -ForegroundColor Yellow
Set-Service -Name wuauserv -StartupType Automatic
Start-Service -Name wuauserv
Start-Sleep -Seconds 5

$service = Get-Service -Name wuauserv
Write-Host "  Service Status: $($service.Status)" -ForegroundColor Green
Write-Host "  Service StartType: $($service.StartType)" -ForegroundColor Green

# Step 6: Reset Windows Update components
Write-Host "[6] Resetting Windows Update components..." -ForegroundColor Yellow
wuauclt /resetauthorization
Start-Sleep -Seconds 3
Write-Host "  Authorization reset" -ForegroundColor Green

# Step 7: Force immediate detection
Write-Host "[7] Forcing immediate detection and reporting..." -ForegroundColor Yellow
wuauclt /detectnow
Start-Sleep -Seconds 2
wuauclt /reportnow
Start-Sleep -Seconds 2

# For Windows 10/Server 2016+
$osVersion = [System.Environment]::OSVersion.Version
if ($osVersion.Major -ge 10) {
    usoclient StartScan
    Start-Sleep -Seconds 2
    usoclient RefreshSettings
    Start-Sleep -Seconds 2
}

Write-Host "  Detection triggered" -ForegroundColor Green

# Step 8: Verify connectivity
Write-Host "[8] Verifying connectivity..." -ForegroundColor Yellow
$connection = Test-NetConnection -ComputerName $WSUSServer -Port $WSUSPort
if ($connection.TcpTestSucceeded) {
    Write-Host "  [OK] Connected to ${WSUSServer}:${WSUSPort}" -ForegroundColor Green
} else {
    Write-Host "  [FAILED] Cannot connect to ${WSUSServer}:${WSUSPort}" -ForegroundColor Red
    Write-Host "  Check network and firewall settings" -ForegroundColor Red
}

# Step 9: Check Windows Update log for errors
Write-Host "[9] Checking Windows Update log for errors..." -ForegroundColor Yellow
Write-Host "  Generating log (this takes 1-2 minutes)..." -ForegroundColor DarkGray

try {
    Get-WindowsUpdateLog -ErrorAction Stop | Out-Null
    $logPath = "$env:USERPROFILE\Desktop\WindowsUpdate.log"

    if (Test-Path $logPath) {
        # Get last 100 lines
        $lastLines = Get-Content $logPath -Tail 100

        # Look for errors
        $errors = $lastLines | Select-String -Pattern "ERROR|FAILED|0x8024"
        if ($errors) {
            Write-Host ""
            Write-Host "  [WARNING] Errors found in log:" -ForegroundColor Red
            $errors | Select-Object -First 10 | ForEach-Object {
                Write-Host "    $_" -ForegroundColor Red
            }
        } else {
            Write-Host "  [OK] No errors in recent log" -ForegroundColor Green
        }

        # Look for WSUS server contact
        $wsusContact = $lastLines | Select-String -Pattern "10.50.5.96|WSUS server" | Select-Object -Last 5
        if ($wsusContact) {
            Write-Host ""
            Write-Host "  Recent WSUS server contact:" -ForegroundColor Cyan
            $wsusContact | ForEach-Object {
                Write-Host "    $_" -ForegroundColor White
            }
        }
    }
} catch {
    Write-Host "  [WARNING] Could not generate log: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RESET COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Actions taken:" -ForegroundColor Yellow
Write-Host "  1. Stopped Windows Update service" -ForegroundColor White
Write-Host "  2. Deleted SusClientID (forces new client registration)" -ForegroundColor White
Write-Host "  3. Cleared all Windows Update cache" -ForegroundColor White
Write-Host "  4. Re-configured registry with WSUS settings" -ForegroundColor White
Write-Host "  5. Started Windows Update service" -ForegroundColor White
Write-Host "  6. Reset authorization" -ForegroundColor White
Write-Host "  7. Forced detection and reporting" -ForegroundColor White
Write-Host "  8. Detection frequency set to 1 hour (faster)" -ForegroundColor White
Write-Host ""
Write-Host "Computer Name: $(hostname)" -ForegroundColor Cyan
Write-Host "WSUS Server: http://${WSUSServer}:${WSUSPort}" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Client should contact WSUS server within 5-10 minutes" -ForegroundColor White
Write-Host "  2. Check WSUS Console > Computers > Unassigned Computers" -ForegroundColor White
Write-Host "  3. If not appearing after 15 minutes, check server logs" -ForegroundColor White
Write-Host ""
Write-Host "To monitor in real-time, run:" -ForegroundColor Yellow
Write-Host '  Get-WinEvent -LogName "System" -MaxEvents 10 | Where-Object { $_.ProviderName -like "*WindowsUpdate*" }' -ForegroundColor DarkGray
Write-Host ""
