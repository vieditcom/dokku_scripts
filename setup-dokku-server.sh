#!/bin/bash

# Dokku Server Setup Script for Ubuntu
# This script prepares a fresh Ubuntu server for Dokku deployment
# Usage: ./setup-dokku-server.sh <letsencrypt-email>

set -e  # Exit on any error
set +x  # Disable command echoing when script is pasted

# Get Let's Encrypt email from command line argument
LETSENCRYPT_EMAIL="${1:-admin@example.com}"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Dokku server setup...${NC}"
echo -e "${BLUE}Using Let's Encrypt email: $LETSENCRYPT_EMAIL${NC}"

# Validate email format
if [[ ! "$LETSENCRYPT_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo -e "${RED}Error: Invalid email format provided${NC}"
    echo -e "${YELLOW}Usage: $0 <letsencrypt-email>${NC}"
    echo -e "${YELLOW}Example: $0 admin@yourdomain.com${NC}"
    exit 1
fi

# Fix locale issues
echo -e "${BLUE}Configuring locale settings...${NC}"
export DEBIAN_FRONTEND=noninteractive

# Generate and configure locales
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Set locale environment variables for current session
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export LANGUAGE=en_US:en

echo -e "${GREEN}Locale configuration completed!${NC}"

# Harden SSH configuration
echo -e "${PURPLE}Hardening SSH configuration for security...${NC}"

# IMPORTANT: Verify SSH keys exist before hardening
if [ ! -f ~/.ssh/authorized_keys ] || [ ! -s ~/.ssh/authorized_keys ]; then
    echo -e "${RED}ERROR: No SSH keys found in ~/.ssh/authorized_keys${NC}"
    echo -e "${RED}SSH hardening SKIPPED to prevent lockout${NC}"
    echo -e "${YELLOW}Please add SSH keys manually, then run SSH hardening separately${NC}"
    echo -e "${YELLOW}Command: cat your-public-key.pub >> ~/.ssh/authorized_keys${NC}"
    SSH_HARDENING_SKIPPED=true
else
    echo -e "${GREEN}SSH keys found in ~/.ssh/authorized_keys - proceeding with hardening${NC}"
    SSH_HARDENING_SKIPPED=false
fi

if [ "$SSH_HARDENING_SKIPPED" = false ]; then
    # Backup original SSH config
    if [ ! -f /etc/ssh/sshd_config.backup ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
        echo -e "${BLUE}Backed up original SSH config${NC}"
    fi

    # Apply SSH hardening settings
    cat > /etc/ssh/sshd_config.d/99-hardening.conf << 'EOF'
# SSH Hardening Configuration

# Disable password authentication (key-only auth)
PasswordAuthentication no
ChallengeResponseAuthentication no

# Disable root login via SSH (use sudo instead)
PermitRootLogin prohibit-password

# Disable empty passwords
PermitEmptyPasswords no

# Use only strong key exchange algorithms
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256

# Use only strong ciphers
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr

# Use only strong MAC algorithms
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# Disable X11 forwarding
X11Forwarding no

# Limit authentication attempts
MaxAuthTries 3

# Set login grace time (30 seconds)
LoginGraceTime 30

# Set client alive interval (5 minutes) to disconnect idle sessions
ClientAliveInterval 300
ClientAliveCountMax 2

# Disable TCP forwarding unless needed
AllowTcpForwarding no

# Disable agent forwarding
AllowAgentForwarding no
EOF

    echo -e "${GREEN}SSH hardening configuration applied${NC}"
    echo -e "${CYAN}Password authentication disabled - key-based auth only${NC}"
    echo -e "${CYAN}Root login via password disabled${NC}"

    # Test SSH config and restart if valid
    if sshd -t 2>/dev/null; then
        # Detect the correct SSH service name (Ubuntu typically uses ssh.service)
        if systemctl list-unit-files --type=service | grep -q '^ssh.service'; then
            SSH_SERVICE_NAME="ssh"
        elif systemctl list-unit-files --type=service | grep -q '^sshd.service'; then
            SSH_SERVICE_NAME="sshd"
        else
            SSH_SERVICE_NAME=""
        fi

        if [ -n "$SSH_SERVICE_NAME" ]; then
            systemctl restart "$SSH_SERVICE_NAME"
            echo -e "${GREEN}SSH service restarted with hardened configuration${NC}"
        else
            echo -e "${YELLOW}Warning: Could not determine SSH service name (ssh/sshd); please restart SSH manually${NC}"
        fi

        # Display warning to keep current session open
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}⚠️  IMPORTANT: DO NOT CLOSE THIS SSH SESSION YET! ⚠️${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}SSH hardening has been applied. Test your connection first:${NC}"
        echo -e "${CYAN}1. Open a NEW terminal window${NC}"
        echo -e "${CYAN}2. Try to SSH: ssh root@your-server-ip${NC}"
        echo -e "${CYAN}3. If it works, you're safe to close this session${NC}"
        echo -e "${CYAN}4. If it fails, use this session to revert:${NC}"
        echo -e "${CYAN}   sudo rm /etc/ssh/sshd_config.d/99-hardening.conf${NC}"
        if [ -n "$SSH_SERVICE_NAME" ]; then
            echo -e "${CYAN}   sudo systemctl restart $SSH_SERVICE_NAME${NC}"
        else
            echo -e "${CYAN}   sudo systemctl restart ssh # or sshd${NC}"
        fi
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        # Wait for user confirmation
        echo -e "${BLUE}Press ENTER after you have verified SSH access works in a new terminal...${NC}"
        read -r
    else
        echo -e "${YELLOW}Warning: SSH config test failed, keeping old configuration${NC}"
        rm -f /etc/ssh/sshd_config.d/99-hardening.conf
    fi
else
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}SSH hardening was SKIPPED due to missing SSH keys${NC}"
    echo -e "${YELLOW}Your server is currently LESS SECURE${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi

# Update package list and upgrade system
echo -e "${BLUE}Updating package list and upgrading system...${NC}"

# Set DEBIAN_FRONTEND to noninteractive to avoid prompts
export DEBIAN_FRONTEND=noninteractive

# Configure dpkg to use old config files by default for SSH
echo 'DPkg::Options {
   "--force-confdef";
   "--force-confold";
}' > /etc/apt/apt.conf.d/50unattended-upgrades-local

# Update and upgrade without confirmation
apt update -y
apt upgrade -y

# Clean up the dpkg configuration
rm -f /etc/apt/apt.conf.d/50unattended-upgrades-local

echo -e "${GREEN}System update completed successfully!${NC}"

# Configure Docker DNS for container connectivity
echo -e "${PURPLE}Configuring Docker DNS for reliable container connectivity...${NC}"

# Create Docker daemon configuration directory if it doesn't exist
if [ ! -d /etc/docker ]; then
    mkdir -p /etc/docker
    echo -e "${BLUE}Created /etc/docker directory${NC}"
fi

# Configure Docker to use reliable external DNS servers
# This prevents DNS resolution issues in containers
cat > /etc/docker/daemon.json << 'EOF'
{
    "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF

echo -e "${GREEN}Docker DNS configuration created at /etc/docker/daemon.json${NC}"
echo -e "${CYAN}Containers will use Google DNS (8.8.8.8) and Cloudflare DNS (1.1.1.1)${NC}"

# Note: Docker will be restarted after Dokku installation to apply these settings

# Configure firewall for Dokku + Rails applications
echo -e "${PURPLE}Configuring firewall for Dokku applications...${NC}"

# Install UFW if not already installed
if ! command -v ufw &> /dev/null; then
    echo -e "${BLUE}Installing UFW (Uncomplicated Firewall)...${NC}"
    apt install -y ufw
    echo -e "${GREEN}UFW installed successfully!${NC}"
else
    echo -e "${GREEN}UFW is already installed${NC}"
fi

# Reset UFW to clean state
echo -e "${BLUE}Resetting firewall to clean state...${NC}"
ufw --force reset

# Set default policies
echo -e "${BLUE}Setting default firewall policies...${NC}"
ufw default deny incoming
ufw default allow outgoing

# Enable forwarding for Docker containers
echo -e "${BLUE}Enabling packet forwarding for Docker containers...${NC}"
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
echo -e "${GREEN}UFW forward policy set to ACCEPT${NC}"

# Allow essential services for Dokku + Rails with rate limiting
echo -e "${BLUE}Configuring firewall rules with rate limiting for Dokku applications...${NC}"

# SSH access with rate limiting (max 6 connections per 30 seconds per IP)
ufw limit 22/tcp comment 'SSH access with rate limiting'
echo -e "${CYAN}✓ SSH (port 22) - Server management (rate limited: 6 conn/30s)${NC}"

# HTTP traffic (will redirect to HTTPS via Dokku)
ufw allow 80/tcp comment 'HTTP web traffic'
echo -e "${CYAN}✓ HTTP (port 80) - Web traffic (redirects to HTTPS)${NC}"

# HTTPS traffic (secure web traffic)
ufw allow 443/tcp comment 'HTTPS web traffic'
echo -e "${CYAN}✓ HTTPS (port 443) - Secure web traffic${NC}"

# Configure UFW to work with Docker/Dokku
echo -e "${BLUE}Configuring UFW to work with Docker containers...${NC}"

# Ensure UFW handles IPv6 properly
sed -i 's/IPV6=no/IPV6=yes/' /etc/default/ufw 2>/dev/null || echo "IPV6=yes" >> /etc/default/ufw

# Configure UFW to work with Docker (Security Hardened)
cat > /etc/ufw/after.rules << 'EOF'
# Put Docker behind UFW with security controls
*filter
:DOCKER-USER - [0:0]
:ufw-user-input - [0:0]

# Allow established/related connections (replies to container requests)
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Drop invalid packets early
-A DOCKER-USER -m conntrack --ctstate INVALID -j DROP

# Allow DNS queries (UDP and TCP port 53) - Required for container connectivity
-A DOCKER-USER -p udp --dport 53 -j ACCEPT
-A DOCKER-USER -p tcp --dport 53 -j ACCEPT

# Allow HTTP/HTTPS outbound (for package downloads, git clone, etc.)
-A DOCKER-USER -p tcp --dport 80 -j ACCEPT
-A DOCKER-USER -p tcp --dport 443 -j ACCEPT

# Allow Git protocol (port 9418) - Used by some git operations
-A DOCKER-USER -p tcp --dport 9418 -j ACCEPT

# Allow NTP for time synchronization
-A DOCKER-USER -p udp --dport 123 -j ACCEPT

# Allow incoming traffic on common network interfaces (for published ports)
-A DOCKER-USER -i eth0 -j ufw-user-input
-A DOCKER-USER -i enp1s0 -j ufw-user-input
-A DOCKER-USER -i ens3 -j ufw-user-input

# Log dropped outbound connections from containers (for security monitoring)
-A DOCKER-USER -m limit --limit 3/min -j LOG --log-prefix "[UFW DOCKER BLOCK] "

# Drop all other outbound traffic from containers
-A DOCKER-USER -j DROP

COMMIT
EOF

# Enable UFW
echo -e "${BLUE}Enabling firewall...${NC}"
ufw --force enable

# Display firewall status
echo -e "${GREEN}Firewall configuration completed!${NC}"
echo -e "${BLUE}Current firewall status:${NC}"
ufw status verbose

echo -e "${GREEN}Firewall is now configured for Dokku + Rails applications${NC}"
echo -e "${CYAN}Allowed services: SSH (22), HTTP (80), HTTPS (443)${NC}"
echo -e "${CYAN}All other incoming traffic is blocked by default${NC}"

# Install and configure fail2ban for intrusion prevention
echo -e "${PURPLE}Installing fail2ban for intrusion prevention...${NC}"
apt install -y fail2ban

# Create fail2ban local configuration
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban hosts for 1 hour (3600 seconds)
bantime = 3600

# A host is banned if it has generated "maxretry" during the last "findtime"
findtime = 600

# Number of failures before a host gets banned
maxretry = 5

# Email notifications (disabled by default, configure if needed)
destemail = root@localhost
sendername = Fail2Ban
action = %(action_)s

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[dokku]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

# Restart fail2ban to apply configuration
systemctl enable fail2ban
systemctl restart fail2ban

echo -e "${GREEN}fail2ban installed and configured!${NC}"
echo -e "${CYAN}SSH bruteforce protection enabled (3 failed attempts = 1 hour ban)${NC}"

# Install unattended-upgrades for automatic security updates
echo -e "${PURPLE}Installing automatic security updates...${NC}"
apt install -y unattended-upgrades

# Configure unattended-upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF

# Enable automatic updates
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

echo -e "${GREEN}Automatic security updates enabled!${NC}"
echo -e "${CYAN}Security patches will be applied automatically${NC}"

# Prepare SSH keys for Dokku installation
echo -e "${BLUE}Preparing SSH keys for Dokku installation...${NC}"
if [ -f ~/.ssh/authorized_keys ]; then
    # Extract the first public key and save it as id_rsa.pub for Dokku
    if [ ! -f ~/.ssh/id_rsa.pub ]; then
        echo -e "${BLUE}Creating id_rsa.pub from authorized_keys for Dokku compatibility...${NC}"
        head -n 1 ~/.ssh/authorized_keys > ~/.ssh/id_rsa.pub
        chmod 644 ~/.ssh/id_rsa.pub
        echo -e "${GREEN}Created ~/.ssh/id_rsa.pub from first authorized key${NC}"
    else
        echo -e "${GREEN}SSH key file ~/.ssh/id_rsa.pub already exists${NC}"
    fi
else
    echo -e "${YELLOW}Warning: ~/.ssh/authorized_keys not found. SSH key setup will be manual.${NC}"
fi

# Change to /tmp directory
echo -e "${BLUE}Changing to /tmp directory...${NC}"
cd /tmp

# Install latest version of Dokku
echo -e "${BLUE}Detecting latest Dokku version...${NC}"

# Try to fetch latest version from GitHub API with timeout
LATEST_VERSION=$(curl -s --connect-timeout 10 --max-time 30 https://api.github.com/repos/dokku/dokku/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

# Verify version format (should start with 'v' and contain numbers)
if [ -z "$LATEST_VERSION" ] || [[ ! "$LATEST_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${YELLOW}Could not detect latest version from GitHub API${NC}"
    echo -e "${YELLOW}Falling back to v0.37.2 (latest stable as of script update)${NC}"
    LATEST_VERSION="v0.37.2"
else
    echo -e "${GREEN}Detected latest Dokku version: $LATEST_VERSION${NC}"
fi

echo -e "${BLUE}Installing Dokku $LATEST_VERSION...${NC}"
wget -NP . https://dokku.com/install/$LATEST_VERSION/bootstrap.sh

# Verify bootstrap script was downloaded successfully
if [ ! -f bootstrap.sh ]; then
    echo -e "${RED}Error: Failed to download Dokku bootstrap script${NC}"
    exit 1
fi

# Make bootstrap script executable and run it
chmod +x bootstrap.sh
DOKKU_TAG=$LATEST_VERSION bash bootstrap.sh

echo -e "${GREEN}Dokku installation completed!${NC}"

# Restart Docker to apply DNS configuration
echo -e "${BLUE}Restarting Docker to apply DNS configuration...${NC}"
if systemctl restart docker 2>/dev/null; then
    echo -e "${GREEN}Docker restarted successfully${NC}"
    sleep 3  # Wait for Docker to fully restart
else
    echo -e "${YELLOW}Warning: Could not restart Docker automatically${NC}"
    echo -e "${YELLOW}Please run 'systemctl restart docker' manually after setup${NC}"
fi

# Verify Docker DNS configuration
echo -e "${BLUE}Verifying Docker DNS configuration...${NC}"
if docker run --rm alpine nslookup github.com > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Docker containers can resolve DNS successfully${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Docker DNS verification failed${NC}"
    echo -e "${YELLOW}This may be resolved after the server reboot${NC}"
fi

# Install essential Dokku plugins
echo -e "${PURPLE}Installing essential Dokku plugins...${NC}"

# Install PostgreSQL plugin
echo -e "${BLUE}Installing PostgreSQL plugin...${NC}"
sudo dokku plugin:install https://github.com/dokku/dokku-postgres.git --name postgres
echo -e "${GREEN}PostgreSQL plugin installed successfully!${NC}"

# Install Redis plugin
echo -e "${BLUE}Installing Redis plugin...${NC}"
sudo dokku plugin:install https://github.com/dokku/dokku-redis.git --name redis
echo -e "${GREEN}Redis plugin installed successfully!${NC}"

# Install Let's Encrypt plugin
echo -e "${BLUE}Installing Let's Encrypt plugin...${NC}"
sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git
echo -e "${GREEN}Let's Encrypt plugin installed successfully!${NC}"

# Configure Let's Encrypt email globally
echo -e "${BLUE}Configuring Let's Encrypt email...${NC}"
dokku letsencrypt:set --global email "$LETSENCRYPT_EMAIL"
echo -e "${GREEN}Let's Encrypt email configured globally!${NC}"

# Enable auto-renewal for SSL certificates
echo -e "${BLUE}Setting up SSL certificate auto-renewal...${NC}"
sudo dokku letsencrypt:cron-job --add
echo -e "${GREEN}SSL certificate auto-renewal enabled!${NC}"

echo -e "${GREEN}All plugins installed and configured successfully!${NC}"

# Configure file upload limits for Dokku applications
echo -e "${PURPLE}Configuring file upload limits for Dokku applications...${NC}"

# Create a helper function for setting up file upload limits on applications
echo -e "${BLUE}Creating helper script for configuring file upload limits...${NC}"
cat > /usr/local/bin/dokku-setup-upload-limits << 'EOF'
#!/bin/bash

# Helper script to configure file upload limits for Dokku applications
# Usage: dokku-setup-upload-limits <app-name> [size-limit]

set -e

APP_NAME="$1"
UPLOAD_LIMIT="${2:-20m}"

if [ -z "$APP_NAME" ]; then
    echo "Usage: dokku-setup-upload-limits <app-name> [size-limit]"
    echo "Example: dokku-setup-upload-limits myapp 50m"
    exit 1
fi

echo "Configuring upload limits for app: $APP_NAME (limit: $UPLOAD_LIMIT)"

# Method 1: Use modern Dokku nginx:set command (preferred)
if dokku nginx:set "$APP_NAME" client-max-body-size "$UPLOAD_LIMIT" 2>/dev/null; then
    echo "✓ Set client-max-body-size using dokku nginx:set command"
    
    # Rebuild the nginx config to apply changes
    if dokku proxy:build-config "$APP_NAME" 2>/dev/null; then
        echo "✓ Rebuilt nginx configuration"
    else
        echo "⚠ Warning: Could not rebuild nginx config automatically"
    fi
else
    echo "⚠ Modern dokku nginx:set command not available, using manual configuration..."
    
    # Method 2: Manual nginx configuration (fallback)
    APP_NGINX_DIR="/home/dokku/$APP_NAME/nginx.conf.d"
    
    # Create nginx.conf.d directory if it doesn't exist
    if [ ! -d "$APP_NGINX_DIR" ]; then
        mkdir -p "$APP_NGINX_DIR"
        echo "✓ Created directory: $APP_NGINX_DIR"
    fi
    
    # Create upload configuration file
    UPLOAD_CONF="$APP_NGINX_DIR/upload.conf"
    echo "client_max_body_size $UPLOAD_LIMIT;" > "$UPLOAD_CONF"
    
    # Set proper ownership
    chown dokku:dokku "$UPLOAD_CONF"
    chmod 644 "$UPLOAD_CONF"
    
    echo "✓ Created upload configuration: $UPLOAD_CONF"
    echo "✓ Set proper ownership and permissions"
fi

# Reload nginx to apply changes
if systemctl reload nginx 2>/dev/null; then
    echo "✓ Reloaded nginx successfully"
elif service nginx reload 2>/dev/null; then
    echo "✓ Reloaded nginx successfully (using service command)"
else
    echo "⚠ Warning: Could not reload nginx automatically"
    echo "Please run 'systemctl reload nginx' or 'service nginx reload' manually"
fi

echo "✅ Upload limit configuration completed for $APP_NAME"
echo ""
echo "To verify the configuration:"
echo "  dokku nginx:show-config $APP_NAME | grep client_max_body_size"
echo ""
echo "To test file uploads, try uploading a file smaller than $UPLOAD_LIMIT"

EOF

# Make the helper script executable
chmod +x /usr/local/bin/dokku-setup-upload-limits
echo -e "${GREEN}Helper script created at /usr/local/bin/dokku-setup-upload-limits${NC}"

# Create a global nginx configuration for default upload limits
echo -e "${BLUE}Setting global default upload limits...${NC}"
GLOBAL_NGINX_CONF="/etc/nginx/conf.d/99-dokku-upload-limits.conf"

cat > "$GLOBAL_NGINX_CONF" << 'EOF'
# Global default upload limits for Dokku applications
# This sets a reasonable default that can be overridden per-app

# Default client max body size (20MB)
# Individual apps can override this using:
# dokku nginx:set <app> client-max-body-size <size>
client_max_body_size 20m;

# Additional timeout settings for large file uploads
client_body_timeout 300s;
client_header_timeout 300s;
proxy_connect_timeout 300s;
proxy_send_timeout 300s;
proxy_read_timeout 300s;
EOF

echo -e "${GREEN}Global upload limits configured in $GLOBAL_NGINX_CONF${NC}"

# Reload nginx to apply global settings
if systemctl reload nginx 2>/dev/null; then
    echo -e "${GREEN}✓ Nginx reloaded successfully${NC}"
elif service nginx reload 2>/dev/null; then
    echo -e "${GREEN}✓ Nginx reloaded successfully (using service command)${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Could not reload nginx automatically${NC}"
    echo -e "${YELLOW}Please run 'systemctl reload nginx' manually after server setup${NC}"
fi

echo -e "${GREEN}File upload limits configuration completed!${NC}"
echo ""
echo -e "${CYAN}Usage examples after deploying applications:${NC}"
echo -e "${CYAN}  # Set 50MB limit for an app named 'myapp'${NC}"
echo -e "${CYAN}  dokku-setup-upload-limits myapp 50m${NC}"
echo -e "${CYAN}  # Or use the modern Dokku command directly${NC}"
echo -e "${CYAN}  dokku nginx:set myapp client-max-body-size 50m${NC}"
echo -e "${CYAN}  dokku proxy:build-config myapp${NC}"
echo ""

# Verify SSH keys are configured for deployment access
echo -e "${BLUE}Verifying SSH keys for deployment access...${NC}"
if [ -f ~/.ssh/authorized_keys ]; then
    # Check if admin key already exists (Dokku auto-imports during installation)
    if dokku ssh-keys:list | grep -q "admin"; then
        echo -e "${GREEN}SSH keys already configured in Dokku for deployment!${NC}"
        echo -e "${CYAN}You can now deploy applications using 'git push dokku main'${NC}"
    else
        # Add keys if not already present
        echo -e "${BLUE}Adding SSH keys to Dokku...${NC}"
        if cat ~/.ssh/authorized_keys | dokku ssh-keys:add admin 2>&1 | grep -q "Duplicate"; then
            echo -e "${GREEN}SSH keys already exist in Dokku (detected via duplicate check)${NC}"
            echo -e "${CYAN}You can now deploy applications using 'git push dokku main'${NC}"
        else
            echo -e "${GREEN}SSH keys added successfully to Dokku!${NC}"
            echo -e "${CYAN}You can now deploy applications using 'git push dokku main'${NC}"
        fi
    fi
else
    echo -e "${YELLOW}Warning: ~/.ssh/authorized_keys not found. You'll need to add SSH keys manually later.${NC}"
    echo -e "${YELLOW}Use: cat ~/.ssh/authorized_keys | dokku ssh-keys:add admin${NC}"
fi

# Configure global domain for multiple applications
echo -e "${BLUE}Configuring global domain for multiple applications...${NC}"

# Try to get IPv4 address first (preferred for sslip.io compatibility)
echo -e "${BLUE}Attempting to detect IPv4 address...${NC}"
SERVER_IP=$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -4 -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null)

# If IPv4 detection failed, fall back to IPv6
if [ -z "$SERVER_IP" ]; then
    echo -e "${YELLOW}IPv4 not available, falling back to IPv6...${NC}"
    SERVER_IP=$(curl -6 -s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -6 -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null)
fi

if [ -n "$SERVER_IP" ]; then
    # Check if the IP is IPv6 (contains colons) and format for sslip.io
    if [[ "$SERVER_IP" == *":"* ]]; then
        # IPv6 address: replace colons with dashes for sslip.io compatibility
        FORMATTED_IP=$(echo "$SERVER_IP" | sed 's/:/-/g')
        echo -e "${YELLOW}Using IPv6 address: $SERVER_IP${NC}"
        echo -e "${BLUE}Formatting for sslip.io: $FORMATTED_IP${NC}"
        SSLIP_DOMAIN="${FORMATTED_IP}.sslip.io"
    else
        # IPv4 address: use as-is
        echo -e "${GREEN}Using IPv4 address: $SERVER_IP${NC}"
        SSLIP_DOMAIN="${SERVER_IP}.sslip.io"
    fi

    dokku domains:set-global "$SSLIP_DOMAIN"
    echo -e "${GREEN}Global domain set to: $SSLIP_DOMAIN${NC}"
    echo -e "${CYAN}This allows multiple apps to run as subdomains (e.g., app1.$SSLIP_DOMAIN, app2.$SSLIP_DOMAIN)${NC}"
else
    echo -e "${YELLOW}Could not detect server IP automatically.${NC}"
    echo -e "${YELLOW}Please run manually: dokku domains:set-global <formatted-ip>.sslip.io${NC}"
    echo -e "${YELLOW}For IPv4: dokku domains:set-global <ipv4>.sslip.io${NC}"
    echo -e "${YELLOW}For IPv6: Replace colons with dashes (e.g., 2a01-4f8-c013-498b--1.sslip.io)${NC}"
fi

echo -e "${GREEN}Dokku server setup completed successfully!${NC}"
echo ""
echo -e "${PURPLE}Next steps after reboot:${NC}"
echo -e "${CYAN}1. Access your server's IP address in a web browser to complete Dokku setup${NC}"
echo -e "${CYAN}2. Deploy your applications using 'git push dokku main'${NC}"
if [ -n "$SSLIP_DOMAIN" ]; then
    echo -e "${CYAN}3. Each app will be accessible at <app-name>.$SSLIP_DOMAIN${NC}"
else
    echo -e "${CYAN}3. Each app will be accessible at <app-name>.<formatted-ip>.sslip.io${NC}"
fi
echo -e "${CYAN}4. Configure custom domains and SSL certificates if needed${NC}"
echo -e "${CYAN}5. Configure file upload limits for apps: dokku-setup-upload-limits <app-name> <size>${NC}"
echo ""
echo -e "${YELLOW}Rebooting server in 5 seconds...${NC}"
sleep 5
reboot
