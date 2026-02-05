# WSUS Post-Reboot Setup Script
# Run this script AFTER rebooting the server to complete WSUS installation

# Set error handling
$ErrorActionPreference = "Continue"

# Create log file
$LogFile = "C:\wsus-post-reboot-setup.log"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "WSUS Post-Reboot Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "Starting WSUS post-reboot setup..."

# Check if wsusutil.exe exists
$wsusUtilPath = "C:\Program Files\Update Services\Tools\wsusutil.exe"
Write-Log "Checking for wsusutil.exe at: $wsusUtilPath"

if (Test-Path $wsusUtilPath) {
    Write-Host "[OK] Found wsusutil.exe" -ForegroundColor Green
    Write-Log "wsusutil.exe found successfully."
} else {
    Write-Host "[ERROR] wsusutil.exe not found!" -ForegroundColor Red
    Write-Log "ERROR: wsusutil.exe not found at expected location."

    # Check if WSUS directory exists
    if (Test-Path "C:\Program Files\Update Services") {
        Write-Host "Update Services directory exists, but wsusutil.exe is missing." -ForegroundColor Yellow
        Write-Log "Update Services directory found, but wsusutil.exe missing."

        # Search for it
        Write-Host "Searching for wsusutil.exe..." -ForegroundColor Yellow
        $found = Get-ChildItem -Path "C:\Program Files\Update Services" -Recurse -Filter "wsusutil.exe" -ErrorAction SilentlyContinue
        if ($found) {
            $wsusUtilPath = $found.FullName
            Write-Host "[FOUND] $wsusUtilPath" -ForegroundColor Green
        }
    } else {
        Write-Host "[ERROR] Update Services directory not found!" -ForegroundColor Red
        Write-Host "" -ForegroundColor Red
        Write-Host "WSUS does not appear to be installed." -ForegroundColor Red
        Write-Host "Please install WSUS manually:" -ForegroundColor Yellow
        Write-Host "  1. Open Server Manager" -ForegroundColor White
        Write-Host "  2. Add Roles and Features" -ForegroundColor White
        Write-Host "  3. Select 'Windows Server Update Services'" -ForegroundColor White
        Write-Host "  4. Complete the wizard" -ForegroundColor White
        Write-Host "  5. After installation, run this script again" -ForegroundColor White
        exit 1
    }
}

# Create WSUS content directory
$WSUSContentDir = "C:\WSUS"
Write-Log "Ensuring WSUS content directory exists: $WSUSContentDir"

if (-not (Test-Path $WSUSContentDir)) {
    New-Item -Path $WSUSContentDir -ItemType Directory -Force | Out-Null
    Write-Host "[CREATED] WSUS content directory: $WSUSContentDir" -ForegroundColor Green
} else {
    Write-Host "[OK] WSUS content directory exists" -ForegroundColor Green
}

# Check if post-install was already run
$wsusConfigured = $false
try {
    [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
    $testServer = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()
    if ($testServer) {
        $wsusConfigured = $true
        Write-Host "[OK] WSUS is already configured" -ForegroundColor Green
        Write-Log "WSUS server connection successful - already configured."
    }
} catch {
    Write-Log "WSUS not yet configured, will run post-install."
}

if (-not $wsusConfigured) {
    # Run WSUS post-installation
    Write-Host "" -ForegroundColor Yellow
    Write-Host "Running WSUS post-installation..." -ForegroundColor Yellow
    Write-Log "Running: $wsusUtilPath postinstall CONTENT_DIR=$WSUSContentDir"

    try {
        $output = & "$wsusUtilPath" postinstall "CONTENT_DIR=$WSUSContentDir" 2>&1

        Write-Host "" -ForegroundColor Green
        Write-Host "Post-install output:" -ForegroundColor Green
        Write-Host $output -ForegroundColor White

        Write-Log "Post-install output: $output"

        # Wait for post-install to complete
        Write-Host "" -ForegroundColor Yellow
        Write-Host "Waiting 30 seconds for post-install to complete..." -ForegroundColor Yellow
        Start-Sleep -Seconds 30

        Write-Host "[OK] WSUS post-installation completed" -ForegroundColor Green
        Write-Log "WSUS post-installation completed successfully."

    } catch {
        Write-Host "[ERROR] Post-install failed: $_" -ForegroundColor Red
        Write-Log "ERROR during post-install: $_"
        exit 1
    }
}

# Now configure WSUS
Write-Host "" -ForegroundColor Cyan
Write-Host "Configuring WSUS..." -ForegroundColor Cyan

try {
    # Load WSUS management assembly
    [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null

    # Connect to WSUS server
    Write-Host "Connecting to WSUS server..." -ForegroundColor Yellow
    $WSUSServer = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()
    Write-Host "[OK] Connected to WSUS server" -ForegroundColor Green

    # Configure synchronization source
    Write-Host "Configuring synchronization source..." -ForegroundColor Yellow
    $WSUSConfig = $WSUSServer.GetConfiguration()
    $WSUSConfig.SyncFromMicrosoftUpdate = $true
    $WSUSConfig.Save()
    Write-Host "[OK] Sync source configured" -ForegroundColor Green

    # Configure firewall rules
    Write-Host "Configuring firewall rules..." -ForegroundColor Yellow
    New-NetFirewallRule -DisplayName "WSUS HTTP (8530)" -Direction Inbound -LocalPort 8530 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "WSUS HTTPS (8531)" -Direction Inbound -LocalPort 8531 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Host "[OK] Firewall rules configured" -ForegroundColor Green

    # Set WSUS service to automatic
    Write-Host "Configuring WSUS service..." -ForegroundColor Yellow
    Set-Service -Name WsusService -StartupType Automatic -ErrorAction SilentlyContinue
    Write-Host "[OK] WSUS service configured" -ForegroundColor Green

    Write-Host "" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "WSUS Setup Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "WSUS Server URL: http://$(hostname):8530" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "1. Open 'Windows Server Update Services' from Server Manager" -ForegroundColor White
    Write-Host "2. Run initial synchronization" -ForegroundColor White
    Write-Host "3. Configure products and classifications" -ForegroundColor White
    Write-Host "4. Configure client computers to use this WSUS server" -ForegroundColor White
    Write-Host ""

    Write-Log "WSUS setup completed successfully!"

} catch {
    Write-Host "" -ForegroundColor Red
    Write-Host "[ERROR] Configuration failed: $_" -ForegroundColor Red
    Write-Log "ERROR during configuration: $_"
    Write-Log "Stack trace: $($_.ScriptStackTrace)"

    Write-Host "" -ForegroundColor Yellow
    Write-Host "You can configure WSUS manually:" -ForegroundColor Yellow
    Write-Host "1. Open Server Manager" -ForegroundColor White
    Write-Host "2. Tools > Windows Server Update Services" -ForegroundColor White
    Write-Host "3. Follow the configuration wizard" -ForegroundColor White
    exit 1
}

Write-Host "Log file: $LogFile" -ForegroundColor DarkGray
