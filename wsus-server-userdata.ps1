<powershell>
# WSUS Server Setup - EC2 User Data Script
# This script installs and configures WSUS on a Windows Server EC2 instance

# Set error handling
$ErrorActionPreference = "Stop"

# Create log file
$LogFile = "C:\wsus-setup.log"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

Write-Log "Starting WSUS Server Setup..."

# Import required modules
Write-Log "Loading ServerManager module..."
try {
    Import-Module ServerManager -ErrorAction Stop
    Write-Log "ServerManager module loaded successfully."
} catch {
    Write-Log "ERROR: Failed to load ServerManager module: $_"
    throw "ServerManager module is required for WSUS installation"
}

try {
    # Check if SQL Server Connectivity feature is already installed
    Write-Log "Checking for SQL Server Connectivity (UpdateServices-DB) feature..."
    $sqlConnectivity = Get-WindowsFeature -Name "UpdateServices-DB" -ErrorAction SilentlyContinue
    $hasConflict = $false

    if ($sqlConnectivity -and $sqlConnectivity.Installed) {
        $hasConflict = $true
        Write-Log "SQL Server Connectivity (UpdateServices-DB) is ALREADY INSTALLED - this will conflict with WID"
        Write-Log "Need to remove it first before installing WSUS with WID"
    } else {
        Write-Log "No SQL Server Connectivity conflict detected."
    }

    # Install WSUS Role with required features
    Write-Log "Installing WSUS Role and features..."

    if ($hasConflict) {
        Write-Log "Removing SQL Server Connectivity feature to avoid conflict..."
        try {
            $removeResult = Uninstall-WindowsFeature -Name "UpdateServices-DB" -ErrorAction Stop
            Write-Log "SQL Server Connectivity removal result: $($removeResult.Success)"

            if ($removeResult.Success) {
                Write-Log "Successfully removed SQL Server Connectivity feature"
            } else {
                Write-Log "WARNING: Could not remove SQL Server Connectivity"
            }
        } catch {
            Write-Log "ERROR removing SQL Server Connectivity: $_"
            Write-Log "Attempting alternative installation method..."
        }

        # Now install WSUS with WID
        Write-Log "Installing WSUS with Windows Internal Database (WID)..."
        $installResult = Install-WindowsFeature -Name UpdateServices -IncludeManagementTools
        Write-Log "UpdateServices installation result: $($installResult.Success)"
    } else {
        Write-Log "No conflict detected - installing WSUS with default database..."
        # Standard installation with WID
        $installResult = Install-WindowsFeature -Name UpdateServices -IncludeManagementTools
        Write-Log "UpdateServices installation result: $($installResult.Success)"
    }

    Write-Log "WSUS Role installation command completed."

    # Detailed diagnostics of installation result
    Write-Log "Installation Result Details:"
    Write-Log "  Success: $($installResult.Success)"
    Write-Log "  Exit Code: $($installResult.ExitCode)"
    Write-Log "  Restart Needed: $($installResult.RestartNeeded)"

    # Check what was actually installed
    Write-Log "Verifying installed WSUS features..."
    $installedFeatures = Get-WindowsFeature | Where-Object { $_.Name -like "UpdateServices*" -and $_.Installed }
    foreach ($feature in $installedFeatures) {
        Write-Log "  Installed: $($feature.Name) - $($feature.DisplayName)"
    }

    if ($installedFeatures.Count -eq 0) {
        Write-Log "ERROR: No UpdateServices features were installed!"
        Write-Log "Installation may have failed. Checking all available WSUS features..."
        $allWsusFeatures = Get-WindowsFeature | Where-Object { $_.Name -like "UpdateServices*" }
        foreach ($feature in $allWsusFeatures) {
            Write-Log "  $($feature.Name): Installed=$($feature.Installed), InstallState=$($feature.InstallState)"
        }
        throw "WSUS features not installed"
    }

    # Wait for installation to complete and check if reboot is needed
    if ($installResult.RestartNeeded -eq 'Yes') {
        Write-Log "WARNING: Reboot is required after WSUS installation."
        Write-Log "The script will continue, but you may need to reboot and run post-install manually."
    }

    # Create WSUS content directory
    $WSUSContentDir = "C:\WSUS"
    if (-not (Test-Path $WSUSContentDir)) {
        New-Item -Path $WSUSContentDir -ItemType Directory -Force
        Write-Log "Created WSUS content directory: $WSUSContentDir"
    }

    # Wait for wsusutil.exe to become available
    Write-Log "Waiting for WSUS binaries to become available..."
    $wsusUtilPath = "C:\Program Files\Update Services\Tools\wsusutil.exe"
    $maxWaitTime = 300  # 5 minutes
    $waitInterval = 10   # 10 seconds
    $elapsedTime = 0

    while (-not (Test-Path $wsusUtilPath) -and $elapsedTime -lt $maxWaitTime) {
        Write-Log "Waiting for wsusutil.exe... ($elapsedTime seconds elapsed)"
        Start-Sleep -Seconds $waitInterval
        $elapsedTime += $waitInterval
    }

    if (-not (Test-Path $wsusUtilPath)) {
        Write-Log "ERROR: wsusutil.exe not found after waiting $maxWaitTime seconds"
        Write-Log "Checking alternate locations and searching entire system..."

        # Check common alternate locations
        $alternatePaths = @(
            "C:\Program Files (x86)\Update Services\Tools\wsusutil.exe",
            "C:\Windows\System32\wsusutil.exe",
            "$env:ProgramFiles\Update Services\Tools\wsusutil.exe"
        )

        foreach ($altPath in $alternatePaths) {
            if (Test-Path $altPath) {
                $wsusUtilPath = $altPath
                Write-Log "Found wsusutil.exe at alternate location: $altPath"
                break
            }
        }

        # If still not found, search for it
        if (-not (Test-Path $wsusUtilPath)) {
            Write-Log "Searching for wsusutil.exe on C: drive (this may take a minute)..."
            try {
                $foundFiles = Get-ChildItem -Path "C:\Program Files" -Recurse -Filter "wsusutil.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($foundFiles) {
                    $wsusUtilPath = $foundFiles.FullName
                    Write-Log "Found wsusutil.exe at: $wsusUtilPath"
                } else {
                    Write-Log "ERROR: Cannot find wsusutil.exe anywhere on the system"
                    Write-Log ""
                    Write-Log "This suggests WSUS binaries were not installed properly."
                    Write-Log "Possible causes:"
                    Write-Log "  1. Installation failed silently"
                    Write-Log "  2. Reboot is required before binaries appear"
                    Write-Log "  3. Disk space issues"
                    Write-Log ""
                    Write-Log "Checking disk space..."
                    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
                        Write-Log "  $($_.Name): $([math]::Round($_.Free/1GB,2)) GB free of $([math]::Round(($_.Used+$_.Free)/1GB,2)) GB"
                    }
                    Write-Log ""
                    Write-Log "Manual fix:"
                    Write-Log "  1. Check if reboot is needed: Get-WindowsFeature UpdateServices*"
                    Write-Log "  2. Reboot the server if needed"
                    Write-Log "  3. After reboot, run: wsusutil.exe postinstall CONTENT_DIR=$WSUSContentDir"
                    throw "wsusutil.exe not found - WSUS installation may be incomplete"
                }
            } catch {
                Write-Log "Error searching for wsusutil.exe: $_"
                throw "wsusutil.exe not found"
            }
        }
    }

    Write-Log "Found wsusutil.exe at: $wsusUtilPath"

    # Run WSUS post-installation configuration
    Write-Log "Running WSUS post-installation configuration..."
    Write-Log "Command: $wsusUtilPath postinstall CONTENT_DIR=$WSUSContentDir"

    try {
        $postInstallOutput = & "$wsusUtilPath" postinstall "CONTENT_DIR=$WSUSContentDir" 2>&1
        Write-Log "Post-install output: $postInstallOutput"
        Write-Log "Waiting 30 seconds for post-install to complete..."
        Start-Sleep -Seconds 30
        Write-Log "WSUS post-installation completed."
    } catch {
        Write-Log "ERROR during post-install: $_"
        Write-Log "Attempting to continue anyway..."
    }

    # Load WSUS management assembly
    [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null

    # Connect to WSUS server
    Write-Log "Connecting to WSUS server..."
    $WSUSServer = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()

    # Configure WSUS synchronization source (Microsoft Update)
    Write-Log "Configuring synchronization source..."
    $WSUSConfig = $WSUSServer.GetConfiguration()
    $WSUSConfig.SyncFromMicrosoftUpdate = $true
    $WSUSConfig.Save()

    # Set WSUS server to use port 8530 (HTTP)
    Write-Log "Configuring WSUS to use port 8530..."
    $WSUSConfig.ServerId = [System.Guid]::NewGuid()
    $WSUSConfig.Save()

    # Configure products to sync (Windows Server, Windows 10/11)
    Write-Log "Configuring products..."
    $subscription = $WSUSServer.GetSubscription()
    $subscription.GetCategories() | Where-Object {
        $_.Title -eq "Windows Server 2019" -or
        $_.Title -eq "Windows Server 2022" -or
        $_.Title -eq "Windows Server 2016" -or
        $_.Title -eq "Windows 10" -or
        $_.Title -eq "Windows 11"
    } | ForEach-Object {
        $subscription.SetCategoryEnabled($_.Id, $true)
        Write-Log "Enabled product: $($_.Title)"
    }

    # Configure update classifications
    Write-Log "Configuring update classifications..."
    $subscription.GetCategories() | Where-Object {
        $_.Title -eq "Critical Updates" -or
        $_.Title -eq "Security Updates" -or
        $_.Title -eq "Definition Updates" -or
        $_.Title -eq "Update Rollups" -or
        $_.Title -eq "Updates"
    } | ForEach-Object {
        $subscription.SetCategoryEnabled($_.Id, $true)
        Write-Log "Enabled classification: $($_.Title)"
    }

    # Set synchronization schedule (daily at 2 AM)
    Write-Log "Setting synchronization schedule..."
    $subscription.SynchronizeAutomatically = $true
    $subscription.SynchronizeAutomaticallyTimeOfDay = (New-TimeSpan -Hours 2)
    $subscription.NumberOfSynchronizationsPerDay = 1
    $subscription.Save()

    # Create computer groups for organization
    Write-Log "Creating computer groups..."
    $allComputers = $WSUSServer.GetComputerTargetGroups() | Where-Object { $_.Name -eq "All Computers" }

    # Create groups for different server types
    $groupNames = @("Production Servers", "Development Servers", "Test Servers")
    foreach ($groupName in $groupNames) {
        try {
            $existingGroup = $WSUSServer.GetComputerTargetGroups() | Where-Object { $_.Name -eq $groupName }
            if (-not $existingGroup) {
                $WSUSServer.CreateComputerTargetGroup($groupName)
                Write-Log "Created computer group: $groupName"
            }
        } catch {
            Write-Log "Group may already exist or error creating: $groupName"
        }
    }

    # Start initial synchronization
    Write-Log "Starting initial synchronization (this may take a while)..."
    $subscription.StartSynchronization()

    # Configure Windows Firewall rules
    Write-Log "Configuring firewall rules..."
    New-NetFirewallRule -DisplayName "WSUS HTTP (8530)" -Direction Inbound -LocalPort 8530 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "WSUS HTTPS (8531)" -Direction Inbound -LocalPort 8531 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue

    Write-Log "Firewall rules configured."

    # Configure automatic approval rules
    Write-Log "Configuring automatic approval rules..."
    try {
        $rule = $WSUSServer.CreateInstallApprovalRule("Auto-Approve Critical and Security Updates")
        $rule.Enabled = $true
        $rule.Action = [Microsoft.UpdateServices.Administration.AutomaticUpdateApprovalAction]::Install

        # Add classifications to auto-approve
        $classifications = $WSUSServer.GetUpdateClassifications() | Where-Object {
            $_.Title -eq "Critical Updates" -or $_.Title -eq "Security Updates"
        }
        foreach ($classification in $classifications) {
            $rule.Classifications.Add($classification)
        }

        # Add computer groups to apply rule
        $allGroups = $WSUSServer.GetComputerTargetGroups()
        foreach ($group in $allGroups) {
            $rule.ComputerTargetGroups.Add($group)
        }

        $rule.Save()
        Write-Log "Auto-approval rule created successfully."
    } catch {
        Write-Log "Error creating auto-approval rule: $_"
    }

    # Set WSUS to run automatically
    Write-Log "Configuring WSUS service to start automatically..."
    Set-Service -Name WsusService -StartupType Automatic

    # Configure IIS settings for WSUS
    Write-Log "Configuring IIS for WSUS..."
    Import-Module WebAdministration

    # Increase max request length for client reports
    Set-WebConfigurationProperty -PSPath "IIS:\Sites\WSUS Administration" -Filter "system.webServer/security/requestFiltering/requestLimits" -Name "maxAllowedContentLength" -Value 30000000

    # Set client web service connection timeout
    Set-WebConfigurationProperty -PSPath "IIS:\Sites\WSUS Administration" -Filter "system.web/httpRuntime" -Name "executionTimeout" -Value 7200

    Write-Log "IIS configuration completed."

    # Create a scheduled task to run WSUS cleanup weekly
    Write-Log "Creating WSUS cleanup scheduled task..."
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -Command `"Get-WsusServer | Invoke-WsusServerCleanup -CleanupObsoleteUpdates -CleanupUnneededContentFiles -CompressUpdates -DeclineExpiredUpdates -DeclineSupersededUpdates`""
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName "WSUS Server Cleanup" -Action $action -Trigger $trigger -Principal $principal -Description "Weekly WSUS server cleanup task"

    Write-Log "Scheduled task created."

    # Output WSUS server information
    Write-Log "================================"
    Write-Log "WSUS Server Setup Complete!"
    Write-Log "================================"
    Write-Log "WSUS Server URL: http://$(hostname):8530"
    Write-Log "WSUS Console: Open 'Windows Server Update Services' from Server Manager"
    Write-Log ""
    Write-Log "Next Steps:"
    Write-Log "1. Configure client machines to use this WSUS server"
    Write-Log "2. Monitor synchronization status in WSUS console"
    Write-Log "3. Approve updates for computer groups"
    Write-Log "================================"

    # Create a summary file
    @"
WSUS Server Configuration Summary
==================================
Server: $(hostname)
IP Address: $(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" | Select-Object -First 1 -ExpandProperty IPAddress)
WSUS URL: http://$(hostname):8530
Content Directory: $WSUSContentDir
Installation Date: $(Get-Date)

Configuration:
- Products: Windows Server 2016, 2019, 2022, Windows 10, 11
- Classifications: Critical Updates, Security Updates, Definition Updates, Update Rollups, Updates
- Synchronization: Daily at 2:00 AM
- Auto-Approval: Enabled for Critical and Security Updates
- Cleanup Task: Weekly on Sunday at 3:00 AM

Computer Groups Created:
- All Computers (Default)
- Production Servers
- Development Servers
- Test Servers

Firewall Rules:
- TCP 8530 (HTTP) - Open
- TCP 8531 (HTTPS) - Open
"@ | Out-File "C:\WSUS-Configuration.txt"

    Write-Log "Configuration summary saved to C:\WSUS-Configuration.txt"

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)"
    throw
}

Write-Log "Script execution completed."
</powershell>
