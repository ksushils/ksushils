# WSUS Server and Client Setup for AWS EC2

Complete automation scripts for deploying and managing Windows Server Update Services (WSUS) in AWS EC2 environments.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Scripts Included](#scripts-included)
- [Quick Start](#quick-start)
- [Detailed Setup Instructions](#detailed-setup-instructions)
- [Terraform Integration](#terraform-integration)
- [Security Group Configuration](#security-group-configuration)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## 🎯 Overview

This solution provides fully automated scripts to:
1. **Install and configure WSUS** on a Windows Server EC2 instance
2. **Configure Windows clients** to receive updates from WSUS
3. **Create Group Policy Objects** for domain environments
4. **Troubleshoot and reset** client connections

All scripts are designed for EC2 user data, enabling complete automation through Terraform or CloudFormation.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    AWS VPC (10.50.0.0/16)               │
│                                                          │
│  ┌──────────────────┐          ┌────────────────────┐  │
│  │  WSUS Server     │          │  Domain Controller │  │
│  │  10.50.5.96      │◄────────►│  (Optional)        │  │
│  │  Port 8530       │          │  GPO Management    │  │
│  └──────────────────┘          └────────────────────┘  │
│          ▲                                              │
│          │ WSUS Updates                                 │
│          │ (HTTP 8530)                                  │
│          │                                              │
│  ┌───────┴──────────────────────────────────────┐      │
│  │                                               │      │
│  │  Client EC2 Instances (15 servers)           │      │
│  │  - Production Servers                        │      │
│  │  - Development Servers                       │      │
│  │  - Test Servers                              │      │
│  │                                               │      │
│  └───────────────────────────────────────────────┘      │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## ✅ Prerequisites

### For WSUS Server:
- **OS**: Windows Server 2016, 2019, or 2022
- **Instance Type**: Minimum t3.medium (2 vCPU, 4GB RAM)
- **Storage**:
  - Root volume: 50GB minimum
  - Additional volume for WSUS content: 100GB+ recommended
- **Network**: Static private IP recommended
- **IAM Role**: Basic EC2 permissions

### For Client Servers:
- **OS**: Windows Server 2016+ or Windows 10/11
- **Network**: Must be able to reach WSUS server on port 8530
- **Domain**: Optional (can use registry-based configuration)

### General Requirements:
- PowerShell 5.1 or later
- Administrator privileges
- Internet access for WSUS server (to download updates from Microsoft)

---

## 📦 Scripts Included

### 1. `wsus-server-userdata.ps1`
**Purpose**: Complete WSUS server installation and configuration

**Features**:
- Installs WSUS role and features
- Configures synchronization with Microsoft Update
- Creates computer groups (Production, Development, Test)
- Sets up automatic approval rules
- Configures IIS for WSUS
- Creates scheduled cleanup tasks
- Opens firewall ports

**Usage**: EC2 User Data for WSUS server

### 2. `wsus-client-userdata.ps1`
**Purpose**: Configure Windows clients to use WSUS

**Features**:
- Sets registry keys for WSUS server location
- Configures automatic update settings
- Forces initial WSUS detection and registration
- Creates scheduled task for periodic reporting
- Tests connectivity to WSUS server

**Usage**: EC2 User Data for client servers

**Configuration**: Edit the `$WSUSServer` variable at the top of the script

### 3. `wsus-gpo-configuration.ps1`
**Purpose**: Create and configure Group Policy for WSUS (Domain Controller)

**Features**:
- Creates GPO with WSUS settings
- Links GPO to specified OU
- Configures all necessary Windows Update policies
- Generates GPO report

**Usage**: Run manually on Domain Controller after WSUS setup

**Configuration**: Edit `$WSUSServer`, `$GPOName`, and `$TargetOU` variables

### 4. `wsus-client-reset.ps1`
**Purpose**: Troubleshooting tool to force WSUS re-registration

**Features**:
- Stops Windows Update services
- Clears WSUS client ID
- Clears update cache
- Forces new registration with WSUS
- Generates diagnostic report

**Usage**: Run manually on clients that don't appear in WSUS console

---

## 🚀 Quick Start

### Option A: Using GPO (Domain Environment)

#### Step 1: Deploy WSUS Server
```hcl
# Terraform example
resource "aws_instance" "wsus_server" {
  ami           = "ami-xxxxx"  # Windows Server 2022
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.private.id

  user_data = file("wsus-server-userdata.ps1")

  tags = {
    Name = "WSUS-Server"
  }
}
```

#### Step 2: Configure GPO on Domain Controller
1. RDP to Domain Controller
2. Copy `wsus-gpo-configuration.ps1` to the server
3. Edit the script to set your WSUS server IP and target OU:
   ```powershell
   $WSUSServer = "10.50.5.96"
   $TargetOU = "OU=Servers,DC=yourdomain,DC=com"
   ```
4. Run the script:
   ```powershell
   .\wsus-gpo-configuration.ps1
   ```

#### Step 3: Deploy Client Servers
```hcl
# Terraform will automatically apply GPO to domain-joined instances
resource "aws_instance" "client_servers" {
  count         = 15
  ami           = "ami-xxxxx"  # Windows Server 2022
  instance_type = "t3.small"
  subnet_id     = aws_subnet.private.id

  # Domain join script in user data
  user_data = <<-EOF
    <powershell>
    # Domain join commands
    Add-Computer -DomainName "yourdomain.com" -Credential (Get-Credential)

    # Force GPO update
    gpupdate /force
    </powershell>
  EOF

  tags = {
    Name = "Client-Server-${count.index + 1}"
  }
}
```

### Option B: Using Registry (Non-Domain Environment)

#### Step 1: Deploy WSUS Server
```hcl
# Same as Option A
```

#### Step 2: Deploy Client Servers with User Data
```hcl
resource "aws_instance" "client_servers" {
  count         = 15
  ami           = "ami-xxxxx"
  instance_type = "t3.small"
  subnet_id     = aws_subnet.private.id

  user_data = file("wsus-client-userdata.ps1")

  tags = {
    Name = "Client-Server-${count.index + 1}"
  }
}
```

**Important**: Edit `wsus-client-userdata.ps1` before deployment:
```powershell
$WSUSServer = "10.50.5.96"  # Your WSUS server IP
```

---

## 📖 Detailed Setup Instructions

### Phase 1: WSUS Server Setup

1. **Launch EC2 Instance**
   - AMI: Windows Server 2022
   - Instance Type: t3.medium or larger
   - Network: Private subnet with NAT gateway for internet access
   - Storage: 50GB root + 100GB additional for WSUS content

2. **Apply User Data**
   - Copy contents of `wsus-server-userdata.ps1`
   - Paste in EC2 user data field during launch
   - Or use Terraform `user_data` parameter

3. **Wait for Installation** (20-30 minutes)
   - Initial setup: 10-15 minutes
   - First synchronization: 10-15 minutes
   - Check logs: `C:\wsus-setup.log`

4. **Verify Installation**
   - RDP to WSUS server
   - Open: Server Manager > Tools > Windows Server Update Services
   - Check: Options > Synchronization Schedule
   - Verify: Updates are downloading

### Phase 2: Client Configuration

#### Method 1: Using GPO (Recommended for Domain)

1. **Run GPO Configuration Script**
   ```powershell
   # On Domain Controller
   .\wsus-gpo-configuration.ps1
   ```

2. **Verify GPO Creation**
   ```powershell
   # Check GPO exists
   Get-GPO -Name "WSUS Client Configuration"

   # View GPO settings
   Get-GPOReport -Name "WSUS Client Configuration" -ReportType Html -Path "C:\gpo-report.html"
   ```

3. **Force GPO Update on Clients**
   ```powershell
   # On each client
   gpupdate /force

   # Verify GPO applied
   gpresult /r
   ```

#### Method 2: Using User Data (Workgroup or Automation)

1. **Edit Client Script**
   - Open `wsus-client-userdata.ps1`
   - Set `$WSUSServer = "10.50.5.96"` (your WSUS IP)

2. **Apply to EC2 Instances**
   - Use as user data during launch
   - Or run manually via RDP

3. **Verify Configuration**
   ```powershell
   # Check registry
   reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate

   # Should show:
   # WUServer: http://10.50.5.96:8530
   # WUStatusServer: http://10.50.5.96:8530
   ```

### Phase 3: Verification

1. **On Client Servers**
   ```powershell
   # Test connectivity
   Test-NetConnection 10.50.5.96 -Port 8530

   # Force detection
   wuauclt /detectnow /reportnow

   # Or for Windows Server 2016+
   UsoClient StartScan
   ```

2. **On WSUS Server**
   - Open WSUS Console
   - Navigate to: Computers > All Computers
   - Wait 10-15 minutes for clients to appear
   - Clients should show up with their computer names

3. **Check Client Status**
   - Each client should show:
     - Last Status Report time
     - Updates needed
     - Group assignment

### Phase 4: Ongoing Management

1. **Approve Updates**
   ```powershell
   # In WSUS Console
   Updates > All Updates > Filter by "Not Approved"
   # Right-click > Approve > Select computer groups
   ```

2. **Monitor Compliance**
   - Reports > Update Reports > Update Status Summary
   - Check for:
     - Clients reporting
     - Updates needed
     - Failed installations

3. **Maintenance**
   - Automated cleanup runs weekly (configured in setup)
   - Manual cleanup if needed:
   ```powershell
   Get-WsusServer | Invoke-WsusServerCleanup -CleanupObsoleteUpdates -CompressUpdates
   ```

---

## 🔧 Terraform Integration

### Complete Example

```hcl
# Variables
variable "wsus_server_ip" {
  default = "10.50.5.96"
}

variable "vpc_id" {
  description = "VPC ID"
}

variable "private_subnet_id" {
  description = "Private subnet for servers"
}

# Security Group for WSUS Server
resource "aws_security_group" "wsus_server" {
  name        = "wsus-server-sg"
  description = "Security group for WSUS server"
  vpc_id      = var.vpc_id

  # Allow HTTP from clients (8530)
  ingress {
    from_port   = 8530
    to_port     = 8530
    protocol    = "tcp"
    cidr_blocks = ["10.50.0.0/16"]  # Your VPC CIDR
    description = "WSUS HTTP"
  }

  # Allow HTTPS from clients (8531) - optional
  ingress {
    from_port   = 8531
    to_port     = 8531
    protocol    = "tcp"
    cidr_blocks = ["10.50.0.0/16"]
    description = "WSUS HTTPS"
  }

  # Allow RDP for management
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["10.50.0.0/16"]
    description = "RDP"
  }

  # Allow all outbound (for downloading updates)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WSUS Server Security Group"
  }
}

# Security Group for Client Servers
resource "aws_security_group" "wsus_clients" {
  name        = "wsus-clients-sg"
  description = "Security group for WSUS client servers"
  vpc_id      = var.vpc_id

  # Allow outbound to WSUS server
  egress {
    from_port   = 8530
    to_port     = 8530
    protocol    = "tcp"
    cidr_blocks = ["${var.wsus_server_ip}/32"]
    description = "WSUS Server"
  }

  # Allow RDP
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["10.50.0.0/16"]
    description = "RDP"
  }

  # Allow other outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WSUS Clients Security Group"
  }
}

# WSUS Server Instance
resource "aws_instance" "wsus_server" {
  ami                    = "ami-xxxxx"  # Windows Server 2022 AMI
  instance_type          = "t3.medium"
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [aws_security_group.wsus_server.id]
  private_ip             = var.wsus_server_ip

  # Root volume
  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
  }

  # Additional volume for WSUS content
  ebs_block_device {
    device_name = "/dev/xvdf"
    volume_size = 100
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = file("${path.module}/wsus-server-userdata.ps1")

  tags = {
    Name = "WSUS-Server"
    Role = "UpdateManagement"
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Client Servers
resource "aws_instance" "client_servers" {
  count                  = 15
  ami                    = "ami-xxxxx"  # Windows Server 2022 AMI
  instance_type          = "t3.small"
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [aws_security_group.wsus_clients.id]

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
  }

  # Option 1: Use client user data script
  user_data = templatefile("${path.module}/wsus-client-userdata.ps1", {
    wsus_server = var.wsus_server_ip
  })

  # Option 2: Domain join only (if using GPO)
  # user_data = file("${path.module}/domain-join-userdata.ps1")

  tags = {
    Name        = "Client-Server-${count.index + 1}"
    Environment = count.index < 5 ? "Production" : (count.index < 10 ? "Development" : "Test")
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Outputs
output "wsus_server_private_ip" {
  value = aws_instance.wsus_server.private_ip
}

output "wsus_server_url" {
  value = "http://${aws_instance.wsus_server.private_ip}:8530"
}

output "client_server_ips" {
  value = aws_instance.client_servers[*].private_ip
}
```

### Template Variables in User Data

If you want to parameterize the WSUS server IP in Terraform:

**wsus-client-userdata.ps1** (modified):
```powershell
<powershell>
# ... (beginning of script)

# WSUS Server from Terraform
$WSUSServer = "${wsus_server}"
$WSUSPort = "8530"

# ... (rest of script)
</powershell>
```

**Terraform usage**:
```hcl
user_data = templatefile("wsus-client-userdata.ps1", {
  wsus_server = aws_instance.wsus_server.private_ip
})
```

---

## 🔐 Security Group Configuration

### WSUS Server Security Group

**Inbound Rules**:
| Port  | Protocol | Source        | Purpose                    |
|-------|----------|---------------|----------------------------|
| 8530  | TCP      | 10.50.0.0/16  | WSUS HTTP (clients)        |
| 8531  | TCP      | 10.50.0.0/16  | WSUS HTTPS (optional)      |
| 3389  | TCP      | Admin CIDR    | RDP management             |

**Outbound Rules**:
| Port  | Protocol | Destination   | Purpose                    |
|-------|----------|---------------|----------------------------|
| 80    | TCP      | 0.0.0.0/0     | Download updates (HTTP)    |
| 443   | TCP      | 0.0.0.0/0     | Download updates (HTTPS)   |

### Client Servers Security Group

**Outbound Rules**:
| Port  | Protocol | Destination       | Purpose                |
|-------|----------|-------------------|------------------------|
| 8530  | TCP      | WSUS Server IP    | Connect to WSUS        |
| 443   | TCP      | 0.0.0.0/0         | Other internet access  |

---

## 🔍 Troubleshooting

### Issue: Client doesn't appear in WSUS console

**Solutions**:

1. **Run the reset script**
   ```powershell
   .\wsus-client-reset.ps1
   ```

2. **Check registry settings**
   ```powershell
   reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate

   # Should show:
   # WUServer
   # WUStatusServer
   ```

3. **Test connectivity**
   ```powershell
   Test-NetConnection 10.50.5.96 -Port 8530
   ```

4. **Check Windows Update service**
   ```powershell
   Get-Service wuauserv
   # Should be Running

   # If not, start it
   Start-Service wuauserv
   ```

5. **Force detection manually**
   ```powershell
   wuauclt /resetauthorization /detectnow /reportnow

   # For Windows Server 2016+
   UsoClient StartScan
   ```

6. **Check Event Logs**
   ```powershell
   Get-WinEvent -LogName "Microsoft-Windows-WindowsUpdateClient/Operational" -MaxEvents 50
   ```

### Issue: WSUS server not downloading updates

**Solutions**:

1. **Check synchronization status**
   - Open WSUS Console
   - Go to: Synchronizations
   - Check last sync status

2. **Force synchronization**
   ```powershell
   $wsus = Get-WsusServer
   $subscription = $wsus.GetSubscription()
   $subscription.StartSynchronization()
   ```

3. **Check internet connectivity**
   ```powershell
   Test-NetConnection update.microsoft.com -Port 443
   ```

4. **Review WSUS service**
   ```powershell
   Get-Service WsusService
   Restart-Service WsusService
   ```

### Issue: GPO not applying to clients

**Solutions**:

1. **Verify GPO link**
   ```powershell
   Get-GPInheritance -Target "OU=Servers,DC=yourdomain,DC=com"
   ```

2. **Check GPO application**
   ```powershell
   # On client
   gpresult /r

   # Should show "WSUS Client Configuration" GPO
   ```

3. **Force GPO update**
   ```powershell
   gpupdate /force
   ```

4. **Check computer location in AD**
   - Ensure computer is in correct OU
   - Verify GPO is linked to that OU

### Issue: Updates not installing

**Solutions**:

1. **Check if updates are approved**
   - WSUS Console > Updates > All Updates
   - Right-click update > Approve
   - Select appropriate computer group

2. **Force installation**
   ```powershell
   # On client
   UsoClient StartInstall
   ```

3. **Check disk space**
   ```powershell
   Get-PSDrive C
   # Ensure adequate free space (10GB+)
   ```

4. **Review Windows Update logs**
   ```powershell
   Get-WindowsUpdateLog
   # Creates WindowsUpdate.log on desktop
   ```

### Common Error Messages

#### "0x80244022" - HTTP status 503
- **Cause**: WSUS IIS application pool stopped
- **Solution**:
  ```powershell
  # On WSUS server
  Import-Module WebAdministration
  Start-WebAppPool "WsusPool"
  ```

#### "0x8024401c" - Connection timeout
- **Cause**: Cannot reach WSUS server
- **Solution**:
  - Check security groups
  - Verify WSUS server is running
  - Test network connectivity

#### "0x80244019" - Invalid certificate
- **Cause**: HTTPS certificate issues (if using port 8531)
- **Solution**: Use HTTP (port 8530) or install valid certificate

---

## 📚 Best Practices

### WSUS Server

1. **Regular Maintenance**
   - Run cleanup weekly (automated in script)
   - Monitor disk space usage
   - Review declined updates quarterly

2. **Backup Strategy**
   - Backup WSUS database regularly
   - Document server configuration
   - Test restore procedures

3. **Update Approval**
   - Create approval rules for critical/security updates
   - Test updates in Development before Production
   - Schedule maintenance windows for installations

4. **Performance Optimization**
   - Use SSD for WSUS content directory
   - Schedule sync during off-hours
   - Limit products and classifications to needed only

5. **Monitoring**
   - Set up CloudWatch alarms for:
     - CPU usage > 80%
     - Disk space < 20%
     - Service health
   - Review WSUS reports weekly

### Client Management

1. **Group Organization**
   - Separate by environment (Prod/Dev/Test)
   - Create role-based groups (Web/DB/App)
   - Use computer targeting for phased rollouts

2. **Update Schedule**
   - Stagger installation times by group
   - Schedule during maintenance windows
   - Allow adequate testing time

3. **Monitoring**
   - Track compliance rates
   - Identify non-reporting clients
   - Review failed installations

### Security

1. **Network Segmentation**
   - Keep WSUS in private subnet
   - Use security groups for access control
   - Enable VPC flow logs

2. **Access Control**
   - Limit RDP access to WSUS server
   - Use IAM roles instead of access keys
   - Enable MFA for privileged accounts

3. **Encryption**
   - Enable EBS encryption
   - Consider HTTPS (port 8531) for WSUS
   - Use VPN for management access

### Disaster Recovery

1. **Documentation**
   - Keep current network diagrams
   - Document GPO settings
   - Maintain runbooks for common tasks

2. **Backup**
   - Regular WSUS database backups
   - AMI snapshots of WSUS server
   - Export GPOs regularly

3. **Testing**
   - Test restore procedures quarterly
   - Validate automation scripts
   - Practice failover scenarios

---

## 📊 Monitoring and Reporting

### WSUS Console Reports

**Access**: WSUS Console > Reports

Useful reports:
1. **Update Status Summary** - Overall compliance
2. **Computer Status Summary** - Client health
3. **Updates with Errors** - Failed installations
4. **Computers Not Contacting Server** - Missing clients

### PowerShell Monitoring

```powershell
# Get WSUS server statistics
$wsus = Get-WsusServer
$stats = $wsus.GetStatus()

Write-Host "Total Computers: $($stats.ComputerTargetCount)"
Write-Host "Updates Needed: $($stats.UpdatesNeededByComputersCount)"
Write-Host "Total Updates: $($stats.UpdateCount)"

# Get clients not reporting
$wsus.GetComputerTargets() |
    Where-Object { $_.LastReportedStatusTime -lt (Get-Date).AddDays(-7) } |
    Select-Object FullDomainName, LastReportedStatusTime

# Get failed updates
Get-WsusUpdate -Classification All -Approval Approved -Status Failed |
    Select-Object Title, @{N='FailedCount';E={($_.GetUpdateInstallationInfoPerComputerTarget() |
        Where-Object { $_.UpdateInstallationState -eq 'Failed' }).Count}}
```

### CloudWatch Integration

```hcl
# Terraform CloudWatch alarms

resource "aws_cloudwatch_metric_alarm" "wsus_cpu" {
  alarm_name          = "wsus-server-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "WSUS server CPU usage is high"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.wsus_server.id
  }
}

resource "aws_cloudwatch_metric_alarm" "wsus_disk" {
  alarm_name          = "wsus-server-low-disk"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DiskSpaceUtilization"
  namespace           = "CWAgent"
  period              = "300"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "WSUS server disk space is low"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.wsus_server.id
    path       = "C:"
  }
}
```

---

## 🎓 Additional Resources

### Microsoft Documentation
- [WSUS Overview](https://docs.microsoft.com/en-us/windows-server/administration/windows-server-update-services/get-started/windows-server-update-services-wsus)
- [Deploy WSUS](https://docs.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/deploy-windows-server-update-services)
- [Group Policy Settings](https://docs.microsoft.com/en-us/windows/deployment/update/waas-wu-settings)

### AWS Resources
- [AWS Windows Guide](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/)
- [EC2 User Data](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2-windows-user-data.html)
- [VPC Security Groups](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)

### PowerShell Commands Reference

```powershell
# WSUS Server Commands
Get-WsusServer                          # Get WSUS server object
Get-WsusUpdate                          # Get updates
Approve-WsusUpdate                      # Approve updates
Invoke-WsusServerCleanup                # Run cleanup
Get-WsusComputerTarget                  # Get client computers

# Client Commands
wuauclt /detectnow                      # Detect updates
wuauclt /reportnow                      # Report to WSUS
UsoClient StartScan                     # Windows 10/Server 2016+
Get-WindowsUpdateLog                    # Generate log file

# GPO Commands
Get-GPO -All                            # List all GPOs
Get-GPOReport -Name "GPO Name"          # Get GPO report
New-GPLink -Name "GPO" -Target "OU"     # Link GPO to OU
gpupdate /force                         # Force GPO update (client)
gpresult /r                             # Show applied GPOs (client)

# Registry Queries
reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate
```

---

## 📝 Change Log

### Version 1.0 (2024-02)
- Initial release
- WSUS server installation script
- Client configuration script
- GPO management script
- Reset/troubleshooting script
- Complete Terraform integration
- Comprehensive documentation

---

## 🤝 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review log files:
   - Server: `C:\wsus-setup.log`
   - Client: `C:\wsus-client-setup.log`
   - Reset: `C:\wsus-client-reset.log`
3. Check Windows Event Viewer
4. Review WSUS console reports

---

## ⚖️ License

These scripts are provided as-is for use in AWS environments. Test thoroughly before production deployment.

---

## ✅ Checklist for Deployment

- [ ] WSUS server instance launched with user data
- [ ] Security groups configured (ports 8530, 3389)
- [ ] WSUS server has internet access (NAT gateway)
- [ ] Static IP assigned to WSUS server
- [ ] GPO created and linked (if using domain)
- [ ] Client instances configured with user data or GPO
- [ ] Clients can reach WSUS server (test connectivity)
- [ ] Clients appear in WSUS console (wait 15 minutes)
- [ ] Updates approved in WSUS console
- [ ] Test update installation on one client
- [ ] CloudWatch alarms configured
- [ ] Backup strategy in place
- [ ] Documentation updated with your specific configuration

---

**Last Updated**: 2024-02-05
**Version**: 1.0
