# WSUS Complete Working Setup - FINAL INSTRUCTIONS

**Based on successful implementation: February 5, 2026**

---

## 🎯 What Can Be Automated

### ✅ CLIENT CONFIGURATION: 100% AUTOMATED
Use `wsus-client-userdata.ps1` as EC2 user data - fully automated, tested and working.

### ⚠️ WSUS SERVER: 90% AUTOMATED (one manual GUI step required)
- Automated: Feature installation, reboot, post-install configuration
- Manual: WSUS Configuration Wizard (GUI) - required by Microsoft, cannot be automated

---

## 📁 FINAL FILES TO USE

### For WSUS Server
1. **Phase 1**: Use EC2 user data or run manually
2. **Phase 2**: After reboot, use `wsus-post-reboot-setup.ps1`
3. **Phase 3**: Complete GUI wizard (5 minutes)

### For Clients
1. **Use**: `wsus-client-userdata.ps1` (fully automated)

---

## 🚀 WSUS SERVER SETUP

### METHOD 1: Semi-Automated (Recommended)

**Step 1: Install WSUS Features (Automated via EC2 User Data)**

Create file: `wsus-server-initial-install.ps1`

```powershell
<powershell>
# WSUS Server Initial Installation - EC2 User Data
# This runs on first boot

$ErrorActionPreference = "Continue"
$LogFile = "C:\wsus-initial-install.log"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

Write-Log "=== WSUS Initial Installation ==="

# Check and remove SQL Server Connectivity if exists
Write-Log "Checking for SQL Server Connectivity conflict..."
try {
    $sqlConn = Get-WindowsFeature -Name "UpdateServices-DB" -ErrorAction SilentlyContinue
    if ($sqlConn -and $sqlConn.Installed) {
        Write-Log "Removing UpdateServices-DB..."
        Uninstall-WindowsFeature -Name "UpdateServices-DB" | Out-Null
    }
} catch {
    Write-Log "No SQL Server Connectivity to remove"
}

# Install WSUS
Write-Log "Installing WSUS features..."
$result = Install-WindowsFeature -Name UpdateServices -IncludeManagementTools

Write-Log "Installation completed: Success=$($result.Success), RestartNeeded=$($result.RestartNeeded)"

# Check if reboot is needed
if ($result.RestartNeeded -eq 'Yes') {
    Write-Log "Reboot required. Scheduling reboot in 60 seconds..."
    shutdown /r /t 60 /c "Rebooting to complete WSUS installation"
} else {
    Write-Log "No reboot required (unusual). Installation may have issues."
}

Write-Log "=== Installation script completed ==="
Write-Log "Next: After reboot, run wsus-post-reboot-setup.ps1"
</powershell>
```

**Use this as EC2 User Data when launching the WSUS server instance.**

---

**Step 2: After Reboot - Run Post-Installation**

Use the existing file: `wsus-post-reboot-setup.ps1`

**How to run automatically after reboot** (optional):

Before the reboot, create a scheduled task:

```powershell
# Run this BEFORE the server reboots to auto-run post-reboot script
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\wsus-post-reboot-setup.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "WSUS-Post-Reboot-Setup" -Action $action -Trigger $trigger -Principal $principal -Settings $settings

# This task will run once after reboot, then you can delete it
```

**OR** just copy `wsus-post-reboot-setup.ps1` to the server and run it manually after reboot.

---

**Step 3: Complete GUI Configuration Wizard (MANUAL - 5 minutes)**

After `wsus-post-reboot-setup.ps1` completes:

1. Open Server Manager
2. Tools → Windows Server Update Services
3. Complete the wizard:
   - Sync from Microsoft Update
   - Select products: Windows Server 2016, 2019, 2022
   - Select classifications: Critical Updates, Security Updates
   - Begin initial synchronization

**DONE!** WSUS server is now fully operational.

---

### METHOD 2: Fully Manual (Use if automation fails)

If you prefer to do everything manually:

**Step 1: Install WSUS**
```powershell
# Remove conflict
Uninstall-WindowsFeature -Name "UpdateServices-DB" -ErrorAction SilentlyContinue

# Install WSUS
Install-WindowsFeature -Name UpdateServices -IncludeManagementTools

# Reboot
Restart-Computer -Force
```

**Step 2: After Reboot**
```powershell
# Run post-install
& "C:\Program Files\Update Services\Tools\wsusutil.exe" postinstall CONTENT_DIR=C:\WSUS

# Start services
Start-Service "MSSQL`$MICROSOFT##WID"
Start-Service WsusService
iisreset /restart

# Configure firewall
New-NetFirewallRule -DisplayName "WSUS HTTP (8530)" -Direction Inbound -LocalPort 8530 -Protocol TCP -Action Allow
```

**Step 3: Complete GUI Wizard** (same as above)

---

## 🖥️ CLIENT SETUP (FULLY AUTOMATED)

Use this file AS-IS for EC2 user data: **`wsus-client-userdata.ps1`**

**The WSUS server IP is already set to `10.50.5.96` - it's ready to use!**

### Terraform Example

```hcl
resource "aws_instance" "wsus_clients" {
  count         = 15
  ami           = "ami-xxxxx"  # Windows Server 2022 AMI
  instance_type = "t3.small"
  subnet_id     = var.private_subnet_id

  # CLIENT SCRIPT - FULLY AUTOMATED
  user_data = file("${path.module}/wsus-client-userdata.ps1")

  vpc_security_group_ids = [aws_security_group.wsus_clients.id]

  tags = {
    Name = "WSUS-Client-${count.index + 1}"
  }
}

# Security group for clients
resource "aws_security_group" "wsus_clients" {
  name        = "wsus-clients-sg"
  description = "Security group for WSUS clients"
  vpc_id      = var.vpc_id

  # Allow outbound to WSUS server
  egress {
    from_port   = 8530
    to_port     = 8530
    protocol    = "tcp"
    cidr_blocks = ["10.50.5.96/32"]
    description = "WSUS Server"
  }

  # Allow other outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

**That's it!** Launch your 15 instances and they will automatically:
1. ✅ Configure registry for WSUS
2. ✅ Connect to 10.50.5.96:8530
3. ✅ Report to WSUS within 10-15 minutes
4. ✅ Install updates daily at 3:00 AM

---

## 📋 COMPLETE DEPLOYMENT CHECKLIST

### WSUS Server Deployment

- [ ] Launch EC2 instance with `wsus-server-initial-install.ps1` as user data
- [ ] Wait for automatic reboot (5-10 minutes)
- [ ] After reboot: Run `wsus-post-reboot-setup.ps1` (manual or scheduled task)
- [ ] Wait for script completion (2-3 minutes)
- [ ] Open WSUS Console and complete Configuration Wizard (5 minutes)
- [ ] Verify synchronization started in WSUS console

**Total Time**: 20-30 minutes (most is waiting for installation/sync)

### Client Deployment

- [ ] Ensure WSUS server is fully configured (above steps completed)
- [ ] Launch 15 EC2 instances with `wsus-client-userdata.ps1` as user data
- [ ] Wait 10-15 minutes
- [ ] Check WSUS Console → Computers → All Computers
- [ ] Verify all 15 clients appear

**Total Time**: 15 minutes after launch

---

## 🔍 VERIFICATION COMMANDS

### On WSUS Server

```powershell
# Check services
Get-Service WsusService, "MSSQL`$MICROSOFT##WID" | Format-Table -AutoSize

# Check WSUS connectivity
[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()
$wsus.Name  # Should return server name

# Check synchronization status
$wsus.GetSubscription().GetSynchronizationStatus()
```

### On Client

```powershell
# Check registry
reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate

# Test connectivity
Test-NetConnection 10.50.5.96 -Port 8530

# Force detection
wuauclt /detectnow /reportnow
```

---

## 🎯 FINAL FILE LIST

### For WSUS Server:
1. **`wsus-server-initial-install.ps1`** - Use as EC2 user data
2. **`wsus-post-reboot-setup.ps1`** - Run after reboot (existing file)
3. **GUI Wizard** - Complete manually in WSUS console

### For Clients:
1. **`wsus-client-userdata.ps1`** - Use as EC2 user data (READY TO USE!)

### Optional/Reference:
- `wsus-gpo-configuration.ps1` - If using GPO (Domain Controller required)
- `wsus-client-reset.ps1` - For troubleshooting clients
- `wsus-diagnose.ps1` - For diagnosing WSUS issues
- `WSUS-COMPLETE-WORKING-SETUP-GUIDE.md` - Comprehensive guide

---

## ⚡ QUICK START SUMMARY

### WSUS Server (One-Time Setup):
1. Launch EC2 with `wsus-server-initial-install.ps1` as user data
2. After reboot: Run `wsus-post-reboot-setup.ps1`
3. Complete WSUS GUI wizard (5 min)

### Clients (Fully Automated):
1. Launch 15 EC2 instances with `wsus-client-userdata.ps1` as user data
2. Wait 10-15 minutes
3. Check WSUS console - all clients will appear automatically!

---

## 💡 IMPORTANT NOTES

1. **The GUI wizard CANNOT be automated** - it's a Microsoft requirement to initialize the WSUS database. This is a one-time 5-minute task.

2. **Client configuration is 100% automated** - tested and working. The script you have is ready to deploy.

3. **After WSUS server is configured once**, you never need to do it again. Just deploy clients!

4. **For future WSUS servers**, you'll need to repeat the server setup (including GUI wizard). But this is typically a one-time infrastructure setup.

---

## 🎊 YOU'RE READY TO DEPLOY!

Your `wsus-client-userdata.ps1` is **tested and working**.

Just launch your 15 EC2 instances with this script as user data, and they'll automatically configure themselves and appear in your WSUS console within 10-15 minutes!

---

**Last Updated**: February 5, 2026
**Status**: ✅ Production Ready
**Client Script Status**: ✅ Tested and Working
**WSUS Server Status**: ✅ Fully Operational
