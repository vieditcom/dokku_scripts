# Dokku Deployment Scripts

A collection of bash scripts to automate Dokku server setup and Rails application deployment on Ubuntu servers.

## Scripts Overview

### 1. `setup-dokku-server.sh`
**Purpose**: Prepares a fresh Ubuntu server for Dokku deployment with all necessary plugins and configurations.

**Features**:
- Installs latest Dokku version
- **Security hardened SSH configuration** (key-only auth, strong ciphers, rate limiting)
- **fail2ban intrusion prevention** (auto-bans after failed login attempts)
- **Automatic security updates** (unattended-upgrades for system patches)
- Configures Docker DNS for reliable container connectivity
- **Hardened firewall** (UFW) with Docker container outbound filtering
- Rate-limited SSH access (6 connections per 30 seconds per IP)
- Installs essential plugins (PostgreSQL, Redis, Let's Encrypt)
- Configures global Let's Encrypt email for SSL certificates
- Sets up SSL certificate auto-renewal
- Configures global file upload limits
- Automatically detects and configures IPv4 domain with sslip.io (falls back to IPv6 if needed)
- Includes fixes for Docker DNS issues (prevents Hetzner VPS connectivity problems)

### 2. `setup-dokku-app.sh`
**Purpose**: Creates and configures a new Rails application with database, cache, and AWS backup integration.

**Features**:
- Creates Dokku application
- Configures app-specific subdomain (e.g., `appname.ipv4.sslip.io`)
- Sets up PostgreSQL database with automated S3 backups
- Configures Redis cache
- Sets Rails production environment variables
- Scales application processes
- Attempts to enable Let's Encrypt SSL automatically (or provides instructions)

### 3. `dokku-configure-upload-limits.sh`
**Purpose**: Configures nginx upload limits for Dokku applications (global or per-app).

**Features**:
- Global upload limit configuration
- Per-application upload limit configuration
- Interactive configuration mode
- Modern Dokku command support with fallback

## Prerequisites

- Fresh Ubuntu 20.04+ server
- Root access or sudo privileges
- Domain name (optional, scripts use sslip.io for automatic domains)
- AWS account for database backups (for app setup)
- SSH access to the server

## Getting Started

### Step 0: Copy Scripts to Server

First, copy the scripts to your new server. Choose one of these methods:

#### SCP Copy
```bash
# From your local machine, copy scripts to server
scp setup-dokku-server.sh root@your-server-ip:/tmp/
scp setup-dokku-app.sh root@your-server-ip:/tmp/
scp dokku-configure-upload-limits.sh root@your-server-ip:/tmp/

# SSH into server and make executable
ssh root@your-server-ip
cd /tmp
chmod +x *.sh
```

## Usage

### Step 1: Server Setup

```bash
# Run as root or with sudo
sudo ./setup-dokku-server.sh <letsencrypt-email>
```

**Parameters**:
- `letsencrypt-email`: Email address for SSL certificate registration (required)

**Example**:
```bash
sudo ./setup-dokku-server.sh admin@yourdomain.com
```

**What it does**:
1. Configures system locales
2. **Hardens SSH configuration** (disables password auth, enables key-only, strong crypto)
3. Updates system packages
4. Configures Docker DNS with reliable external DNS servers (8.8.8.8, 1.1.1.1)
5. Configures **security-hardened firewall** with:
   - Rate-limited SSH (6 conn/30s per IP)
   - Docker container outbound filtering (whitelist-based)
   - Logging of blocked container traffic
6. **Installs fail2ban** (3 failed SSH attempts = 1 hour ban)
7. **Enables automatic security updates** (unattended-upgrades)
8. Installs Dokku and essential plugins
9. Restarts Docker and verifies DNS connectivity
10. Configures global Let's Encrypt email for SSL certificates
11. Sets up SSL certificate auto-renewal
12. Configures global upload limits (20MB default)
13. Detects server IP and sets global domain (prioritizes IPv4, falls back to IPv6)
14. Reboots the server

### Step 2: Application Setup

```bash
# Run after server reboot and Dokku web setup
./setup-dokku-app.sh <app-name> <aws-access-key-id> <aws-secret-access-key> <s3-backup-bucket>
```

**Parameters**:
- `app-name`: Name of your application (alphanumeric and hyphens only)
- `aws-access-key-id`: AWS access key for S3 backups
- `aws-secret-access-key`: AWS secret key for S3 backups
- `s3-backup-bucket`: S3 bucket name for backups

**Example**:
```bash
./setup-dokku-app.sh myapp AKIAIOSFODNN7EXAMPLE wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY my-company-backups
```

**What it does**:
1. Creates the Dokku application
2. Configures app domain as `<app-name>.<global-domain>` (e.g., `myapp.1.2.3.4.sslip.io`)
3. Sets up PostgreSQL database (`<app-name>db`)
4. Configures automated S3 backups (Sunday & Thursday at midnight)
5. Sets up Redis cache (`<app-name>red`)
6. Configures Rails production environment
7. Scales to 1 web worker and 1 background worker
8. Attempts to enable Let's Encrypt SSL (provides instructions if app not yet deployed)

### Step 3: Configure Upload Limits (Optional)

```bash
# Interactive mode
sudo ./dokku-configure-upload-limits.sh

# Set global limit
sudo ./dokku-configure-upload-limits.sh --global 50m

# Set per-app limit
sudo ./dokku-configure-upload-limits.sh --app myapp 100m

# Shorthand per-app
sudo ./dokku-configure-upload-limits.sh myapp 100m
```

## AWS Setup for Backups

1. Create an IAM user with S3 access
2. Create an S3 bucket for backups
3. Ensure the IAM user has permissions for the backup bucket

**Required IAM permissions**:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::your-backup-bucket",
                "arn:aws:s3:::your-backup-bucket/*"
            ]
        }
    ]
}
```

## Post-Setup Steps

### 1. Deploy Your Application
```bash
# Add Dokku remote to your Rails app
git remote add dokku dokku@your-server-ip:myapp

# Deploy
git push dokku main
```

### 2. Enable SSL (If Not Automatically Enabled)
If the app wasn't deployed when you ran `setup-dokku-app.sh`, enable SSL after deployment:
```bash
# SSH into your server
dokku letsencrypt:enable myapp
```

Your app will now be accessible at `https://myapp.YOUR_IP.sslip.io`

### 3. Set Custom Domain (Optional)
```bash
# SSH into your server
dokku domains:add myapp yourdomain.com

# Enable SSL for custom domain
dokku letsencrypt:enable myapp
```

### 4. Configure Environment Variables
```bash
# Set additional environment variables as needed
dokku config:set myapp SECRET_KEY_BASE=$(rails secret)
dokku config:set myapp RAILS_MASTER_KEY=your_master_key
```

## Application URLs

After deployment, your applications will be accessible at:
- **With sslip.io** (automatic): `https://myapp.YOUR_SERVER_IP.sslip.io`
- **With custom domain** (optional): `https://yourdomain.com`

The scripts automatically configure:
- IPv4 servers: `myapp.1.2.3.4.sslip.io`
- IPv6 servers: `myapp.2a01-4f8-c013-498b--1.sslip.io` (colons replaced with dashes)

## File Upload Limits

- **Default global limit**: 20MB
- **Per-app configuration**: Use `dokku-configure-upload-limits.sh`
- **Modern Dokku method**: `dokku nginx:set myapp client-max-body-size 50m`

## Database Backups

- **Schedule**: Every Sunday and Thursday at midnight
- **Location**: AWS S3 bucket (configurable, default: "my-app-backups")
- **Retention**: Configured by Dokku postgres plugin settings

## Troubleshooting

### Docker Container DNS Issues

If deployments fail with DNS resolution errors (e.g., "cannot resolve github.com"), this indicates Docker containers cannot access external DNS. This issue has been observed on **Hetzner VPS** but not on **Vultr**, suggesting provider-specific firewall configurations.

**Symptoms**:
- Host can resolve DNS (`ping github.com` works)
- Docker containers fail DNS lookups (`docker run --rm alpine nslookup github.com` fails)
- Dokku buildpacks fail to download dependencies

**Root Causes**:
1. Docker DNS misconfiguration
2. Firewall blocking forwarded traffic from containers
3. Strict iptables rules preventing DNS queries

**Prevention** (Already Applied in Scripts):
The `setup-dokku-server.sh` script now includes these fixes:

1. **Docker DNS Configuration** (`/etc/docker/daemon.json`):
   ```json
   {
       "dns": ["8.8.8.8", "1.1.1.1"]
   }
   ```

2. **UFW Forwarding Policy** (`/etc/default/ufw`):
   ```
   DEFAULT_FORWARD_POLICY="ACCEPT"
   ```

3. **DNS Traffic Rules** (in `/etc/ufw/after.rules`):
   - Allows UDP/TCP port 53 for DNS
   - Permits all outbound traffic from containers
   - Uses RETURN instead of DROP for better compatibility

**Manual Verification**:
```bash
# Test DNS from within a container
docker run --rm alpine nslookup github.com

# Check Docker DNS config
cat /etc/docker/daemon.json

# Verify UFW forwarding policy
grep DEFAULT_FORWARD_POLICY /etc/default/ufw

# Check iptables rules
iptables -L DOCKER-USER -n -v
```

**Manual Fix** (if needed on existing servers):
```bash
# 1. Configure Docker DNS
cat > /etc/docker/daemon.json << 'EOF'
{
    "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF
systemctl restart docker

# 2. Enable UFW forwarding
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
ufw reload

# 3. Add explicit DNS rules (if still needed)
iptables -I DOCKER-USER -p udp --dport 53 -j ACCEPT
iptables -I DOCKER-USER -p tcp --dport 53 -j ACCEPT
```

### Automatic Domain Configuration
The scripts prioritize IPv4 for better compatibility:
- **IPv4 preferred**: Scripts try IPv4 first with `curl -4`
- **IPv6 fallback**: If IPv4 unavailable, automatically uses IPv6
- **IPv6 formatting**: Colons replaced with dashes for sslip.io compatibility
  - Example: `2a01:4f8:c013:ae::1` → `2a01-4f8-c013-ae--1.sslip.io`
- No manual configuration needed

### SSL Certificate Issues
If Let's Encrypt fails:
```bash
# Check if app is deployed
dokku ps:report myapp

# Enable SSL manually after deployment
dokku letsencrypt:enable myapp

# Check SSL status
dokku letsencrypt:list
```

### Common Setup Issues

#### AUFS Module Warning
```
modprobe: FATAL: Module aufs not found
```
**Solution**: This is harmless. Modern Docker uses `overlay2` storage driver instead.

#### Kernel Version Notice
```
Running kernel version is not the expected kernel version
```
**Solution**: This is normal after system updates. The server reboot at the end of setup will load the new kernel.

### Check Application Status
```bash
dokku ps:report myapp
```

### View Application Logs
```bash
dokku logs myapp --tail
```

### Check Database Connection
```bash
dokku postgres:info myappdb
```

### Verify SSL Certificate
```bash
dokku letsencrypt:list
```

### Test Upload Limits
```bash
dokku nginx:show-config myapp | grep client_max_body_size
```

## Security Features

### Production-Grade Security Hardening

The `setup-dokku-server.sh` script implements comprehensive security hardening based on industry best practices:

#### 1. SSH Hardening
- **Key-only authentication**: Password authentication disabled
- **Strong cryptography**: Modern ciphers and key exchange algorithms only
  - Ciphers: ChaCha20-Poly1305, AES-256-GCM, AES-128-GCM
  - Key Exchange: Curve25519, DH-Group16/18-SHA512
  - MACs: HMAC-SHA2-512/256 with ETM
- **Connection limits**: Max 3 authentication attempts, 30-second grace period
- **Idle session timeout**: 5 minutes of inactivity
- **Disabled unnecessary features**: X11 forwarding, TCP forwarding, agent forwarding
- **Root login**: Only via SSH keys (no password)

#### 2. Firewall Protection (UFW)
- **Default deny**: All incoming traffic blocked by default
- **Rate limiting**: SSH limited to 6 connections per 30 seconds per IP
- **Minimal ports**: Only 22 (SSH), 80 (HTTP), 443 (HTTPS) open
- **IPv6 enabled**: Full IPv4 and IPv6 support

#### 3. Docker Container Security
- **Outbound filtering**: Whitelist-based approach (prevents data exfiltration)
- **Allowed protocols**: DNS (53), HTTP (80), HTTPS (443), Git (9418), NTP (123)
- **Blocked by default**: All other outbound connections from containers
- **Logging**: Blocked container traffic logged with `[UFW DOCKER BLOCK]` prefix
- **Protection against**: Command & control, data exfiltration, lateral movement

#### 4. Intrusion Prevention (fail2ban)
- **Auto-banning**: 3 failed SSH attempts = 1 hour ban
- **Detection window**: 10 minutes
- **Protection against**: Brute force attacks, credential stuffing
- **Monitoring**: `/var/log/auth.log` for SSH attacks

#### 5. Automatic Security Updates
- **unattended-upgrades**: Security patches applied automatically
- **Update sources**:
  - Ubuntu security updates
  - ESM (Extended Security Maintenance) for apps and infrastructure
- **Maintenance**: Automatic removal of unused kernels and dependencies
- **No auto-reboot**: Updates applied without automatic reboots (manual control)

#### 6. SSL/TLS
- **Let's Encrypt**: Free, automatic SSL certificates
- **Auto-renewal**: Certificates renewed automatically via cron
- **HTTPS enforcement**: HTTP → HTTPS redirects via Dokku

### Security Monitoring

**Check fail2ban status**:
```bash
sudo fail2ban-client status sshd
```

**View banned IPs**:
```bash
sudo fail2ban-client get sshd banned
```

**Check UFW firewall logs** (blocked Docker traffic):
```bash
grep "UFW DOCKER BLOCK" /var/log/syslog
```

**View automatic update logs**:
```bash
cat /var/log/unattended-upgrades/unattended-upgrades.log
```

**Check SSH configuration**:
```bash
sshd -T | grep -E "(passwordauthentication|permitrootlogin|maxauthtries)"
```

### Security Best Practices

1. **SSH Key Management**:
   - Use strong SSH keys (ED25519 or RSA 4096-bit)
   - Keep private keys secure (never share)
   - Use different keys for different servers

2. **Regular Monitoring**:
   - Check fail2ban logs weekly: `sudo fail2ban-client status`
   - Review UFW logs for unusual traffic patterns
   - Monitor system updates: `cat /var/log/apt/history.log`

3. **Dokku Application Security**:
   - Use environment variables for secrets (never commit to git)
   - Enable SSL for all applications: `dokku letsencrypt:enable <app>`
   - Keep Dokku plugins updated: `dokku plugin:update <plugin>`

4. **Database Security**:
   - PostgreSQL accessible only from localhost by default
   - Regular backups to S3 (encrypted in transit)
   - Use strong database passwords

5. **Additional Hardening** (Optional):
   - Consider using a non-standard SSH port
   - Restrict SSH to specific IPs if you have static IPs
   - Set up 2FA for critical accounts
   - Enable email notifications for fail2ban

### Security Notes

- Scripts configure UFW firewall with minimal required ports
- SSL certificates are automatically managed with Let's Encrypt
- Database backups are encrypted in transit to S3
- AWS credentials are passed as parameters (not hardcoded)
- Docker containers run with security constraints (limited outbound access)
- All security configurations are idempotent and can be re-run safely

## File Structure

```
dokku/
├── README.md                           # This file
├── setup-dokku-server.sh              # Server setup script
├── setup-dokku-app.sh                 # Application setup script
└── dokku-configure-upload-limits.sh   # Upload limits configuration
```

## Contributing

1. Test scripts on a fresh Ubuntu server
2. Ensure no secrets are hardcoded
3. Update this README for any new features
4. Follow existing script patterns and error handling

## License

These scripts are provided as-is for educational and deployment purposes. Use at your own risk and always test on development servers first.