# WSUS Configuration via Domain Group Policy
# Run this on DOMAIN CONTROLLER (10.50.5.31)
# This creates a GPO to configure WSUS for all computers in the domain

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "WSUS Domain Group Policy Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$WSUSServer = "10.50.6.69"
$WSUSPort = "8530"
$GPOName = "WSUS Configuration"

Write-Host "WSUS Server: http://${WSUSServer}:${WSUSPort}" -ForegroundColor Cyan
Write-Host "GPO Name: $GPOName" -ForegroundColor Cyan
Write-Host ""

# Check if running on Domain Controller
Write-Host "[1] Checking if running on Domain Controller..." -ForegroundColor Yellow
$isDC = (Get-WmiObject -Class Win32_ComputerSystem).DomainRole -ge 4

if (-not $isDC) {
    Write-Host "  [WARNING] This does not appear to be a Domain Controller!" -ForegroundColor Red
    Write-Host "  This script must be run on a Domain Controller." -ForegroundColor Red
    Write-Host "  Current domain role: $((Get-WmiObject -Class Win32_ComputerSystem).DomainRole)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  If you cannot access the DC, use OPTION 2 instead." -ForegroundColor Yellow
    exit
}

Write-Host "  [OK] Running on Domain Controller" -ForegroundColor Green

# Import Group Policy module
Write-Host ""
Write-Host "[2] Loading Group Policy module..." -ForegroundColor Yellow
try {
    Import-Module GroupPolicy -ErrorAction Stop
    Write-Host "  [OK] Module loaded" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] Cannot load GroupPolicy module: $_" -ForegroundColor Red
    Write-Host "  Install RSAT tools: Install-WindowsFeature GPMC" -ForegroundColor Yellow
    exit
}

# Check if GPO already exists
Write-Host ""
Write-Host "[3] Checking for existing GPO..." -ForegroundColor Yellow
$existingGPO = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue

if ($existingGPO) {
    Write-Host "  [FOUND] GPO '$GPOName' already exists" -ForegroundColor Yellow
    Write-Host "  Do you want to update it? (Y/N)" -ForegroundColor Yellow
    $response = Read-Host
    if ($response -ne 'Y') {
        Write-Host "  Aborted." -ForegroundColor Red
        exit
    }
    $gpo = $existingGPO
} else {
    Write-Host "  Creating new GPO: $GPOName" -ForegroundColor Yellow
    $gpo = New-GPO -Name $GPOName
    Write-Host "  [OK] GPO created" -ForegroundColor Green
}

# Configure WSUS settings in the GPO
Write-Host ""
Write-Host "[4] Configuring WSUS settings in GPO..." -ForegroundColor Yellow

# Registry path for Group Policy
$regPath = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$regPathAU = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

# Set WSUS server location
Write-Host "  Setting WSUS server location..." -ForegroundColor DarkGray
Set-GPRegistryValue -Name $GPOName -Key $regPath -ValueName "WUServer" -Type String -Value "http://${WSUSServer}:${WSUSPort}" | Out-Null
Set-GPRegistryValue -Name $GPOName -Key $regPath -ValueName "WUStatusServer" -Type String -Value "http://${WSUSServer}:${WSUSPort}" | Out-Null

# Enable WSUS
Write-Host "  Enabling WSUS usage..." -ForegroundColor DarkGray
Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "UseWUServer" -Type DWord -Value 1 | Out-Null

# Configure Automatic Updates
Write-Host "  Configuring Automatic Updates..." -ForegroundColor DarkGray
Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "NoAutoUpdate" -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "AUOptions" -Type DWord -Value 4 | Out-Null
Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "ScheduledInstallDay" -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "ScheduledInstallTime" -Type DWord -Value 3 | Out-Null

# Set detection frequency
Write-Host "  Setting detection frequency (1 hour)..." -ForegroundColor DarkGray
Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "DetectionFrequencyEnabled" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "DetectionFrequency" -Type DWord -Value 1 | Out-Null

# Prevent connecting to Windows Update
Write-Host "  Preventing Windows Update internet access..." -ForegroundColor DarkGray
Set-GPRegistryValue -Name $GPOName -Key $regPath -ValueName "DoNotConnectToWindowsUpdateInternetLocations" -Type DWord -Value 1 | Out-Null

# Additional settings
Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "NoAutoRebootWithLoggedOnUsers" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $GPOName -Key $regPathAU -ValueName "IncludeRecommendedUpdates" -Type DWord -Value 1 | Out-Null

Write-Host "  [OK] WSUS settings configured in GPO" -ForegroundColor Green

# Link GPO to domain root
Write-Host ""
Write-Host "[5] Linking GPO to domain..." -ForegroundColor Yellow

$domain = Get-ADDomain
$domainDN = $domain.DistinguishedName

Write-Host "  Domain: $($domain.DNSRoot)" -ForegroundColor Cyan
Write-Host "  Distinguished Name: $domainDN" -ForegroundColor DarkGray

$existingLink = Get-GPInheritance -Target $domainDN | Select-Object -ExpandProperty GpoLinks | Where-Object { $_.DisplayName -eq $GPOName }

if ($existingLink) {
    Write-Host "  [OK] GPO already linked to domain" -ForegroundColor Green
} else {
    New-GPLink -Name $GPOName -Target $domainDN -LinkEnabled Yes | Out-Null
    Write-Host "  [OK] GPO linked to domain root" -ForegroundColor Green
}

# Force Group Policy update on all computers
Write-Host ""
Write-Host "[6] GPO Configuration Summary..." -ForegroundColor Yellow
Write-Host "  GPO Name: $GPOName" -ForegroundColor Cyan
Write-Host "  WSUS Server: http://${WSUSServer}:${WSUSPort}" -ForegroundColor Cyan
Write-Host "  Linked to: $($domain.DNSRoot)" -ForegroundColor Cyan
Write-Host "  Status: Active" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "GPO CONFIGURATION COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Wait 90 minutes for GPO to apply naturally" -ForegroundColor White
Write-Host "     OR" -ForegroundColor White
Write-Host "  2. On each client computer, run: gpupdate /force" -ForegroundColor White
Write-Host "  3. After gpupdate, restart Windows Update service: Restart-Service wuauserv" -ForegroundColor White
Write-Host "  4. Clients should appear in WSUS console within 10-15 minutes" -ForegroundColor White
Write-Host ""
Write-Host "To verify GPO is applied on a client:" -ForegroundColor Yellow
Write-Host '  gpresult /r | Select-String -Pattern "WSUS"' -ForegroundColor DarkGray
Write-Host ""
Write-Host "To check WSUS server configuration on client:" -ForegroundColor Yellow
Write-Host '  Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"' -ForegroundColor DarkGray
Write-Host ""
