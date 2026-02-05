# WSUS Complete Working Setup Guide - EC2 Windows Server

**This document contains the EXACT steps that successfully installed and configured WSUS on Windows Server EC2.**

Based on real implementation: February 5, 2026

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Complete Installation Steps](#complete-installation-steps)
4. [Post-Installation Client Setup](#post-installation-client-setup)
5. [Troubleshooting](#troubleshooting)
6. [Automation for EC2 User Data](#automation-for-ec2-user-data)

---

## Overview

WSUS installation on Windows Server requires **THREE PHASES**:
1. **Phase 1**: Install Windows Features (requires reboot)
2. **Phase 2**: Run post-install configuration (after reboot)
3. **Phase 3**: Complete WSUS Configuration Wizard (GUI)

**Total Time**: 30-45 minutes

---

## Prerequisites

- **OS**: Windows Server 2016, 2019, or 2022
- **Instance Type**: Minimum t3.medium (2 vCPU, 4GB RAM)
- **Storage**:
  - Root volume: 50GB minimum
  - Additional volume for WSUS content: 100GB+ recommended
- **Network**:
  - Static private IP (recommended)
  - Security group with port 8530 open (TCP inbound)
- **Permissions**: Administrator access

---

## Complete Installation Steps

### Phase 1: Install WSUS Windows Features

**⚠️ CRITICAL**: If `UpdateServices-DB` (SQL Server Connectivity) is already installed, it MUST be removed first to avoid conflict.

#### Step 1.1: Check for Conflicts

```powershell
# Check if SQL Server Connectivity is installed
Get-WindowsFeature -Name "UpdateServices-DB"
```

**If it shows `Installed: True`**, remove it:

```powershell
Uninstall-WindowsFeature -Name "UpdateServices-DB"
```

#### Step 1.2: Install WSUS

```powershell
# Install WSUS with Windows Internal Database
Install-WindowsFeature -Name UpdateServices -IncludeManagementTools
```

**Expected Output**:
```
Success Restart Needed Exit Code      Feature Result
------- -------------- ---------      --------------
True    Yes            SuccessRest... {Windows Server Update Services, WID Connectivity...}
WARNING: You must restart this server to finish the installation process.
```

#### Step 1.3: Reboot the Server

**⚠️ MANDATORY REBOOT**

```powershell
Restart-Computer -Force
```

**Why reboot is required**:
- Removes `UpdateServices-DB` completely
- Installs `UpdateServices` components
- Creates necessary file structure
- Registers COM components
- Installs `wsusutil.exe` binary

**Wait for server to fully restart (2-3 minutes)**

---

### Phase 2: Post-Reboot Configuration

After the server reboots, run these commands to complete the installation.

#### Step 2.1: Verify Installation

```powershell
# Verify wsusutil.exe exists
Test-Path "C:\Program Files\Update Services\Tools\wsusutil.exe"
# Should return: True
```

**If it returns `False`**, WSUS did not install properly. Re-run Phase 1.

#### Step 2.2: Create WSUS Content Directory

```powershell
# Create directory for update files
New-Item -Path "C:\WSUS" -ItemType Directory -Force
```

#### Step 2.3: Run WSUS Post-Install

```powershell
# Run post-installation configuration
& "C:\Program Files\Update Services\Tools\wsusutil.exe" postinstall CONTENT_DIR=C:\WSUS

# Wait for completion
Start-Sleep -Seconds 30
```

**Expected Output**:
```
Log file is located at C:\Users\...\WSUS_PostInstall_20260205T123657.log
Post install is starting
Post install has successfully completed
```

#### Step 2.4: Start Required Services

```powershell
# Start Windows Internal Database
Start-Service -Name "MSSQL`$MICROSOFT##WID"
Set-Service -Name "MSSQL`$MICROSOFT##WID" -StartupType Automatic

# Start WSUS Service
Start-Service -Name WsusService
Set-Service -Name WsusService -StartupType Automatic

# Restart IIS
iisreset /restart

# Wait for services to initialize
Start-Sleep -Seconds 15
```

#### Step 2.5: Configure Firewall

```powershell
# Open WSUS ports
New-NetFirewallRule -DisplayName "WSUS HTTP (8530)" -Direction Inbound -LocalPort 8530 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WSUS HTTPS (8531)" -Direction Inbound -LocalPort 8531 -Protocol TCP -Action Allow
```

---

### Phase 3: Complete WSUS Configuration Wizard (GUI)

**⚠️ REQUIRED**: The GUI wizard must be run to initialize the WSUS database properly.

#### Step 3.1: Open WSUS Console

```powershell
# Open Server Manager
Start-Process "C:\Windows\System32\ServerManager.exe"
```

**In Server Manager**:
1. Click **Tools** (top-right menu)
2. Select **Windows Server Update Services**
3. The WSUS Configuration Wizard will launch

#### Step 3.2: Complete Configuration Wizard

Follow these steps in the wizard:

**Screen 1: Before You Begin**
- Click **Next**

**Screen 2: Join Microsoft Update Improvement Program** (Optional)
- Uncheck if you don't want to participate
- Click **Next**

**Screen 3: Choose Upstream Server** ⭐ IMPORTANT
- Select: **Synchronize from Microsoft Update**
- Click **Next**

**Screen 4: Specify Proxy Server** (Optional)
- Leave blank unless you have a proxy server
- Click **Next**

**Screen 5: Connect to Upstream Server**
- Click **Start Connecting**
- **Wait 2-5 minutes** for connection to complete
- Click **Next**

**Screen 6: Choose Languages**
- Select languages you need (English is default)
- Click **Next**

**Screen 7: Choose Products** ⭐ IMPORTANT
- Expand **Windows** and select:
  - ✅ Windows Server 2016
  - ✅ Windows Server 2019
  - ✅ Windows Server 2022
  - ✅ Windows 10 (if you have Windows 10 clients)
  - ✅ Windows 11 (if you have Windows 11 clients)
- Click **Next**

**Screen 8: Choose Classifications** ⭐ IMPORTANT
- Select:
  - ✅ Critical Updates
  - ✅ Security Updates
  - ✅ Definition Updates
  - ✅ Update Rollups
  - ✅ Updates
- Click **Next**

**Screen 9: Set Sync Schedule**
- Select: **Synchronize automatically**
- First synchronization: **Daily**
- Time: **2:00 AM** (or your preferred time)
- Click **Next**

**Screen 10: Finished** ⭐ IMPORTANT
- ✅ **Check**: "Begin initial synchronization"
- Click **Finish**

#### Step 3.3: Verify WSUS is Working

After the wizard completes, you should see:

- **Synchronization Status**: Synchronizing (0-100%)
- **Port**: 8530
- **Connection**: Local/SSL
- **Status**: Running

**Initial synchronization will take 15-30 minutes** depending on internet speed.

---

## Post-Installation Client Setup

Now that WSUS server is running, configure your client servers to use it.

### Option A: Using Group Policy (Domain Environment)

Run this on your **Domain Controller**:

```powershell
# Import the GPO configuration script
.\wsus-gpo-configuration.ps1

# Edit these variables in the script:
# $WSUSServer = "10.50.5.96"  # Your WSUS server IP
# $TargetOU = "OU=Servers,DC=yourdomain,DC=com"
```

### Option B: Using Registry (Non-Domain / Workgroup)

Run this on **each client server**:

```powershell
# Use the client configuration script
.\wsus-client-userdata.ps1

# Edit this variable in the script:
# $WSUSServer = "10.50.5.96"  # Your WSUS server IP
```

Or configure manually:

```powershell
# Set WSUS server location
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer" -Value "http://10.50.5.96:8530"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUStatusServer" -Value "http://10.50.5.96:8530"

# Enable WSUS
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "UseWUServer" -Value 1

# Configure automatic updates
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Value 4

# Force detection
wuauclt /detectnow /reportnow
```

### Verify Client Registration

**On the client**:
```powershell
# Check registry
reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate

# Test connectivity
Test-NetConnection 10.50.5.96 -Port 8530
```

**On the WSUS server**:
1. Open WSUS Console
2. Go to: **Computers** → **All Computers**
3. Wait 10-15 minutes for clients to appear

---

## Troubleshooting

### Issue 1: "WID Connectivity has a conflict with SQL Server Connectivity"

**Cause**: `UpdateServices-DB` feature is already installed

**Solution**:
```powershell
Uninstall-WindowsFeature -Name "UpdateServices-DB"
Restart-Computer -Force
# After reboot, re-run installation
```

---

### Issue 2: "wsusutil.exe not found" after installation

**Cause**: Server needs reboot to complete installation

**Solution**:
```powershell
# Check if reboot is pending
Get-WindowsFeature | Where-Object { $_.Name -like "UpdateServices*" }

# If InstallState shows "InstallPending", reboot is required
Restart-Computer -Force
```

---

### Issue 3: "WsusInvalidServerException" when connecting

**Cause**: WSUS Configuration Wizard has not been run

**Solution**:
- Open WSUS Console via Server Manager
- Complete the Configuration Wizard (Phase 3)
- This initializes the database properly

---

### Issue 4: Clients don't appear in WSUS console

**Solutions**:

1. **Check registry on client**:
```powershell
reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
# Should show WUServer and WUStatusServer
```

2. **Reset client**:
```powershell
Stop-Service wuauserv
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Recurse -Force
Start-Service wuauserv
wuauclt /resetauthorization /detectnow /reportnow
```

3. **Check firewall**:
```powershell
Test-NetConnection 10.50.5.96 -Port 8530
# Should return: TcpTestSucceeded : True
```

---

## Automation for EC2 User Data

For full automation, use a **two-script approach**:

### Script 1: EC2 User Data (Initial Launch)

**File**: `wsus-server-initial-setup.ps1`

```powershell
<powershell>
# Remove SQL Server Connectivity if exists
$sqlConn = Get-WindowsFeature -Name "UpdateServices-DB" -ErrorAction SilentlyContinue
if ($sqlConn -and $sqlConn.Installed) {
    Uninstall-WindowsFeature -Name "UpdateServices-DB"
}

# Install WSUS
Install-WindowsFeature -Name UpdateServices -IncludeManagementTools

# Schedule reboot
shutdown /r /t 60 /c "Rebooting to complete WSUS installation"
</powershell>
```

### Script 2: Run After Reboot

**File**: `wsus-post-reboot-setup.ps1`

Use the script we created: `wsus-post-reboot-setup.ps1`

**To run automatically after reboot**, create a scheduled task:

```powershell
# Create scheduled task to run at startup (one-time)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\wsus-post-reboot-setup.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "WSUS-Post-Reboot-Setup" -Action $action -Trigger $trigger -Principal $principal -Settings $settings
```

**Note**: The GUI Configuration Wizard (Phase 3) still needs to be run manually once. This cannot be fully automated.

---

## Summary: What Actually Worked

**The Complete Working Procedure**:

1. ✅ Remove `UpdateServices-DB` if installed
2. ✅ Install `UpdateServices` with `IncludeManagementTools`
3. ✅ **REBOOT** (mandatory)
4. ✅ After reboot: Run `wsusutil.exe postinstall`
5. ✅ Start WID and WSUS services
6. ✅ Restart IIS
7. ✅ Configure firewall rules
8. ✅ **Run WSUS Configuration Wizard via GUI** (mandatory)
9. ✅ Configure clients to point to WSUS server

**Key Learnings**:
- Reboot is **mandatory** after feature installation
- GUI Configuration Wizard is **required** to initialize database
- WID service must be running before WSUS can connect
- Port 8530 must be open in security groups
- Clients take 10-15 minutes to appear in WSUS console

---

## Files in This Repository

| File | Purpose |
|------|---------|
| `wsus-server-userdata.ps1` | Original full automation script (complex) |
| `wsus-post-reboot-setup.ps1` | ✅ **Use this after reboot** |
| `wsus-client-userdata.ps1` | Client configuration for EC2 user data |
| `wsus-gpo-configuration.ps1` | GPO automation for domain environments |
| `wsus-client-reset.ps1` | Troubleshooting script for clients |
| `wsus-diagnose.ps1` | Diagnostic script for troubleshooting |
| `WSUS-SETUP-README.md` | Original comprehensive guide |
| **`WSUS-COMPLETE-WORKING-SETUP-GUIDE.md`** | ✅ **This document - actual working steps** |

---

## Quick Reference Commands

### WSUS Server

```powershell
# Check WSUS service
Get-Service WsusService

# Check WID service
Get-Service "MSSQL`$MICROSOFT##WID"

# Open WSUS console
Start-Process "C:\Windows\System32\ServerManager.exe"
# Then: Tools > Windows Server Update Services

# Check synchronization status
Get-WsusServer | Get-WsusSubscription
```

### WSUS Client

```powershell
# Check configuration
reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate

# Force detection
wuauclt /detectnow /reportnow

# Test connectivity
Test-NetConnection <WSUS-Server-IP> -Port 8530

# Reset client
Stop-Service wuauserv
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Recurse -Force
Start-Service wuauserv
wuauclt /resetauthorization /detectnow /reportnow
```

---

## Security Group Configuration (AWS)

### WSUS Server Security Group

**Inbound Rules**:
| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| Custom TCP | TCP | 8530 | VPC CIDR (10.50.0.0/16) | WSUS HTTP |
| Custom TCP | TCP | 8531 | VPC CIDR (10.50.0.0/16) | WSUS HTTPS (optional) |
| RDP | TCP | 3389 | Admin IP | Management |

**Outbound Rules**:
| Type | Protocol | Port | Destination | Description |
|------|----------|------|-------------|-------------|
| HTTP | TCP | 80 | 0.0.0.0/0 | Download updates |
| HTTPS | TCP | 443 | 0.0.0.0/0 | Download updates |

### Client Server Security Group

**Outbound Rules**:
| Type | Protocol | Port | Destination | Description |
|------|----------|------|-------------|-------------|
| Custom TCP | TCP | 8530 | WSUS Server IP | Connect to WSUS |

---

## Success Criteria

Your WSUS server is successfully configured when:

✅ WSUS Console opens without errors
✅ Synchronization Status shows "Succeeded"
✅ Port 8530 is listening
✅ WID service is running
✅ WSUS service is running
✅ Clients appear in "All Computers" after 10-15 minutes
✅ Updates can be approved and deployed

---

**Document Version**: 1.0
**Last Updated**: February 5, 2026
**Status**: ✅ Verified Working
**Tested On**: Windows Server 2022 on AWS EC2

---

## Support

For issues:
1. Review the [Troubleshooting](#troubleshooting) section
2. Run `wsus-diagnose.ps1` diagnostic script
3. Check logs at `C:\wsus-setup.log` or `C:\wsus-post-reboot-setup.log`
4. Check WSUS post-install log in `%TEMP%\WSUS_PostInstall_*.log`

---

**END OF DOCUMENT**
