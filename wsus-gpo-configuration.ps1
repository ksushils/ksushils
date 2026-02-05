<powershell>
# WSUS Group Policy Configuration Script
# Run this script on your Domain Controller to create and configure WSUS GPO
# This script creates a GPO for WSUS client configuration and links it to specified OUs

# Set error handling
$ErrorActionPreference = "Stop"

# ===== CONFIGURATION =====
# Change these to match your environment
$WSUSServer = "10.50.5.96"               # Your WSUS server IP or hostname
$WSUSPort = "8530"                        # WSUS HTTP port
$GPOName = "WSUS Client Configuration"    # Name of the GPO to create
$TargetOU = "OU=Computers,DC=yourdomain,DC=com"  # OU to link the GPO (change this!)
# Example: "OU=Servers,DC=contoso,DC=local"
# Example: "DC=contoso,DC=local" for entire domain
# =========================

# Create log file
$LogFile = "C:\wsus-gpo-setup.log"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

Write-Log "Starting WSUS GPO Configuration..."
Write-Log "GPO Name: $GPOName"
Write-Log "WSUS Server: http://${WSUSServer}:${WSUSPort}"
Write-Log "Target OU: $TargetOU"

try {
    # Import Group Policy module
    Write-Log "Importing GroupPolicy module..."
    Import-Module GroupPolicy -ErrorAction Stop

    # Get domain information
    $domain = Get-ADDomain
    Write-Log "Domain: $($domain.DNSRoot)"

    # Check if GPO already exists
    $existingGPO = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
    if ($existingGPO) {
        Write-Log "GPO '$GPOName' already exists. Updating configuration..."
        $gpo = $existingGPO
    } else {
        # Create new GPO
        Write-Log "Creating new GPO: $GPOName"
        $gpo = New-GPO -Name $GPOName -Comment "WSUS client configuration for Windows Update management"
        Write-Log "GPO created successfully."
    }

    # Configure WSUS settings in the GPO
    Write-Log "Configuring WSUS policy settings..."

    # Set WSUS server location
    Write-Log "Setting 'Specify intranet Microsoft update service location'..."
    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" `
        -ValueName "WUServer" -Type String -Value "http://${WSUSServer}:${WSUSPort}"

    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" `
        -ValueName "WUStatusServer" -Type String -Value "http://${WSUSServer}:${WSUSPort}"

    # Enable WSUS server usage
    Write-Log "Enabling 'Use WSUS Server'..."
    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -ValueName "UseWUServer" -Type DWord -Value 1

    # Configure Automatic Updates
    Write-Log "Configuring Automatic Updates..."

    # AUOptions: 4 = Auto download and schedule install
    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -ValueName "AUOptions" -Type DWord -Value 4

    # Disable NoAutoUpdate to ensure automatic updates are enabled
    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -ValueName "NoAutoUpdate" -Type DWord -Value 0

    # Schedule install day (0 = Every day)
    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -ValueName "ScheduledInstallDay" -Type DWord -Value 0

    # Schedule install time (3 = 3 AM)
    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -ValueName "ScheduledInstallTime" -Type DWord -Value 3

    # Set detection frequency
    Write-Log "Setting detection frequency to 4 hours..."
    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -ValueName "DetectionFrequencyEnabled" -Type DWord -Value 1

    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -ValueName "DetectionFrequency" -Type DWord -Value 4

    # Prevent auto-restart with logged-on users
    Write-Log "Configuring restart policy..."
    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -ValueName "NoAutoRebootWithLoggedOnUsers" -Type DWord -Value 1

    # Enable recommended updates
    Write-Log "Enabling recommended updates..."
    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -ValueName "IncludeRecommendedUpdates" -Type DWord -Value 1

    # Configure re-prompt for restart
    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -ValueName "RebootRelaunchTimeoutEnabled" -Type DWord -Value 1

    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -ValueName "RebootRelaunchTimeout" -Type DWord -Value 240  # 240 minutes = 4 hours

    # Allow auto update immediate installation
    Set-GPRegistryValue -Name $GPOName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -ValueName "AutoInstallMinorUpdates" -Type DWord -Value 1

    Write-Log "WSUS policy settings configured successfully."

    # Link GPO to target OU
    Write-Log "Linking GPO to OU: $TargetOU"
    try {
        # Check if link already exists
        $existingLink = Get-GPInheritance -Target $TargetOU | Select-Object -ExpandProperty GpoLinks |
            Where-Object { $_.DisplayName -eq $GPOName }

        if ($existingLink) {
            Write-Log "GPO is already linked to $TargetOU"
        } else {
            New-GPLink -Name $GPOName -Target $TargetOU -LinkEnabled Yes
            Write-Log "GPO linked successfully to $TargetOU"
        }
    } catch {
        Write-Log "Error linking GPO to OU: $_"
        Write-Log "You may need to manually link the GPO to the desired OU."
    }

    # Set GPO to apply only to computer objects
    Write-Log "Configuring GPO security filtering..."
    Set-GPPermission -Name $GPOName -TargetName "Authenticated Users" -TargetType Group -PermissionLevel GpoRead
    Set-GPPermission -Name $GPOName -TargetName "Domain Computers" -TargetType Group -PermissionLevel GpoApply

    # Generate GPO report
    Write-Log "Generating GPO report..."
    $reportPath = "C:\WSUS-GPO-Report.html"
    Get-GPOReport -Name $GPOName -ReportType Html -Path $reportPath
    Write-Log "GPO report saved to: $reportPath"

    # Output summary
    Write-Log "================================"
    Write-Log "WSUS GPO Configuration Complete!"
    Write-Log "================================"
    Write-Log "GPO Name: $GPOName"
    Write-Log "WSUS Server: http://${WSUSServer}:${WSUSPort}"
    Write-Log "Linked to: $TargetOU"
    Write-Log ""
    Write-Log "Configuration Details:"
    Write-Log "- WSUS Server: http://${WSUSServer}:${WSUSPort}"
    Write-Log "- Auto Updates: Enabled (Download and schedule install)"
    Write-Log "- Install Schedule: Daily at 3:00 AM"
    Write-Log "- Detection Frequency: Every 4 hours"
    Write-Log "- Auto-restart with logged on users: Disabled"
    Write-Log "- Restart re-prompt: Every 4 hours"
    Write-Log ""
    Write-Log "Next Steps:"
    Write-Log "1. Run 'gpupdate /force' on client computers"
    Write-Log "2. Verify with: gpresult /r or rsop.msc"
    Write-Log "3. Check registry: reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    Write-Log "4. Monitor WSUS console for client check-ins (10-15 minutes)"
    Write-Log "================================"

    # Create summary file
    @"
WSUS Group Policy Configuration Summary
========================================
Domain: $($domain.DNSRoot)
GPO Name: $GPOName
WSUS Server: http://${WSUSServer}:${WSUSPort}
Target OU: $TargetOU
Configuration Date: $(Get-Date)

GPO Settings Applied:
---------------------
Computer Configuration > Policies > Administrative Templates > Windows Components > Windows Update

1. Specify intranet Microsoft update service location
   - Status: Enabled
   - Update service: http://${WSUSServer}:${WSUSPort}
   - Statistics server: http://${WSUSServer}:${WSUSPort}

2. Configure Automatic Updates
   - Status: Enabled
   - Option: 4 - Auto download and schedule the install
   - Scheduled install day: 0 (Every day)
   - Scheduled install time: 03:00

3. Automatic Updates detection frequency
   - Status: Enabled
   - Check interval: 4 hours

4. No auto-restart with logged on users for scheduled installations
   - Status: Enabled

5. Include recommended updates
   - Status: Enabled

6. Re-prompt for restart with scheduled installations
   - Status: Enabled
   - Wait time: 240 minutes (4 hours)

7. Allow Automatic Updates immediate installation
   - Status: Enabled

How to Verify on Clients:
-------------------------
1. Force Group Policy update:
   gpupdate /force

2. Check applied policies:
   gpresult /r
   or
   rsop.msc

3. Verify registry settings:
   reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate

4. Check Windows Update service:
   Get-Service wuauserv

5. Force WSUS detection:
   wuauclt /resetauthorization /detectnow
   wuauclt /reportnow

6. Check WSUS console:
   Update Services > Computers > All Computers
   (Client will appear within 10-15 minutes)

Troubleshooting:
---------------
- If GPO not applying: Check GPO link order and inheritance
- If clients not reporting: Check firewall port 8530 on WSUS server
- If registry empty: Verify GPO scope and security filtering
- For logging: Get-WindowsUpdateLog (PowerShell on client)

Additional Commands:
-------------------
View GPO settings:
  Get-GPO -Name "$GPOName" | Format-List

View GPO links:
  Get-GPInheritance -Target "$TargetOU"

Remove GPO link (if needed):
  Remove-GPLink -Name "$GPOName" -Target "$TargetOU"

Delete GPO (if needed):
  Remove-GPO -Name "$GPOName"

GPO Report Location: $reportPath
========================================
"@ | Out-File "C:\WSUS-GPO-Configuration.txt"

    Write-Log "Configuration summary saved to C:\WSUS-GPO-Configuration.txt"

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)"
    Write-Log ""
    Write-Log "Common issues:"
    Write-Log "- Make sure you're running this on a Domain Controller"
    Write-Log "- Verify the TargetOU path is correct"
    Write-Log "- Ensure you have Domain Admin privileges"
    throw
}

Write-Log "Script execution completed."
</powershell>
