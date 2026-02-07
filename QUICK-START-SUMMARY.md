# WSUS Setup - Quick Start Summary
# What Actually Worked - Minimal Steps

**Environment**: Domain-Joined Windows Clients (ad.rldatix.cloud)
**WSUS Server**: 10.50.6.69:8530

---

## 🎯 THE SOLUTION THAT WORKED

**Key Discovery**: For **domain-joined** computers, you MUST use **Domain Group Policy**, not local registry/scripts.

---

## 📋 MINIMAL SETUP STEPS

### STEP 1: WSUS Server (One-Time, 90% Automated)

**Files Needed**:
- `wsus-server-initial-install.ps1`
- `wsus-post-reboot-setup.ps1`

**Process**:
```bash
1. Launch EC2: t3.medium, 100GB, Windows Server 2022, IP: 10.50.6.69
2. Security Group: Allow TCP 8530 from client subnets
3. RDP to server
4. Run: .\wsus-server-initial-install.ps1
5. Wait for automatic reboot (10 min)
6. Run: .\wsus-post-reboot-setup.ps1
7. Complete WSUS GUI Wizard (5 min) ⚠️ MANUAL STEP
   - Connect to Microsoft Update
   - Select products: Windows Server 2016, 2019, 2022
   - Select updates: Critical, Security, Definitions
   - Enable automatic sync
8. Done!
```

**Time**: 30 minutes (including initial sync)

---

### STEP 2: Domain GPO (One-Time, 5 Minutes)

**Where**: Domain Controller (10.50.5.31) OR remote from WSUS server

**Process**:
```bash
1. Open: Group Policy Management Console (gpmc.msc)
2. Edit: "WSUS update" GPO (or create new)
3. Navigate: Computer Config → Policies → Admin Templates → Windows Components → Windows Update
4. Edit: "Specify intranet Microsoft update service location"
   - Enable
   - Set BOTH URLs to: http://10.50.6.69:8530
   - Leave alternate download blank
5. Link: GPO to domain root or Computers OU
6. Done!
```

**Result**: ALL domain computers automatically get WSUS settings!

---

### STEP 3: Clients (Automatic)

**Default Behavior** (No Work):
- Clients automatically apply GPO within 90 minutes
- Clients appear in WSUS console within 2 hours

**Force Immediate** (Optional):

On each client:
```powershell
gpupdate /force
Restart-Service wuauserv -Force
wuauclt /detectnow /reportnow
```

If ServerSelection = 0, reboot client.

---

## 🔑 KEY POINTS

### What Worked ✅

1. **WSUS Server**: 90% automated scripts + 5-minute GUI wizard
2. **Domain GPO**: One-time configuration applies to ALL computers
3. **Client Registration**: Automatic via domain membership

### What Didn't Work ❌

1. ❌ Local registry edits on domain-joined clients (GPO overrides them)
2. ❌ PowerShell-only WSUS configuration (GUI wizard required)
3. ❌ Removing clients from domain (not scalable)

### Critical Settings

**WSUS Server**:
- URL: `http://10.50.6.69:8530`
- Port: 8530 (HTTP)
- Database: Windows Internal Database (WID)

**Domain GPO**:
- Policy: "Specify intranet Microsoft update service location"
- Both URLs: `http://10.50.6.69:8530`
- Alternate: BLANK (important!)

**Client Verification**:
```powershell
# Check GPO applied
gpresult /r | Select-String "WSUS"

# Check registry (should be set by GPO)
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# Check ServerSelection (should be 1)
(New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().ServerSelection
```

---

## 📁 FILES YOU NEED

### Production Scripts

| File | Use |
|------|-----|
| `wsus-server-initial-install.ps1` | WSUS server: Initial install |
| `wsus-post-reboot-setup.ps1` | WSUS server: Post-reboot config |
| `wsus-client-domain-joined.ps1` | Client: Force immediate registration (optional) |

### Documentation

| File | Use |
|------|-----|
| `WSUS-COMPLETE-PRODUCTION-GUIDE.md` | Complete deployment guide |
| `QUICK-START-SUMMARY.md` | This file - minimal steps |

### Troubleshooting

| File | Use |
|------|-----|
| `wsus-client-troubleshooting.ps1` | Client diagnostics |
| `wsus-server-fix-iis.ps1` | Server diagnostics |

---

## 🚀 DEPLOYMENT FOR 30-40 SERVERS

### New Servers (Best Practice)

**When launching new EC2 instances**:
1. Join to domain: ad.rldatix.cloud
2. Place in Computers OU (where GPO is linked)
3. Wait 90 minutes OR run `gpupdate /force`
4. Client automatically registers with WSUS
5. Done!

**No per-server configuration needed!**

### Existing Servers

**Option A: Wait** (no work)
- Servers automatically get GPO within 90 minutes

**Option B: Force** (faster)
```powershell
# Run on each server OR remotely via Invoke-Command
gpupdate /force
Restart-Service wuauserv -Force
wuauclt /detectnow /reportnow

# If needed, reboot server
```

---

## ✅ SUCCESS CHECKLIST

### WSUS Server
- [ ] Port 8530 listening
- [ ] Services running: WsusService, WID, W3SVC
- [ ] WSUS Console shows updates
- [ ] Synchronization status: Succeeded

### Domain GPO
- [ ] GPO "WSUS update" configured
- [ ] URL set to: http://10.50.6.69:8530
- [ ] GPO linked and enabled
- [ ] Applies to: Computers OU or domain root

### Clients
- [ ] Registry: WUServer = http://10.50.6.69:8530 (set by GPO)
- [ ] ServerSelection = 1
- [ ] Clients appear in WSUS Console → Computers
- [ ] Last Contact: Recent timestamp

---

## 🔧 TROUBLESHOOTING

### Client Not Appearing?

**Quick Fix**:
```powershell
# 1. Force GPO
gpupdate /force

# 2. Check ServerSelection
$s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().ServerSelection
Write-Host "ServerSelection: $s"

# 3. If 0, reboot required
if ($s -eq 0) { Restart-Computer -Force }

# 4. After reboot or if 1, force detection
wuauclt /detectnow /reportnow
```

### WSUS Server Issue?

**Quick Fix**:
```powershell
# Restart services
Restart-Service WsusService -Force
iisreset /restart

# Check port
Get-NetTCPConnection -LocalPort 8530

# Check IIS app pool
& "$env:SystemRoot\System32\inetsrv\appcmd.exe" list apppool "WsusPool"
```

---

## 🎯 AUTOMATION SUMMARY

### Fully Automated (100%)
- ✅ Client registration (via domain GPO)
- ✅ New servers joining domain
- ✅ GPO distribution to all computers

### Semi-Automated (90%)
- ⚠️ WSUS server setup (scripts + 5 min GUI)
- ⚠️ Domain GPO initial setup (one-time GUI)

### Manual Only
- ❌ WSUS Configuration Wizard (5 min, one-time)
- ❌ Update approval (by design)

---

## 💡 LESSONS LEARNED

### What We Discovered

1. **Domain GPO is mandatory** for domain-joined clients
   - Local registry changes don't work
   - ServerSelection stays at 0 without GPO

2. **WSUS GUI wizard cannot be skipped**
   - Microsoft requires it to initialize database
   - 5 minutes of manual work

3. **Some clients need reboot** after GPO
   - ServerSelection doesn't change until reboot
   - Especially if Windows Update was previously active

4. **Security groups matter**
   - Must allow TCP 8530 from client subnets to WSUS
   - Often overlooked, causes "client can't connect" issues

5. **Alternate download server must be blank**
   - Setting it to WSUS URL causes issues
   - Leave it empty!

---

## 📊 TIMELINE

### Initial Setup (One-Time)
- WSUS Server: 30 minutes
- Domain GPO: 5 minutes
- **Total**: 35 minutes

### Per-Client (If Forcing)
- Automatic: 0 minutes (wait 90 min)
- Forced: 2 minutes per client
- **For 30 clients**: 1 hour if forcing all

### Maintenance (Ongoing)
- Update approval: 10 min/week
- Monitoring: 5 min/day

---

## 🎉 FINAL RESULT

After following these steps:

✅ **WSUS Server**: Fully operational at 10.50.6.69:8530
✅ **Domain GPO**: Configured and linked to all computers
✅ **All Clients**: Automatically receive updates from WSUS
✅ **New Servers**: Auto-configure when joining domain
✅ **Management**: Centralized via WSUS Console

**No per-server configuration needed!**
**No scripts to run on 30-40 servers!**
**Everything managed via Domain Group Policy!**

---

**For complete details, see**: `WSUS-COMPLETE-PRODUCTION-GUIDE.md`

**Created**: February 6, 2026
**Status**: ✅ Tested and Working in Production
