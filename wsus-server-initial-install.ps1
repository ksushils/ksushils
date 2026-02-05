<powershell>
# WSUS Server Initial Installation - EC2 User Data
# This runs on first boot and installs WSUS features

$ErrorActionPreference = "Continue"
$LogFile = "C:\wsus-initial-install.log"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

Write-Log "========================================"
Write-Log "WSUS Initial Installation"
Write-Log "========================================"

try {
    # Check and remove SQL Server Connectivity if exists
    Write-Log "Checking for SQL Server Connectivity conflict..."
    try {
        $sqlConn = Get-WindowsFeature -Name "UpdateServices-DB" -ErrorAction SilentlyContinue
        if ($sqlConn -and $sqlConn.Installed) {
            Write-Log "UpdateServices-DB is installed - removing to avoid conflict..."
            $removeResult = Uninstall-WindowsFeature -Name "UpdateServices-DB"
            Write-Log "Removal result: $($removeResult.Success)"
        } else {
            Write-Log "No SQL Server Connectivity conflict detected."
        }
    } catch {
        Write-Log "Error checking for SQL connectivity: $_"
        Write-Log "Continuing with installation..."
    }

    # Install WSUS
    Write-Log ""
    Write-Log "Installing WSUS features..."
    Write-Log "This may take 5-10 minutes..."

    $result = Install-WindowsFeature -Name UpdateServices -IncludeManagementTools

    Write-Log ""
    Write-Log "Installation Results:"
    Write-Log "  Success: $($result.Success)"
    Write-Log "  Exit Code: $($result.ExitCode)"
    Write-Log "  Restart Needed: $($result.RestartNeeded)"
    Write-Log "  Features Installed: $($result.FeatureResult.Count)"

    # List installed features
    $result.FeatureResult | ForEach-Object {
        Write-Log "    - $($_.DisplayName)"
    }

    # Check if reboot is needed
    if ($result.RestartNeeded -eq 'Yes') {
        Write-Log ""
        Write-Log "========================================"
        Write-Log "REBOOT REQUIRED"
        Write-Log "========================================"
        Write-Log "A reboot is required to complete the installation."
        Write-Log ""
        Write-Log "After reboot:"
        Write-Log "1. Copy wsus-post-reboot-setup.ps1 to the server"
        Write-Log "2. Run: .\wsus-post-reboot-setup.ps1"
        Write-Log "3. Complete the WSUS Configuration Wizard (GUI)"
        Write-Log ""
        Write-Log "Scheduling automatic reboot in 60 seconds..."
        Write-Log "========================================"

        shutdown /r /t 60 /c "Rebooting to complete WSUS installation. After reboot, run wsus-post-reboot-setup.ps1"
    } else {
        Write-Log ""
        Write-Log "WARNING: No reboot indicated by installation."
        Write-Log "This is unusual. The installation may not be complete."
        Write-Log "You may need to reboot manually."
    }

} catch {
    Write-Log ""
    Write-Log "ERROR: Installation failed"
    Write-Log "Error: $_"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)"
    throw
}

Write-Log ""
Write-Log "========================================"
Write-Log "Installation script completed"
Write-Log "Log file: $LogFile"
Write-Log "========================================"
</powershell>
