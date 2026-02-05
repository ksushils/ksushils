# WSUS Complete Setup - Final Working Steps

**Created**: February 5, 2026
**Status**: ✅ Tested and Working
**Environment**: AWS EC2, Windows Server 2022, WSUS Server IP: 10.50.5.96

---

## 📋 Overview

This document contains the **EXACT steps that successfully configured WSUS** on Windows Server EC2.

**What Works**:
- ✅ WSUS Server Setup (90% automated, one GUI step required)
- ✅ Client Configuration (100% automated via EC2 user data)
- ✅ Registry-based configuration (no Domain Controller needed)

---

## 🚀 PART 1: WSUS SERVER SETUP

### Prerequisites

- **Instance Type**: t3.medium or larger (2 vCPU, 4GB RAM minimum)
- **Storage**: 50GB root volume + 100GB for WSUS content
- **Network**: Static private IP (10.50.5.96), port 8530 open
- **OS**: Windows Server 2016, 2019, or 2022

---

### Step 1: Initial Installation (EC2 User Data)

**File**: `wsus-server-initial-install.ps1`

Use this as **EC2 User Data** when launching the WSUS server:

```powershell
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
```

**What this does**:
1. ✅ Removes SQL Server Connectivity conflict (UpdateServices-DB)
2. ✅ Installs WSUS with Windows Internal Database (WID)
3. ✅ Installs management tools
4. ✅ Schedules automatic reboot in 60 seconds

**Expected Result**: Server will reboot after 5-10 minutes

**Time**: ~10 minutes including reboot

---

### Step 2: Post-Reboot Configuration

**File**: `wsus-post-reboot-setup.ps1`

After the server reboots, run this script:

**How to run**:
1. RDP into the server
2. Copy `wsus-post-reboot-setup.ps1` to the server (e.g., `C:\wsus-post-reboot-setup.ps1`)
3. Open PowerShell as Administrator
4. Run: `.\wsus-post-reboot-setup.ps1`

**What this script does**:
1. ✅ Verifies wsusutil.exe exists
2. ✅ Creates WSUS content directory (C:\WSUS)
3. ✅ Runs `wsusutil.exe postinstall CONTENT_DIR=C:\WSUS`
4. ✅ Starts WID service (Windows Internal Database)
5. ✅ Starts WSUS service
6. ✅ Restarts IIS
7. ✅ Configures firewall rules (ports 8530, 8531)
8. ✅ Configures WSUS to sync from Microsoft Update

**Expected Output**:
```
========================================
WSUS Setup Complete!
========================================

WSUS Server URL: http://EC2AMAZ-xxxxx:8530

Next Steps:
1. Open 'Windows Server Update Services' from Server Manager
2. Run initial synchronization
3. Configure products and classifications
4. Configure client computers to use this WSUS server
```

**Time**: 2-3 minutes

---

### Step 3: Complete WSUS Configuration Wizard (MANUAL - Required)

⚠️ **This step CANNOT be automated** - Microsoft requires the GUI wizard to initialize the WSUS database properly.

**Steps**:

1. **Open WSUS Console**:
   - Open **Server Manager**
   - Click **Tools** → **Windows Server Update Services**
   - The WSUS Configuration Wizard will launch

2. **Complete the Wizard**:

   **Screen 1: Before You Begin**
   - Click **Next**

   **Screen 2: Join Microsoft Update Improvement Program**
   - Uncheck if you don't want to participate
   - Click **Next**

   **Screen 3: Choose Upstream Server** ⭐ **IMPORTANT**
   - Select: **Synchronize from Microsoft Update**
   - Click **Next**

   **Screen 4: Specify Proxy Server**
   - Leave blank (no proxy)
   - Click **Next**

   **Screen 5: Connect to Upstream Server**
   - Click **Start Connecting**
   - **⏱ Wait 2-5 minutes** for connection
   - Click **Next**

   **Screen 6: Choose Languages**
   - Select languages needed (English is default)
   - Click **Next**

   **Screen 7: Choose Products** ⭐ **IMPORTANT**
   - Expand **Windows** and select:
     - ✅ Windows Server 2016
     - ✅ Windows Server 2019
     - ✅ Windows Server 2022
   - Click **Next**

   **Screen 8: Choose Classifications** ⭐ **IMPORTANT**
   - Select:
     - ✅ Critical Updates
     - ✅ Security Updates
     - ✅ Definition Updates
     - ✅ Update Rollups
   - Click **Next**

   **Screen 9: Set Sync Schedule**
   - Select: **Synchronize automatically**
   - First synchronization: **Daily**
   - Time: **2:00 AM**
   - Click **Next**

   **Screen 10: Finished** ⭐ **IMPORTANT**
   - ✅ **CHECK**: "Begin initial synchronization"
   - Click **Finish**

3. **Verify WSUS is Working**:
   - You should see synchronization starting
   - Status will show: **Synchronizing (0-100%)**
   - Port: **8530**
   - Connection: **Local/SSL**

**Time**: 5 minutes (wizard) + 15-30 minutes (initial sync)

---

### Step 4: Verify WSUS Server

Run these commands on the WSUS server to verify:

```powershell
# Check services are running
Get-Service WsusService, "MSSQL`$MICROSOFT##WID" | Format-Table -AutoSize

# Should show:
# Name                 Status StartType
# ----                 ------ ---------
# WsusService          Running Automatic
# MSSQL$MICROSOFT##WID Running Automatic

# Check port 8530 is listening
Get-NetTCPConnection -LocalPort 8530

# Should show:
# LocalAddress  LocalPort RemoteAddress State
# ------------  --------- ------------- -----
# 0.0.0.0       8530      0.0.0.0       Listen

# Check firewall rules
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*WSUS*" }

# Should show rules for ports 8530 and 8531
```

**WSUS Server Setup Complete!** ✅

---

## 🖥️ PART 2: CLIENT CONFIGURATION

### Client Setup (100% Automated)

**File**: `wsus-client-userdata.ps1`

This script is **100% automated** and ready to use as EC2 user data.

**How to use**:

#### Option A: Terraform

```hcl
resource "aws_instance" "wsus_clients" {
  count         = 15
  ami           = "ami-xxxxx"  # Windows Server 2022 AMI
  instance_type = "t3.small"
  subnet_id     = var.private_subnet_id

  # Use the client script as user data
  user_data = file("${path.module}/wsus-client-userdata.ps1")

  vpc_security_group_ids = [aws_security_group.wsus_clients.id]

  tags = {
    Name = "WSUS-Client-${count.index + 1}"
  }
}
```

#### Option B: AWS Console

1. Launch EC2 Windows instance
2. In **User Data** section, paste the contents of `wsus-client-userdata.ps1`
3. Launch instance

#### Option C: Manual Execution

If instance is already running:
1. Copy `wsus-client-userdata.ps1` to the client
2. Open PowerShell as Administrator
3. Run: `.\wsus-client-userdata.ps1`

---

### What the Client Script Does

1. ✅ Tests connectivity to WSUS server (10.50.5.96:8530)
2. ✅ Creates registry keys for WSUS configuration
3. ✅ Sets WUServer and WUStatusServer to `http://10.50.5.96:8530`
4. ✅ Enables WSUS usage (UseWUServer = 1)
5. ✅ Configures automatic updates (AUOptions = 4)
6. ✅ Sets update schedule (Daily at 3:00 AM)
7. ✅ Sets detection frequency (Every 4 hours)
8. ✅ **Sets Windows Update service to Automatic startup** (critical fix)
9. ✅ **Starts Windows Update service** (critical fix)
10. ✅ Clears Windows Update cache
11. ✅ Forces detection and reporting
12. ✅ Creates scheduled task for periodic reporting (every 6 hours)

**Expected Result**:
- Client configures successfully
- Log file created at `C:\wsus-client-setup.log`
- Configuration summary saved to `C:\WSUS-Client-Configuration.txt`
- Client appears in WSUS console within **10-30 minutes**

---

### Verify Client Configuration

Run these commands on the client:

```powershell
# 1. Check registry settings
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# Should show:
# WUServer: http://10.50.5.96:8530
# WUStatusServer: http://10.50.5.96:8530

reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

# Should show:
# UseWUServer: 0x1
# AUOptions: 0x4
# NoAutoUpdate: 0x0

# 2. Check Windows Update service
Get-Service wuauserv | Format-List Status, StartType

# Should show:
# Status    : Running
# StartType : Automatic

# 3. Test connectivity
Test-NetConnection 10.50.5.96 -Port 8530

# Should show:
# TcpTestSucceeded : True

# 4. Force detection (if needed)
wuauclt /detectnow /reportnow
usoclient StartScan
```

---

## 🔍 TROUBLESHOOTING

### Client Not Appearing in WSUS Console

If client doesn't appear after 30 minutes:

#### On Client: Run Troubleshooting Script

**File**: `wsus-client-troubleshooting.ps1`

```powershell
.\wsus-client-troubleshooting.ps1
```

This will:
- Check all registry settings
- Verify service status
- Test connectivity
- Generate Windows Update logs
- Force detection and reporting
- Provide specific recommendations

#### On Server: Check WSUS Server Health

**File**: `WSUS-SERVER-CHECK.md`

Run these checks:

```powershell
# 1. Check services
Get-Service WsusService, "MSSQL`$MICROSOFT##WID", W3SVC | Format-Table

# 2. Check port 8530
Get-NetTCPConnection -LocalPort 8530

# 3. Check IIS Application Pool
Import-Module WebAdministration
Get-WebAppPoolState

# If WsusPool is stopped, start it:
Start-WebAppPool -Name "WsusPool"

# 4. Restart WSUS service
Restart-Service WsusService -Force
iisreset /restart

# 5. Check for computers in console
# Open WSUS Console → Computers → Unassigned Computers
# Client may appear here first
```

#### Common Issues

**Issue 1: Windows Update service stopped**
```powershell
# Solution:
Set-Service -Name wuauserv -StartupType Automatic
Start-Service -Name wuauserv
wuauclt /detectnow /reportnow
```

**Issue 2: Registry keys not set**
```powershell
# Solution: Re-run client script
.\wsus-client-userdata.ps1
```

**Issue 3: Cannot connect to WSUS server**
```powershell
# Check:
# 1. WSUS server is running
# 2. Port 8530 is listening on server
# 3. Security groups allow port 8530
# 4. Network connectivity

Test-NetConnection 10.50.5.96 -Port 8530
```

**Issue 4: IIS Application Pool stopped**
```powershell
# On server:
Import-Module WebAdministration
Start-WebAppPool -Name "WsusPool"
iisreset /restart
```

---

## 📊 VERIFICATION CHECKLIST

### WSUS Server Checklist

- [ ] WSUS features installed successfully
- [ ] Server rebooted after installation
- [ ] `wsus-post-reboot-setup.ps1` executed successfully
- [ ] WSUS Configuration Wizard completed in GUI
- [ ] Initial synchronization started
- [ ] Services running:
  - [ ] WsusService: Running, Automatic
  - [ ] MSSQL$MICROSOFT##WID: Running, Automatic
  - [ ] W3SVC (IIS): Running, Automatic
- [ ] Port 8530 listening
- [ ] Firewall rules created for ports 8530, 8531
- [ ] WSUS console opens without errors
- [ ] Synchronization status shows "Succeeded"

### Client Checklist

- [ ] `wsus-client-userdata.ps1` executed successfully
- [ ] Registry keys set correctly:
  - [ ] WUServer: http://10.50.5.96:8530
  - [ ] WUStatusServer: http://10.50.5.96:8530
  - [ ] UseWUServer: 1
  - [ ] NoAutoUpdate: 0
  - [ ] AUOptions: 4
- [ ] Windows Update service:
  - [ ] Status: Running
  - [ ] StartType: Automatic
- [ ] Connectivity test passes: `Test-NetConnection 10.50.5.96 -Port 8530`
- [ ] Log file created: `C:\wsus-client-setup.log`
- [ ] Detection commands executed
- [ ] Wait 10-30 minutes
- [ ] Client appears in WSUS console (Computers → All Computers or Unassigned Computers)

---

## 📁 FILES SUMMARY

### For WSUS Server:
1. **`wsus-server-initial-install.ps1`** - EC2 user data for initial install (THIS FILE)
2. **`wsus-post-reboot-setup.ps1`** - Run after reboot (EXISTS)
3. **WSUS Configuration Wizard** - Complete in GUI (5 minutes)

### For Clients:
1. **`wsus-client-userdata.ps1`** - EC2 user data for clients (EXISTS, TESTED ✅)

### For Troubleshooting:
1. **`wsus-client-troubleshooting.ps1`** - Client diagnostics (NEW ✅)
2. **`WSUS-SERVER-CHECK.md`** - Server health checks (NEW ✅)
3. **`wsus-diagnose.ps1`** - Server diagnostics (EXISTS)

### Documentation:
1. **`FINAL-WORKING-SETUP-STEPS.md`** - This file (the complete guide)
2. **`WSUS-FINAL-DEPLOYMENT-GUIDE.md`** - Quick deployment reference
3. **`WSUS-COMPLETE-WORKING-SETUP-GUIDE.md`** - Detailed technical guide

---

## ⚡ QUICK START SUMMARY

### For WSUS Server (One-Time Setup):

```bash
# Step 1: Launch EC2 with wsus-server-initial-install.ps1 as user data
# ⏱ Wait 10 minutes (installation + reboot)

# Step 2: After reboot, RDP to server and run:
.\wsus-post-reboot-setup.ps1
# ⏱ Wait 3 minutes

# Step 3: Complete GUI wizard
# Open Server Manager → Tools → Windows Server Update Services
# Follow wizard (5 minutes)
# ⏱ Wait 15-30 minutes for initial sync

# ✅ WSUS Server Ready!
```

### For Clients (Fully Automated):

```bash
# Launch 15 EC2 instances with wsus-client-userdata.ps1 as user data
# ⏱ Wait 10-30 minutes
# ✅ Check WSUS Console → Computers → All Computers
```

---

## 🎯 IMPORTANT NOTES

1. **The GUI wizard CANNOT be automated** - It's a Microsoft requirement to initialize the WSUS database. This is a **one-time 5-minute task**.

2. **Client configuration is 100% automated** - The `wsus-client-userdata.ps1` script is tested and working.

3. **Timing is important**:
   - WSUS server setup: ~30-45 minutes total (including sync)
   - Client registration: 10-30 minutes after configuration
   - Don't panic if clients don't appear immediately

4. **Check "Unassigned Computers" first** - Clients often appear here before "All Computers"

5. **PowerShell API may fail but GUI works** - This is OK. COM registration issue doesn't affect functionality.

6. **Windows Update service MUST be running** - The script sets it to Automatic and starts it.

---

## 🎊 SUCCESS CRITERIA

Your setup is successful when:

**WSUS Server**:
- ✅ WSUS Console opens without errors
- ✅ Synchronization Status shows "Succeeded"
- ✅ Port 8530 is listening
- ✅ WID and WSUS services running
- ✅ Updates available for approval

**Clients**:
- ✅ Registry configured correctly
- ✅ Windows Update service running and set to Automatic
- ✅ Connectivity test to 10.50.5.96:8530 passes
- ✅ Clients appear in WSUS Console → Computers
- ✅ Last Contact time shows recent timestamp

---

## 📞 NEED HELP?

Run diagnostics:

**On Client**:
```powershell
.\wsus-client-troubleshooting.ps1
```

**On Server**:
```powershell
.\wsus-diagnose.ps1
```

Check logs:
- Server: `C:\wsus-initial-install.log`, `C:\wsus-post-reboot-setup.log`
- Client: `C:\wsus-client-setup.log`
- Windows Update log: Run `Get-WindowsUpdateLog` on client (creates log on desktop)

---

**Last Updated**: February 5, 2026
**Status**: ✅ Production Ready
**Tested On**: Windows Server 2022 on AWS EC2
**WSUS Server**: 10.50.5.96:8530
**Client Script**: ✅ Tested and Working

---

**END OF GUIDE**
