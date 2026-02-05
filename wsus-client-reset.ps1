<powershell>
# WSUS Client Reset and Force Registration Script
# Run this script on a client to force re-registration with WSUS server
# Use this for troubleshooting when client doesn't appear in WSUS console

# Requires Administrator privileges
#Requires -RunAsAdministrator

# Set error handling
$ErrorActionPreference = "Continue"

# Create log file
$LogFile = "C:\wsus-client-reset.log"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

Write-Log "========================================="
Write-Log "WSUS Client Reset and Registration Tool"
Write-Log "========================================="
Write-Log ""

try {
    # Display current configuration
    Write-Log "Current WSUS Configuration:"
    Write-Log "----------------------------"

    $wuServer = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer" -ErrorAction SilentlyContinue).WUServer
    $wuStatusServer = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUStatusServer" -ErrorAction SilentlyContinue).WUStatusServer
    $useWUServer = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "UseWUServer" -ErrorAction SilentlyContinue).UseWUServer

    if ($wuServer) {
        Write-Log "WUServer: $wuServer"
        Write-Log "WUStatusServer: $wuStatusServer"
        Write-Log "UseWUServer: $useWUServer"

        # Test connectivity to WSUS server
        if ($wuServer -match "http://([^:]+):(\d+)") {
            $wsusHost = $matches[1]
            $wsusPort = $matches[2]

            Write-Log ""
            Write-Log "Testing connectivity to WSUS server..."
            $connection = Test-NetConnection -ComputerName $wsusHost -Port $wsusPort -InformationLevel Detailed -WarningAction SilentlyContinue

            if ($connection.TcpTestSucceeded) {
                Write-Log "✓ Successfully connected to $wsusHost on port $wsusPort"
            } else {
                Write-Log "✗ FAILED to connect to $wsusHost on port $wsusPort"
                Write-Log "  Please check network connectivity and firewall rules."
            }
        }
    } else {
        Write-Log "✗ WSUS server is NOT configured (WUServer registry key missing)"
        Write-Log "  Please configure WSUS via GPO or run wsus-client-userdata.ps1"
        exit 1
    }

    Write-Log ""
    Write-Log "Starting WSUS client reset..."
    Write-Log "----------------------------"

    # Stop Windows Update service
    Write-Log "1. Stopping Windows Update service..."
    Stop-Service -Name wuauserv -Force
    Write-Log "   Service stopped."

    # Stop BITS service
    Write-Log "2. Stopping BITS service..."
    Stop-Service -Name BITS -Force -ErrorAction SilentlyContinue
    Write-Log "   Service stopped."

    # Remove WSUS client SusClientId (forces new registration)
    Write-Log "3. Removing old WSUS client ID..."
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate") {
        Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Recurse -Force
        Write-Log "   Client ID removed."
    } else {
        Write-Log "   No existing client ID found."
    }

    # Clear Software Distribution folder (optional - clears pending downloads)
    Write-Log "4. Clearing Windows Update cache..."
    $softwareDistPath = "C:\Windows\SoftwareDistribution"

    # Backup and clear DataStore (WSUS database)
    $dataStorePath = Join-Path $softwareDistPath "DataStore"
    if (Test-Path $dataStorePath) {
        Get-ChildItem -Path $dataStorePath -Recurse -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Log "   DataStore cleared."
    }

    # Clear Download folder
    $downloadPath = Join-Path $softwareDistPath "Download"
    if (Test-Path $downloadPath) {
        Get-ChildItem -Path $downloadPath -Recurse -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Log "   Download cache cleared."
    }

    # Start services
    Write-Log "5. Starting Windows Update service..."
    Start-Service -Name wuauserv
    Start-Sleep -Seconds 3
    Write-Log "   Service started."

    Write-Log "6. Starting BITS service..."
    Start-Service -Name BITS -ErrorAction SilentlyContinue
    Write-Log "   Service started."

    Write-Log ""
    Write-Log "Forcing WSUS registration and detection..."
    Write-Log "----------------------------"

    # Reset Windows Update authorization
    Write-Log "7. Resetting Windows Update authorization..."
    Start-Process -FilePath "wuauclt.exe" -ArgumentList "/resetauthorization" -NoNewWindow -Wait
    Start-Sleep -Seconds 3
    Write-Log "   Authorization reset."

    # Force detection
    Write-Log "8. Triggering update detection..."
    Start-Process -FilePath "wuauclt.exe" -ArgumentList "/detectnow" -NoNewWindow
    Start-Sleep -Seconds 3
    Write-Log "   Detection triggered."

    # Report to WSUS server
    Write-Log "9. Reporting to WSUS server..."
    Start-Process -FilePath "wuauclt.exe" -ArgumentList "/reportnow" -NoNewWindow
    Start-Sleep -Seconds 3
    Write-Log "   Report sent."

    # For Windows 10/Server 2016 and later
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -ge 10) {
        Write-Log "10. Using UsoClient (Windows 10/Server 2016+)..."

        # Refresh settings
        Start-Process -FilePath "usoclient.exe" -ArgumentList "RefreshSettings" -NoNewWindow -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Start scan
        Start-Process -FilePath "usoclient.exe" -ArgumentList "StartScan" -NoNewWindow -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3

        # Start interactive scan
        Start-Process -FilePath "usoclient.exe" -ArgumentList "ScanInstallWait" -NoNewWindow -ErrorAction SilentlyContinue

        Write-Log "    UsoClient commands executed."
    }

    Write-Log ""
    Write-Log "========================================="
    Write-Log "WSUS Client Reset Complete!"
    Write-Log "========================================="
    Write-Log ""
    Write-Log "What happens next:"
    Write-Log "- The client will register with WSUS server"
    Write-Log "- This may take 10-15 minutes"
    Write-Log "- Check the WSUS console: Computers > All Computers"
    Write-Log ""
    Write-Log "To verify immediately:"
    Write-Log "1. Check Windows Update service: Get-Service wuauserv"
    Write-Log "2. View registry: reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    Write-Log "3. Generate update log: Get-WindowsUpdateLog (may take a few minutes)"
    Write-Log "4. Check Windows Update: Settings > Update & Security > Windows Update"
    Write-Log ""
    Write-Log "Troubleshooting:"
    Write-Log "- If client still doesn't appear, check WSUS server logs"
    Write-Log "- Verify firewall allows port 8530 to WSUS server"
    Write-Log "- Ensure GPO is applied: gpupdate /force, then gpresult /r"
    Write-Log "- Check event logs: Event Viewer > Applications and Services > Microsoft > Windows > WindowsUpdateClient"
    Write-Log ""
    Write-Log "Log file saved to: $LogFile"
    Write-Log "========================================="

    # Generate detailed diagnostics
    Write-Log ""
    Write-Log "Collecting diagnostics..."

    # Get Windows Update service status
    $wuService = Get-Service -Name wuauserv
    Write-Log "Windows Update Service: $($wuService.Status)"

    # Get BITS service status
    $bitsService = Get-Service -Name BITS
    Write-Log "BITS Service: $($bitsService.Status)"

    # Check for pending reboots
    $pendingReboot = $false
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $pendingReboot = $true
    }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $pendingReboot = $true
    }

    if ($pendingReboot) {
        Write-Log "⚠ WARNING: System has pending reboot. Please restart the computer."
    } else {
        Write-Log "System reboot: Not required"
    }

    # Save full diagnostic report
    $diagnosticsReport = @"
WSUS Client Diagnostics Report
Generated: $(Get-Date)
Computer: $(hostname)
========================================

Registry Configuration:
-----------------------
WUServer: $wuServer
WUStatusServer: $wuStatusServer
UseWUServer: $useWUServer

Service Status:
--------------
Windows Update (wuauserv): $($wuService.Status)
BITS: $($bitsService.Status)

System Information:
------------------
OS Version: $($osVersion.Major).$($osVersion.Minor).$($osVersion.Build)
Computer Name: $(hostname)
Domain: $($env:USERDNSDOMAIN)
IP Address: $(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" | Select-Object -First 1 -ExpandProperty IPAddress)

Pending Reboot: $pendingReboot

Actions Performed:
-----------------
1. Stopped Windows Update and BITS services
2. Removed old WSUS client ID
3. Cleared Windows Update cache
4. Restarted services
5. Reset Windows Update authorization
6. Triggered update detection
7. Sent report to WSUS server
8. Executed UsoClient commands (if applicable)

Next Steps:
----------
1. Wait 10-15 minutes for client to appear in WSUS console
2. Check WSUS console: Update Services > Computers > All Computers
3. Look for computer name: $(hostname)

If client doesn't appear:
------------------------
1. Verify network connectivity: Test-NetConnection $wsusHost -Port $wsusPort
2. Check WSUS server is running: Get-Service WsusService (on WSUS server)
3. Review Windows Update logs: Get-WindowsUpdateLog
4. Check Event Viewer for errors
5. Ensure GPO is applied: gpresult /r

Log file: $LogFile
========================================
"@

    $diagnosticsReport | Out-File "C:\WSUS-Client-Diagnostics.txt"
    Write-Log ""
    Write-Log "Full diagnostics saved to: C:\WSUS-Client-Diagnostics.txt"

} catch {
    Write-Log ""
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)"
    Write-Log ""
    Write-Log "The script encountered an error. Please:"
    Write-Log "1. Ensure you're running as Administrator"
    Write-Log "2. Check that WSUS is configured (registry keys exist)"
    Write-Log "3. Review the error message above"
    throw
}

Write-Log ""
Write-Log "Script execution completed."
</powershell>
