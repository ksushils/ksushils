<powershell>
# WSUS Client Configuration - EC2 User Data Script
# This script configures a Windows EC2 instance to use WSUS for updates

# Set error handling
$ErrorActionPreference = "Stop"

# ===== CONFIGURATION =====
# Change this to your WSUS server IP or hostname
$WSUSServer = "10.50.5.96"  # Replace with your WSUS server IP
$WSUSPort = "8530"           # Default HTTP port
# =========================

# Create log file
$LogFile = "C:\wsus-client-setup.log"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

Write-Log "Starting WSUS Client Configuration..."
Write-Log "WSUS Server: http://${WSUSServer}:${WSUSPort}"

try {
    # Test connectivity to WSUS server
    Write-Log "Testing connectivity to WSUS server..."
    $connection = Test-NetConnection -ComputerName $WSUSServer -Port $WSUSPort -InformationLevel Quiet
    if (-not $connection) {
        Write-Log "WARNING: Cannot reach WSUS server at ${WSUSServer}:${WSUSPort}"
        Write-Log "Continuing with configuration anyway..."
    } else {
        Write-Log "Successfully connected to WSUS server."
    }

    # Configure registry settings for WSUS
    Write-Log "Configuring Windows Update registry settings..."

    # Create registry paths if they don't exist
    $registryPaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    )

    foreach ($path in $registryPaths) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
            Write-Log "Created registry path: $path"
        }
    }

    # Set WSUS server locations
    $wsusURL = "http://${WSUSServer}:${WSUSPort}"

    Write-Log "Setting WUServer to: $wsusURL"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer" -Value $wsusURL -Type String

    Write-Log "Setting WUStatusServer to: $wsusURL"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUStatusServer" -Value $wsusURL -Type String

    # Configure to use WSUS server
    Write-Log "Enabling WSUS server usage..."
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "UseWUServer" -Value 1 -Type DWord

    # Configure Automatic Updates
    Write-Log "Configuring Automatic Updates..."

    # AUOptions: 4 = Auto download and schedule the install
    # 2 = Notify before download
    # 3 = Auto download and notify for install
    # 4 = Auto download and schedule the install
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Value 4 -Type DWord

    # Schedule install day (0 = Every day, 1-7 = Sunday-Saturday)
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ScheduledInstallDay" -Value 0 -Type DWord

    # Schedule install time (0-23 hours, 3 = 3 AM)
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ScheduledInstallTime" -Value 3 -Type DWord

    # Disable automatic restarts with logged-on users
    Write-Log "Configuring restart policy..."
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord

    # Set detection frequency (in hours)
    Write-Log "Setting detection frequency to 4 hours..."
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "DetectionFrequencyEnabled" -Value 1 -Type DWord
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "DetectionFrequency" -Value 4 -Type DWord

    # Enable recommended updates
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "IncludeRecommendedUpdates" -Value 1 -Type DWord

    # Disable auto-restart for scheduled installations
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord

    Write-Log "Registry configuration completed."

    # Verify registry settings
    Write-Log "Verifying registry settings..."
    $wuServer = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer" -ErrorAction SilentlyContinue
    $wuStatusServer = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUStatusServer" -ErrorAction SilentlyContinue
    $useWUServer = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "UseWUServer" -ErrorAction SilentlyContinue

    Write-Log "WUServer: $($wuServer.WUServer)"
    Write-Log "WUStatusServer: $($wuStatusServer.WUStatusServer)"
    Write-Log "UseWUServer: $($useWUServer.UseWUServer)"

    # Stop Windows Update service
    Write-Log "Stopping Windows Update service..."
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Clear Windows Update cache to force fresh registration
    Write-Log "Clearing Windows Update cache..."
    Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Recurse -Force -ErrorAction SilentlyContinue

    # Clear SoftwareDistribution folder (optional - removes pending downloads)
    # Uncomment the next two lines if you want to clear the download cache
    # Write-Log "Clearing SoftwareDistribution folder..."
    # Remove-Item "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue

    # Start Windows Update service
    Write-Log "Starting Windows Update service..."
    Start-Service -Name wuauserv
    Start-Sleep -Seconds 3

    # Force Windows Update to detect WSUS server
    Write-Log "Forcing Windows Update detection..."

    # Reset authorization
    Write-Log "Resetting Windows Update authorization..."
    Start-Process -FilePath "wuauclt.exe" -ArgumentList "/resetauthorization" -NoNewWindow -Wait
    Start-Sleep -Seconds 2

    # Detect updates now
    Write-Log "Triggering update detection..."
    Start-Process -FilePath "wuauclt.exe" -ArgumentList "/detectnow" -NoNewWindow
    Start-Sleep -Seconds 2

    # Report to WSUS server
    Write-Log "Reporting to WSUS server..."
    Start-Process -FilePath "wuauclt.exe" -ArgumentList "/reportnow" -NoNewWindow

    # For Windows Server 2016 and later, also use UsoClient
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -ge 10) {
        Write-Log "Using UsoClient for detection (Windows 10/Server 2016+)..."
        Start-Process -FilePath "usoclient.exe" -ArgumentList "StartScan" -NoNewWindow -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process -FilePath "usoclient.exe" -ArgumentList "RefreshSettings" -NoNewWindow -ErrorAction SilentlyContinue
    }

    Write-Log "Initial detection triggered."

    # Create a scheduled task to ensure reporting (runs every 6 hours)
    Write-Log "Creating scheduled task for periodic WSUS reporting..."
    $action = New-ScheduledTaskAction -Execute "wuauclt.exe" -Argument "/reportnow /detectnow"
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration ([TimeSpan]::MaxValue)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName "WSUS Client Reporting" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Periodic WSUS client reporting task" -Force

    Write-Log "Scheduled task created."

    # Output configuration summary
    Write-Log "================================"
    Write-Log "WSUS Client Configuration Complete!"
    Write-Log "================================"
    Write-Log "Computer Name: $(hostname)"
    Write-Log "WSUS Server: http://${WSUSServer}:${WSUSPort}"
    Write-Log ""
    Write-Log "Configuration Details:"
    Write-Log "- Auto Updates: Enabled (Download and schedule install)"
    Write-Log "- Install Schedule: Daily at 3:00 AM"
    Write-Log "- Detection Frequency: Every 4 hours"
    Write-Log "- No auto-restart with logged on users"
    Write-Log ""
    Write-Log "The client will appear in WSUS console within 10-15 minutes."
    Write-Log "Check: WSUS Console > Computers > All Computers"
    Write-Log "================================"

    # Create configuration summary file
    @"
WSUS Client Configuration Summary
==================================
Computer Name: $(hostname)
IP Address: $(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" | Select-Object -First 1 -ExpandProperty IPAddress)
WSUS Server: http://${WSUSServer}:${WSUSPort}
Configuration Date: $(Get-Date)

Registry Settings:
- WUServer: http://${WSUSServer}:${WSUSPort}
- WUStatusServer: http://${WSUSServer}:${WSUSPort}
- UseWUServer: Enabled

Automatic Updates Configuration:
- AUOptions: 4 (Auto download and schedule install)
- Schedule: Daily at 3:00 AM
- Detection Frequency: Every 4 hours
- Auto-restart with logged on users: Disabled

Scheduled Tasks:
- WSUS Client Reporting: Every 6 hours

To verify client registration:
1. Run: wuauclt /detectnow /reportnow
2. Check WSUS console on server (may take 10-15 minutes)
3. Check Windows Update log: Get-WindowsUpdateLog (PowerShell)

Troubleshooting:
- Test connectivity: Test-NetConnection ${WSUSServer} -Port ${WSUSPort}
- View registry: reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
- Check service: Get-Service wuauserv
"@ | Out-File "C:\WSUS-Client-Configuration.txt"

    Write-Log "Configuration summary saved to C:\WSUS-Client-Configuration.txt"

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)"
    throw
}

Write-Log "Script execution completed successfully."
</powershell>
