# Temporarily remove client from domain to allow WSUS configuration
# WARNING: This is a temporary workaround. You'll need to re-join the domain later.
# NOT RECOMMENDED for production environments

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Red
Write-Host "REMOVE FROM DOMAIN (TEMPORARY WORKAROUND)" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host ""
Write-Host "WARNING: This will remove the computer from the domain!" -ForegroundColor Red
Write-Host "You will need to re-join the domain after WSUS registration." -ForegroundColor Yellow
Write-Host ""
Write-Host "Current domain: $($(Get-WmiObject -Class Win32_ComputerSystem).Domain)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Do you want to continue? Type 'YES' to proceed: " -ForegroundColor Yellow
$confirmation = Read-Host

if ($confirmation -ne 'YES') {
    Write-Host "Aborted." -ForegroundColor Green
    exit
}

Write-Host ""
Write-Host "[1] Removing computer from domain..." -ForegroundColor Yellow
Write-Host ""

# You need domain admin credentials
$credential = Get-Credential -Message "Enter domain admin credentials to unjoin domain"

try {
    # Remove from domain and join workgroup
    $workgroupName = "WORKGROUP"

    Write-Host "  Removing from domain and joining workgroup '$workgroupName'..." -ForegroundColor DarkGray
    Remove-Computer -UnjoinDomainCredential $credential -WorkgroupName $workgroupName -Force -Restart

    Write-Host ""
    Write-Host "  [OK] Computer will restart and join workgroup" -ForegroundColor Green
    Write-Host ""
    Write-Host "After restart:" -ForegroundColor Yellow
    Write-Host "  1. Run wsus-client-force-reset.ps1 again" -ForegroundColor White
    Write-Host "  2. Client should register with WSUS within 10 minutes" -ForegroundColor White
    Write-Host "  3. To re-join domain, run: Add-Computer -DomainName ad.rldatix.cloud -Credential (Get-Credential) -Restart" -ForegroundColor White

} catch {
    Write-Host "  [ERROR] Failed to remove from domain: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "You may need to:" -ForegroundColor Yellow
    Write-Host "  1. Use 'System Properties' GUI to leave domain" -ForegroundColor White
    Write-Host "  2. Computer Settings → Change → Workgroup" -ForegroundColor White
}
