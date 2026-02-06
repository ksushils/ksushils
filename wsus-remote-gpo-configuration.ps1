# Configure Domain Group Policy for WSUS - REMOTELY from WSUS Server
# Run this on WSUS SERVER (10.50.6.69)
# This will configure Group Policy on the Domain Controller remotely

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Remote Domain GPO Configuration for WSUS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$WSUSServer = "10.50.6.69"
$WSUSPort = "8530"
$DomainController = "10.50.5.31"
$DomainName = "ad.rldatix.cloud"
$GPOName = "WSUS Configuration"

Write-Host "WSUS Server: http://${WSUSServer}:${WSUSPort}" -ForegroundColor Cyan
Write-Host "Domain Controller: $DomainController" -ForegroundColor Cyan
Write-Host "Domain: $DomainName" -ForegroundColor Cyan
Write-Host "GPO Name: $GPOName" -ForegroundColor Cyan
Write-Host ""

# Check if GroupPolicy module is available
Write-Host "[1] Checking for Group Policy Management tools..." -ForegroundColor Yellow

if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
    Write-Host "  [NOT FOUND] Group Policy module not installed" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Installing Remote Server Administration Tools (RSAT)..." -ForegroundColor Yellow

    try {
        # For Windows Server 2016+
        Install-WindowsFeature -Name GPMC -IncludeManagementTools
        Write-Host "  [OK] GPMC installed" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Could not install GPMC: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Manual installation:" -ForegroundColor Yellow
        Write-Host "    Install-WindowsFeature GPMC" -ForegroundColor White
        exit
    }
} else {
    Write-Host "  [OK] Group Policy module is available" -ForegroundColor Green
}

# Import the module
Write-Host ""
Write-Host "[2] Loading Group Policy module..." -ForegroundColor Yellow
try {
    Import-Module GroupPolicy -ErrorAction Stop
    Write-Host "  [OK] Module loaded" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] Cannot load GroupPolicy module: $_" -ForegroundColor Red
    exit
}

# Get domain admin credentials
Write-Host ""
Write-Host "[3] Connecting to domain..." -ForegroundColor Yellow
Write-Host "  Enter domain admin credentials for $DomainName" -ForegroundColor Yellow
$credential = Get-Credential -Message "Enter Domain Admin credentials (domain\username)"

# Test domain connectivity
Write-Host ""
Write-Host "[4] Testing connection to Domain Controller..." -ForegroundColor Yellow
$dcTest = Test-NetConnection -ComputerName $DomainController -Port 445 -InformationLevel Quiet

if ($dcTest) {
    Write-Host "  [OK] Can reach Domain Controller" -ForegroundColor Green
} else {
    Write-Host "  [ERROR] Cannot reach Domain Controller at $DomainController" -ForegroundColor Red
    Write-Host "  Check network connectivity and firewall rules" -ForegroundColor Yellow
    exit
}

# Check if GPO exists, create if not
Write-Host ""
Write-Host "[5] Checking for existing GPO..." -ForegroundColor Yellow

try {
    $existingGPO = Get-GPO -Name $GPOName -Domain $DomainName -Server $DomainController -ErrorAction SilentlyContinue

    if ($existingGPO) {
        Write-Host "  [FOUND] GPO '$GPOName' exists (will update)" -ForegroundColor Yellow
        $gpo = $existingGPO
    } else {
        Write-Host "  Creating new GPO: $GPOName" -ForegroundColor Yellow
        $gpo = New-GPO -Name $GPOName -Domain $DomainName -Server $DomainController
        Write-Host "  [OK] GPO created" -ForegroundColor Green
    }
} catch {
    Write-Host "  [ERROR] Cannot access domain: $_" -ForegroundColor Red
    Write-Host "  Make sure you have domain admin credentials" -ForegroundColor Yellow
    exit
}

# Configure WSUS settings in GPO
Write-Host ""
Write-Host "[6] Configuring WSUS settings in GPO..." -ForegroundColor Yellow

$regPath = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$regPathAU = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

try {
    # WSUS Server locations
    Write-Host "  Setting WSUS server location..." -ForegroundColor DarkGray
    Set-GPRegistryValue -Name $GPOName -Key $regPath -ValueName "WUServer" -Type String -Value "http://${WSUSServer}:${WSUSPort}" -Domain $DomainName -Server $DomainController | Out-Null
    Set-GPRegistryValue -Name $GPOName -Key $regPath -ValueName "WUStatusServer" -Type String -Value "http://${WSUSServer}:${WSUSPort}" -Domain $DomainName -Server $DomainController | Out-Null

    # Enable WSUS
    Write-Host "  Enabling WSUS usage..." -ForegroundColor DarkGray
    Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "UseWUServer" -Type DWord -Value 1 -Domain $DomainName -Server $DomainController | Out-Null

    # Automatic Updates configuration
    Write-Host "  Configuring Automatic Updates..." -ForegroundColor DarkGray
    Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "NoAutoUpdate" -Type DWord -Value 0 -Domain $DomainName -Server $DomainController | Out-Null
    Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "AUOptions" -Type DWord -Value 4 -Domain $DomainName -Server $DomainController | Out-Null
    Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "ScheduledInstallDay" -Type DWord -Value 0 -Domain $DomainName -Server $DomainController | Out-Null
    Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "ScheduledInstallTime" -Type DWord -Value 3 -Domain $DomainName -Server $DomainController | Out-Null

    # Detection frequency
    Write-Host "  Setting detection frequency..." -ForegroundColor DarkGray
    Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "DetectionFrequencyEnabled" -Type DWord -Value 1 -Domain $DomainName -Server $DomainController | Out-Null
    Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "DetectionFrequency" -Type DWord -Value 1 -Domain $DomainName -Server $DomainController | Out-Null

    # Additional settings
    Write-Host "  Configuring additional policies..." -ForegroundColor DarkGray
    Set-GPRegistryValue -Name $GPOName -Key $regPath -ValueName "DoNotConnectToWindowsUpdateInternetLocations" -Type DWord -Value 1 -Domain $DomainName -Server $DomainController | Out-Null
    Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "NoAutoRebootWithLoggedOnUsers" -Type DWord -Value 1 -Domain $DomainName -Server $DomainController | Out-Null
    Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "IncludeRecommendedUpdates" -Type DWord -Value 1 -Domain $DomainName -Server $DomainController | Out-Null

    Write-Host "  [OK] All WSUS settings configured" -ForegroundColor Green

} catch {
    Write-Host "  [ERROR] Failed to configure GPO settings: $_" -ForegroundColor Red
    exit
}

# Link GPO to domain
Write-Host ""
Write-Host "[7] Linking GPO to domain..." -ForegroundColor Yellow

try {
    $domainDN = "DC=" + ($DomainName -replace "\.", ",DC=")
    Write-Host "  Domain DN: $domainDN" -ForegroundColor DarkGray

    # Check if already linked
    $existingLink = Get-GPInheritance -Target $domainDN -Domain $DomainName -Server $DomainController |
                    Select-Object -ExpandProperty GpoLinks |
                    Where-Object { $_.DisplayName -eq $GPOName }

    if ($existingLink) {
        Write-Host "  [OK] GPO already linked to domain" -ForegroundColor Green
    } else {
        New-GPLink -Name $GPOName -Target $domainDN -LinkEnabled Yes -Domain $DomainName -Server $DomainController | Out-Null
        Write-Host "  [OK] GPO linked to domain root" -ForegroundColor Green
    }

} catch {
    Write-Host "  [ERROR] Failed to link GPO: $_" -ForegroundColor Red
    Write-Host "  You may need to link it manually via Group Policy Management Console" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "GPO CONFIGURATION COMPLETE!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "GPO Details:" -ForegroundColor Yellow
Write-Host "  Name: $GPOName" -ForegroundColor Cyan
Write-Host "  Domain: $DomainName" -ForegroundColor Cyan
Write-Host "  WSUS Server: http://${WSUSServer}:${WSUSPort}" -ForegroundColor Cyan
Write-Host "  Status: Active and Linked" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. On client computers, run: gpupdate /force" -ForegroundColor White
Write-Host "  2. Restart Windows Update service: Restart-Service wuauserv -Force" -ForegroundColor White
Write-Host "  3. Force detection: wuauclt /detectnow /reportnow" -ForegroundColor White
Write-Host "  4. Wait 5-10 minutes" -ForegroundColor White
Write-Host "  5. Check WSUS Console > Computers > Unassigned Computers" -ForegroundColor White
Write-Host ""
Write-Host "To verify on client:" -ForegroundColor Yellow
Write-Host '  $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()' -ForegroundColor DarkGray
Write-Host '  Write-Host "Server Selection: $($searcher.ServerSelection)"  # Should be 1' -ForegroundColor DarkGray
Write-Host ""
Write-Host "The GPO will automatically apply to all computers in the domain." -ForegroundColor Green
Write-Host "New computers will also automatically get WSUS configuration." -ForegroundColor Green
Write-Host ""
