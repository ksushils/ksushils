# WSUS Complete Deployment Guide - Production Ready
# Everything That Worked - Full Automation Guide

**Last Updated**: February 6, 2026
**Status**: ✅ Tested and Working
**Environment**: AWS EC2, Domain-Joined (ad.rldatix.cloud)

---

## 📋 TABLE OF CONTENTS

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Part 1: WSUS Server Setup](#part-1-wsus-server-setup)
4. [Part 2: Domain GPO Configuration](#part-2-domain-gpo-configuration)
5. [Part 3: Client Registration](#part-3-client-registration)
6. [Automation Strategy](#automation-strategy)
7. [Troubleshooting Quick Reference](#troubleshooting-quick-reference)

---

## 🏗️ ARCHITECTURE OVERVIEW

```
┌─────────────────────────────────────────────────────────────┐
│                     ad.rldatix.cloud                         │
│                                                              │
│  ┌──────────────────┐      ┌──────────────────┐            │
│  │ Domain Controller│      │   WSUS Server    │            │
│  │   10.50.5.31     │◄────►│   10.50.6.69     │            │
│  │                  │      │   Port: 8530     │            │
│  │  - Active Dir    │      │   - WID Database │            │
│  │  - GPO: "WSUS    │      │   - IIS          │            │
│  │    update"       │      │   - WSUS Service │            │
│  └──────────────────┘      └──────────────────┘            │
│           │                          ▲                       │
│           │                          │                       │
│           │                          │                       │
│  ┌────────▼──────────────────────────┴─────────────────┐   │
│  │         30-40 Domain-Joined Clients                  │   │
│  │  - Auto-apply GPO via domain membership             │   │
│  │  - Register with WSUS automatically                 │   │
│  │  - ServerSelection: 1 (WSUS)                        │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**Key Points**:
- ✅ Clients are **domain-joined** (ad.rldatix.cloud)
- ✅ WSUS configured via **Domain Group Policy** (not local registry)
- ✅ Domain GPO applies to ALL computers automatically
- ✅ No per-client configuration needed (except optional forced update)

---

## ✅ PREREQUISITES

### AWS Infrastructure

1. **WSUS Server EC2 Instance**
   - Instance Type: `t3.medium` minimum (2 vCPU, 4GB RAM)
   - Storage: 100GB+ for updates
   - OS: Windows Server 2019/2022
   - Private IP: Static (e.g., 10.50.6.69)

2. **Security Groups**
   - **WSUS Server Inbound**: TCP 8530 from client subnets
   - **WSUS Server Outbound**: TCP 443 to internet (Microsoft Update)
   - **Clients Outbound**: TCP 8530 to WSUS server

3. **Domain Environment**
   - Active Directory Domain: `ad.rldatix.cloud`
   - Domain Controller: Accessible (e.g., 10.50.5.31)
   - Domain Admin credentials

### Required Scripts (All in Repository)

- `wsus-server-initial-install.ps1` - WSUS server installation
- `wsus-post-reboot-setup.ps1` - Post-reboot configuration
- `wsus-client-domain-joined.ps1` - Client setup (optional, for faster rollout)

---

## 🚀 PART 1: WSUS SERVER SETUP

### Step 1.1: Launch WSUS Server EC2 Instance

**Option A: Terraform**

```hcl
resource "aws_instance" "wsus_server" {
  ami           = "ami-xxxxx"  # Windows Server 2022
  instance_type = "t3.medium"
  subnet_id     = var.private_subnet_id

  # Static private IP
  private_ip = "10.50.6.69"

  # IMPORTANT: Do NOT use user_data for WSUS server
  # Manual setup required due to GUI wizard

  vpc_security_group_ids = [aws_security_group.wsus_server.id]

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }

  tags = {
    Name = "WSUS-Server"
  }
}

resource "aws_security_group" "wsus_server" {
  name = "wsus-server-sg"
  vpc_id = var.vpc_id

  # Allow WSUS clients
  ingress {
    from_port   = 8530
    to_port     = 8530
    protocol    = "tcp"
    cidr_blocks = [var.client_subnet_cidr]
  }

  # Allow RDP for management
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Allow outbound to internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

**Option B: AWS Console**

1. Launch Windows Server 2022 instance
2. Instance type: t3.medium
3. Storage: 100GB
4. Set static private IP in subnet: 10.50.6.69
5. Security group: Allow TCP 8530 inbound from client subnets

---

### Step 1.2: Initial WSUS Installation (90% Automated)

**⚠️ IMPORTANT**: WSUS server setup is **90% automated** with **ONE manual step** (GUI wizard).

**1. RDP to WSUS Server**

**2. Run Initial Install Script**

Copy `wsus-server-initial-install.ps1` to the server and run:

```powershell
.\wsus-server-initial-install.ps1
```

**What it does**:
- Checks for SQL Server Connectivity conflict
- Installs WSUS features with Windows Internal Database (WID)
- Schedules automatic reboot in 60 seconds

**Time**: 10 minutes (including reboot)

**3. After Reboot: Run Post-Install Script**

After server reboots, RDP back in and run:

```powershell
.\wsus-post-reboot-setup.ps1
```

**What it does**:
- Runs `wsusutil.exe postinstall`
- Starts WID and WSUS services
- Restarts IIS
- Configures firewall rules (ports 8530, 8531)

**Time**: 3 minutes

---

### Step 1.3: Complete WSUS GUI Wizard (MANUAL - Required)

**⚠️ THIS STEP CANNOT BE AUTOMATED** - Microsoft requires the GUI wizard to initialize the database.

**Steps**:

1. Open **Server Manager** → **Tools** → **Windows Server Update Services**

2. The WSUS Configuration Wizard will launch automatically

3. **Complete the wizard**:

   - **Screen 1**: Before You Begin → Click **Next**

   - **Screen 2**: Join Microsoft Update Improvement Program → Uncheck → **Next**

   - **Screen 3**: Choose Upstream Server ⭐
     - Select: **"Synchronize from Microsoft Update"**
     - Click **Next**

   - **Screen 4**: Specify Proxy Server → Leave blank → **Next**

   - **Screen 5**: Connect to Upstream Server
     - Click **"Start Connecting"**
     - ⏱️ Wait 2-5 minutes
     - Click **Next**

   - **Screen 6**: Choose Languages → Select English → **Next**

   - **Screen 7**: Choose Products ⭐
     - Expand **Windows**
     - Select: Windows Server 2016, 2019, 2022
     - Click **Next**

   - **Screen 8**: Choose Classifications ⭐
     - Select: Critical Updates, Security Updates, Definition Updates, Update Rollups
     - Click **Next**

   - **Screen 9**: Set Sync Schedule
     - Select: **"Synchronize automatically"**
     - Daily at 2:00 AM
     - Click **Next**

   - **Screen 10**: Finished ⭐
     - ✅ CHECK: "Begin initial synchronization"
     - Click **Finish**

**Time**: 5 minutes (wizard) + 20-30 minutes (initial sync)

**4. Verify WSUS is Working**

In WSUS Console, you should see:
- Port: 8530
- Connection: Local/SSL
- Synchronization starting
- Updates appearing after sync completes

---

### Step 1.4: Verify WSUS Server Health

```powershell
# Check services
Get-Service WsusService, "MSSQL`$MICROSOFT##WID", W3SVC | Format-Table

# Should show:
# WsusService          Running Automatic
# MSSQL$MICROSOFT##WID Running Automatic
# W3SVC                Running Automatic

# Check port 8530
Get-NetTCPConnection -LocalPort 8530

# Should show listening on port 8530

# Test local access
Test-NetConnection -ComputerName localhost -Port 8530
# Should show: TcpTestSucceeded : True
```

**✅ WSUS Server Setup Complete!**

---

## 🎯 PART 2: DOMAIN GPO CONFIGURATION

**⚠️ THIS IS THE CRITICAL STEP FOR DOMAIN-JOINED CLIENTS**

For domain-joined clients, you **MUST** configure WSUS via Domain Group Policy. Local registry settings will NOT work because domain GPO overrides them.

---

### Step 2.1: Open Group Policy Management on Domain Controller

**Option A: Directly on Domain Controller**

1. RDP to Domain Controller (10.50.5.31)
2. Open **Server Manager** → **Tools** → **Group Policy Management**

**Option B: From WSUS Server (Remote Management)**

If you cannot RDP to DC but have domain admin credentials:

```powershell
# On WSUS server, run:
.\wsus-remote-gpo-configuration.ps1
```

This script connects to DC remotely and configures the GPO.

---

### Step 2.2: Create or Update WSUS GPO

**If GPO Already Exists** (Updating for New WSUS Server):

1. In Group Policy Management Console (GPMC)
2. Expand: **Forest** → **Domains** → **ad.rldatix.cloud** → **Group Policy Objects**
3. Find your existing WSUS GPO (e.g., "WSUS update")
4. Right-click → **Edit**
5. **Skip to Step 2.3** below

**If Creating New GPO**:

1. In GPMC, expand: **Forest** → **Domains** → **ad.rldatix.cloud**
2. Right-click **Group Policy Objects** → **New**
3. Name: **"WSUS Configuration"** (or "WSUS update")
4. Click **OK**
5. Right-click the new GPO → **Edit**

---

### Step 2.3: Configure WSUS Settings in GPO

In the Group Policy Management Editor:

**1. Navigate to Windows Update Policies**:

```
Computer Configuration
└── Policies
    └── Administrative Templates
        └── Windows Components
            └── Windows Update
```

**2. Configure: "Specify intranet Microsoft update service location"**

- Double-click the policy
- Set to: **Enabled**
- **Set the intranet update service for detecting updates**: `http://10.50.6.69:8530`
- **Set the intranet statistics server**: `http://10.50.6.69:8530`
- **Set the alternate download server**: **LEAVE BLANK** ⚠️ Important!
- Click **OK**

**3. Configure: "Configure Automatic Updates"**

- Double-click the policy
- Set to: **Enabled**
- **Configure automatic updating**: 4 - Auto download and schedule the install
- **Scheduled install day**: 0 - Every day
- **Scheduled install time**: 03:00
- Click **OK**

**4. Configure: "Automatic Updates detection frequency"**

- Double-click the policy
- Set to: **Enabled**
- **Check for updates at the following interval (hours)**: 4
- Click **OK**

**5. Configure: "Do not connect to any Windows Update Internet locations"**

- Double-click the policy
- Set to: **Enabled**
- Click **OK**

**6. Configure: "No auto-restart with logged on users for scheduled automatic updates installations"**

- Double-click the policy
- Set to: **Enabled**
- Click **OK**

**7. Close the Editor**

---

### Step 2.4: Link GPO to Domain

**If Not Already Linked**:

1. In GPMC, expand: **Forest** → **Domains** → **ad.rldatix.cloud**
2. Right-click the **domain root** (ad.rldatix.cloud) or **Computers OU**
3. Select **"Link an Existing GPO..."**
4. Select your WSUS GPO
5. Click **OK**

**Verify GPO Link**:

1. Click on the domain root or OU where GPO is linked
2. In the right panel, you should see your WSUS GPO listed under "Linked Group Policy Objects"
3. Ensure **"Link Enabled"** shows **Yes**

---

### Step 2.5: Verify GPO Configuration

**On Domain Controller**:

```powershell
# View GPO settings
Get-GPO -Name "WSUS update" | fl

# Check GPO links
Get-GPInheritance -Target "DC=ad,DC=rldatix,DC=cloud" |
  Select-Object -ExpandProperty GpoLinks |
  Where-Object { $_.DisplayName -like "*WSUS*" }
```

**✅ Domain GPO Configuration Complete!**

All domain computers will now receive WSUS settings automatically.

---

## 💻 PART 3: CLIENT REGISTRATION

**Good News**: With Domain GPO configured, clients will automatically get WSUS settings!

---

### Step 3.1: Automatic Registration (No Work Required)

**Timeline**:
- **0-90 minutes**: Clients automatically apply GPO
- **5-10 minutes after GPO**: Clients appear in WSUS console

**What Happens Automatically**:
1. Client applies Domain GPO (every 90 minutes by default)
2. WSUS registry keys are set via GPO
3. Windows Update service picks up settings (may require reboot)
4. Client contacts WSUS server
5. Client appears in WSUS Console → Computers → Unassigned Computers

**No manual configuration needed!**

---

### Step 3.2: Force Immediate Registration (Optional)

If you want clients to register **immediately** instead of waiting up to 90 minutes:

**Option A: Manual (Per Client)**

RDP to each client and run:

```powershell
# Force GPO update
gpupdate /force

# Restart Windows Update service
Restart-Service wuauserv -Force

# Force detection
wuauclt /detectnow /reportnow
usoclient StartScan
```

**Option B: Automated Script (Recommended)**

Copy `wsus-client-domain-joined.ps1` to each client and run:

```powershell
.\wsus-client-domain-joined.ps1
```

**What it does**:
- Forces GPO update
- Clears Windows Update cache
- Deletes SusClientID (forces fresh registration)
- Triggers detection
- Checks if reboot needed

**Option C: Remote Execution (Fastest)**

From any admin workstation with WinRM access:

```powershell
$clients = @(
    "Server1",
    "Server2",
    "Server3"
    # ... all your clients
)

foreach ($client in $clients) {
    Write-Host "Processing $client..." -ForegroundColor Yellow

    try {
        Invoke-Command -ComputerName $client -ScriptBlock {
            gpupdate /force /wait:0
            Stop-Service wuauserv -Force
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name "SusClientId" -ErrorAction SilentlyContinue
            Start-Service wuauserv
            wuauclt /detectnow /reportnow
        }
        Write-Host "  [OK] $client" -ForegroundColor Green
    } catch {
        Write-Host "  [FAILED] $client - $_" -ForegroundColor Red
    }
}
```

---

### Step 3.3: Handle Clients That Need Reboot

Some clients may show **ServerSelection = 0** even after GPO is applied. This means a **reboot is required**.

**To check on a client**:

```powershell
$searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
Write-Host "ServerSelection: $($searcher.ServerSelection)"

# 0 = Windows Update (reboot needed)
# 1 = WSUS (working correctly)
```

**If ServerSelection = 0**: Reboot the client

```powershell
Restart-Computer -Force
```

After reboot, client will use WSUS automatically.

---

### Step 3.4: Verify Client Registration

**Check WSUS Console**:

1. Open WSUS Console on server
2. Expand **Computers** → **Unassigned Computers**
3. Clients should appear here first
4. Right-click clients → Move to appropriate computer group

**Check on Client**:

```powershell
# Verify registry settings
reg query "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# Should show:
# WUServer        REG_SZ    http://10.50.6.69:8530
# WUStatusServer  REG_SZ    http://10.50.6.69:8530

# Check ServerSelection
$searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
$searcher.ServerSelection
# Should be: 1

# Check last detection time
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect" |
  Select-Object LastSuccessTime
```

**✅ Client Registration Complete!**

---

## 🤖 AUTOMATION STRATEGY

Here's what can and cannot be automated:

### ✅ Fully Automated (100%)

**Domain GPO Configuration**: Once set up, applies to ALL computers automatically
- New computers joining the domain get WSUS settings automatically
- No per-computer configuration needed
- Settings update centrally

**Client Registration**: Automatic via domain membership
- Clients auto-register within 90 minutes of joining domain
- Optional: Use `wsus-client-domain-joined.ps1` for immediate registration

### ⚠️ Semi-Automated (90%)

**WSUS Server Installation**:
- **Automated**: Install features, post-install configuration, service startup
- **Manual**: GUI wizard (5 minutes, one-time)

**Breakdown**:
```
EC2 Launch             → Fully automated (Terraform/CloudFormation)
Initial Install Script → Fully automated (EC2 user data not recommended)
Reboot                 → Fully automated
Post-Reboot Script     → Fully automated
GUI Wizard             → ⚠️ MANUAL (5 minutes)
```

### ❌ Cannot Automate

1. **WSUS Configuration Wizard**: Microsoft requires GUI interaction to initialize database
2. **Initial Domain GPO Setup**: One-time GUI configuration (but updates can be scripted)
3. **Approving Updates**: Manual approval in WSUS console (by design for safety)

---

## 📝 COMPLETE DEPLOYMENT CHECKLIST

### Phase 1: Infrastructure (Terraform/Manual)

- [ ] Launch WSUS Server EC2 instance (t3.medium, 100GB storage)
- [ ] Assign static private IP (e.g., 10.50.6.69)
- [ ] Configure security groups (allow TCP 8530 from clients)
- [ ] Join WSUS server to domain (if needed)

### Phase 2: WSUS Server Setup

- [ ] RDP to WSUS server
- [ ] Copy `wsus-server-initial-install.ps1` to server
- [ ] Run: `.\wsus-server-initial-install.ps1`
- [ ] Wait for automatic reboot (10 minutes)
- [ ] After reboot, copy `wsus-post-reboot-setup.ps1` to server
- [ ] Run: `.\wsus-post-reboot-setup.ps1`
- [ ] Open WSUS Console: Server Manager → Tools → Windows Server Update Services
- [ ] Complete WSUS Configuration Wizard (5 minutes)
  - [ ] Connect to Microsoft Update
  - [ ] Select products: Windows Server 2016, 2019, 2022
  - [ ] Select classifications: Critical, Security, Definitions, Update Rollups
  - [ ] Enable automatic synchronization (daily at 2 AM)
  - [ ] ✅ CHECK "Begin initial synchronization"
- [ ] Wait for initial sync to complete (20-30 minutes)
- [ ] Verify: Port 8530 listening, services running

### Phase 3: Domain Group Policy

- [ ] RDP to Domain Controller OR use remote GPO management
- [ ] Open Group Policy Management Console
- [ ] Find or create WSUS GPO ("WSUS update" or "WSUS Configuration")
- [ ] Edit GPO → Computer Config → Policies → Admin Templates → Windows Components → Windows Update
- [ ] Configure "Specify intranet Microsoft update service location"
  - [ ] Enable
  - [ ] Set both URLs to: `http://10.50.6.69:8530`
  - [ ] Leave alternate download server BLANK
- [ ] Configure "Configure Automatic Updates" → Enabled → Option 4
- [ ] Configure "Automatic Updates detection frequency" → Enabled → 4 hours
- [ ] Configure "Do not connect to any Windows Update Internet locations" → Enabled
- [ ] Configure "No auto-restart with logged on users" → Enabled
- [ ] Close editor
- [ ] Link GPO to domain root or Computers OU (if not already linked)
- [ ] Verify GPO link is enabled

### Phase 4: Client Registration

**Option A: Wait (No Work)**
- [ ] Wait 90 minutes for automatic GPO application
- [ ] Check WSUS Console → Computers → Unassigned Computers

**Option B: Force Immediate (Recommended for Testing)**
- [ ] On test client, run: `gpupdate /force`
- [ ] Run: `Restart-Service wuauserv -Force`
- [ ] Run: `wuauclt /detectnow /reportnow`
- [ ] Check ServerSelection: Should be 1
- [ ] If ServerSelection = 0, reboot client
- [ ] Wait 5-10 minutes
- [ ] Verify client appears in WSUS console

### Phase 5: Production Rollout

- [ ] Deploy to first 5 clients and verify
- [ ] Deploy to remaining clients (automatic or use script)
- [ ] Verify all clients appear in WSUS console
- [ ] Organize clients into computer groups
- [ ] Approve updates for testing group
- [ ] Test updates on pilot group
- [ ] Approve updates for production

---

## 🔧 TROUBLESHOOTING QUICK REFERENCE

### Client Not Appearing in WSUS Console

**1. Check GPO Applied**:
```powershell
gpresult /r | Select-String "WSUS"
```

**2. Check Registry**:
```powershell
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
# Should show: WUServer = http://10.50.6.69:8530
```

**3. Check ServerSelection**:
```powershell
$s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
$s.ServerSelection
# Should be: 1 (if 0, reboot required)
```

**4. Check Connectivity**:
```powershell
Test-NetConnection -ComputerName 10.50.6.69 -Port 8530
# Should show: TcpTestSucceeded : True
```

**5. Force Registration**:
```powershell
Stop-Service wuauserv -Force
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name "SusClientId" -ErrorAction SilentlyContinue
Start-Service wuauserv
wuauclt /detectnow /reportnow
```

**6. Check WSUS IIS Logs**:

On WSUS server:
```powershell
$logDir = "C:\inetpub\logs\LogFiles\W3SVC*"
$latestLog = Get-ChildItem $logDir -Filter "*.log" | Sort LastWriteTime -Desc | Select -First 1
Get-Content $latestLog.FullName -Tail 50 | Select-String "10.50"
# Should show client IP making requests
```

### WSUS Server Not Accepting Clients

**1. Check Services**:
```powershell
Get-Service WsusService, "MSSQL`$MICROSOFT##WID", W3SVC
# All should be: Running
```

**2. Check Port 8530**:
```powershell
Get-NetTCPConnection -LocalPort 8530
# Should show: State = Listen
```

**3. Restart Services**:
```powershell
Restart-Service WsusService -Force
iisreset /restart
```

**4. Check IIS Application Pool**:
```powershell
$appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
& $appcmd list apppool "WsusPool"
# Should show: state:Started
```

### Domain GPO Not Applying

**1. Check Computer OU**:
```powershell
$dn = ([ADSI]"LDAP://$env:COMPUTERNAME").distinguishedName
Write-Host $dn
# Should be in OU where GPO is linked
```

**2. Check GPO Link**:

On DC:
```powershell
Get-GPInheritance -Target "DC=ad,DC=rldatix,DC=cloud" |
  Select -ExpandProperty GpoLinks |
  Where { $_.DisplayName -like "*WSUS*" }
```

**3. Force GPO Update**:
```powershell
gpupdate /force /wait:0
```

---

## 📊 FILE REFERENCE

### Scripts You Need

| File | Purpose | When to Use |
|------|---------|-------------|
| `wsus-server-initial-install.ps1` | WSUS feature installation | Once during server setup |
| `wsus-post-reboot-setup.ps1` | Post-reboot configuration | Once after server reboot |
| `wsus-client-domain-joined.ps1` | Force client registration | Optional, for faster rollout |
| `wsus-remote-gpo-configuration.ps1` | Remote GPO configuration | If can't access DC directly |

### Manual Steps Required

1. **WSUS Configuration Wizard** (5 minutes, one-time)
2. **Domain GPO Setup** (5 minutes, one-time via GUI)
3. **Update Approval** (ongoing, via WSUS console)

---

## 🎯 QUICK START (TL;DR)

### For Brand New Setup:

1. **Launch WSUS Server** (EC2 t3.medium, 100GB, static IP)
2. **Install WSUS**: Run `wsus-server-initial-install.ps1` → Reboot → Run `wsus-post-reboot-setup.ps1`
3. **Complete GUI Wizard** (5 minutes, Microsoft Update, select products/classifications)
4. **Configure Domain GPO**: GPMC → Edit "WSUS update" GPO → Set `http://10.50.6.69:8530`
5. **Wait or Force**: Clients auto-register in 90 min OR run `gpupdate /force` on clients

### For Updating Existing WSUS IP:

1. **Edit Domain GPO**: Change IP from old to new (`http://10.50.6.69:8530`)
2. **On Clients**: Run `gpupdate /force` and `Restart-Service wuauserv`
3. **If Needed**: Reboot clients where ServerSelection = 0

---

## ✅ SUCCESS CRITERIA

Your WSUS setup is successful when:

**WSUS Server**:
- ✅ Services running (WsusService, WID, W3SVC)
- ✅ Port 8530 listening
- ✅ WSUS Console shows updates available
- ✅ Synchronization status: Succeeded

**Domain GPO**:
- ✅ "WSUS update" GPO configured with correct IP
- ✅ GPO linked to domain or Computers OU
- ✅ Link enabled

**Clients**:
- ✅ Registry shows: WUServer = http://10.50.6.69:8530
- ✅ ServerSelection = 1
- ✅ Clients appear in WSUS Console → Computers
- ✅ Last Contact time shows recent timestamp

---

## 📞 SUPPORT

If issues persist:

1. Run client troubleshooting: `.\wsus-client-troubleshooting.ps1`
2. Run server diagnostics: `.\wsus-server-fix-iis.ps1`
3. Check logs:
   - Client: `C:\wsus-domain-client-setup.log`
   - Server: `C:\wsus-post-reboot-setup.log`
   - Windows Update: Run `Get-WindowsUpdateLog` on client

---

**END OF GUIDE**

Last Updated: February 6, 2026
Tested Environment: AWS EC2, Windows Server 2022, Domain-Joined
Status: ✅ Production Ready
