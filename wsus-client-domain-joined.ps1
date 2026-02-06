# WSUS Client Configuration for Domain-Joined Computers
# This script ensures domain-joined computers use WSUS via GPO
# Run this AFTER the Domain GPO is configured

$ErrorActionPreference = "Continue"
$LogFile = "C:\wsus-domain-client-setup.log"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

Write-Log "========================================="
Write-Log "WSUS Client Setup (Domain-Joined)"
Write-Log "========================================="
Write-Log ""

# Check if domain-joined
$computerSystem = Get-WmiObject -Class Win32_ComputerSystem
if (-not $computerSystem.PartOfDomain) {
    Write-Log "[ERROR] Computer is not domain-joined!"
    Write-Log "This script is for domain-joined computers only."
    exit 1
}

Write-Log "Domain: $($computerSystem.Domain)"
Write-Log "Computer: $($env:COMPUTERNAME)"
Write-Log ""

# Step 1: Force Group Policy update
Write-Log "[1] Forcing Group Policy update..."
gpupdate /force /wait:0
Start-Sleep -Seconds 10
Write-Log "  GPO updated"

# Step 2: Verify WSUS registry settings
Write-Log ""
Write-Log "[2] Verifying WSUS GPO settings..."
$wuServer = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue).WUServer
$wuStatus = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue).WUStatusServer

if ($wuServer -and $wuStatus) {
    Write-Log "  WUServer: $wuServer"
    Write-Log "  WUStatusServer: $wuStatus"
    Write-Log "  [OK] WSUS GPO is applied"
} else {
    Write-Log "  [ERROR] WSUS GPO not applied!"
    Write-Log "  Computer may not be in the correct OU"
    Write-Log "  Or GPO is not linked properly"
    exit 1
}

# Step 3: Stop Windows Update service
Write-Log ""
Write-Log "[3] Stopping Windows Update services..."
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
Stop-Service bits -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Write-Log "  Services stopped"

# Step 4: Delete SusClientID to force re-registration
Write-Log ""
Write-Log "[4] Deleting SusClientID (force new registration)..."
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name "SusClientId" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name "SusClientIdValidation" -ErrorAction SilentlyContinue
Write-Log "  SusClientID deleted"

# Step 5: Clear Windows Update cache
Write-Log ""
Write-Log "[5] Clearing Windows Update cache..."
Remove-Item "C:\Windows\SoftwareDistribution\DataStore\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
Write-Log "  Cache cleared"

# Step 6: Start services
Write-Log ""
Write-Log "[6] Starting Windows Update service..."
Set-Service -Name wuauserv -StartupType Automatic
Set-Service -Name bits -StartupType Automatic
Start-Service bits -ErrorAction SilentlyContinue
Start-Service wuauserv
Start-Sleep -Seconds 5
Write-Log "  Services started"

# Step 7: Check ServerSelection
Write-Log ""
Write-Log "[7] Checking Windows Update configuration..."
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $serverSelection = $updateSearcher.ServerSelection

    Write-Log "  ServerSelection: $serverSelection"

    if ($serverSelection -eq 1) {
        Write-Log "  [OK] Windows Update is using WSUS!"
    } elseif ($serverSelection -eq 0) {
        Write-Log "  [INFO] ServerSelection is 0 - reboot required"
        Write-Log "  Computer will use WSUS after next reboot"
    }
} catch {
    Write-Log "  [WARNING] Could not check ServerSelection: $_"
}

# Step 8: Force detection and reporting
Write-Log ""
Write-Log "[8] Triggering Windows Update detection..."
wuauclt /resetauthorization
Start-Sleep -Seconds 2
wuauclt /detectnow
Start-Sleep -Seconds 2
wuauclt /reportnow

# For Windows Server 2016+
$osVersion = [System.Environment]::OSVersion.Version
if ($osVersion.Major -ge 10) {
    usoclient StartScan
    usoclient RefreshSettings
}

Write-Log "  Detection triggered"

Write-Log ""
Write-Log "========================================="
Write-Log "SETUP COMPLETE"
Write-Log "========================================="
Write-Log ""
Write-Log "Next Steps:"
Write-Log "  1. If ServerSelection was 0, reboot the computer"
Write-Log "  2. After reboot, client will appear in WSUS console"
Write-Log "  3. Check WSUS Console > Computers > Unassigned Computers"
Write-Log "  4. Client should appear within 10-15 minutes"
Write-Log ""
Write-Log "To check if reboot is needed:"
Write-Log '  $s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()'
Write-Log '  if ($s.ServerSelection -eq 0) { Write-Host "Reboot required" }'
Write-Log ""

# Create a flag file to indicate setup completed
"Setup completed at $(Get-Date)" | Out-File "C:\wsus-setup-completed.txt"

Write-Log "Log file: $LogFile"
Write-Log ""
