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

# Allow essential services for Dokku + Rails
echo -e "${BLUE}Configuring firewall rules for Dokku applications...${NC}"

# SSH access (essential for server management)
ufw allow 22/tcp comment 'SSH access'
echo -e "${CYAN}✓ SSH (port 22) - Server management${NC}"

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

# Configure UFW to work with Docker
cat > /etc/ufw/after.rules << 'EOF'
# Put Docker behind UFW
*filter
:DOCKER-USER - [0:0]
:ufw-user-input - [0:0]

# Allow established connections
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Drop invalid packets
-A DOCKER-USER -m conntrack --ctstate INVALID -j DROP

# Allow incoming traffic on the default interface
-A DOCKER-USER -i eth0 -j ufw-user-input
-A DOCKER-USER -i enp1s0 -j ufw-user-input

# Drop all other traffic to Docker containers
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

# Change to /tmp directory
echo -e "${BLUE}Changing to /tmp directory...${NC}"
cd /tmp

# Install latest version of Dokku
echo -e "${BLUE}Detecting latest Dokku version...${NC}"
LATEST_VERSION=$(curl -s https://api.github.com/repos/dokku/dokku/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_VERSION" ]; then
    echo -e "${YELLOW}Could not detect latest version, falling back to v0.35.20${NC}"
    LATEST_VERSION="v0.35.20"
fi

echo -e "${BLUE}Installing Dokku $LATEST_VERSION...${NC}"
wget -NP . https://dokku.com/install/$LATEST_VERSION/bootstrap.sh

# Make bootstrap script executable and run it
chmod +x bootstrap.sh
DOKKU_TAG=$LATEST_VERSION bash bootstrap.sh

echo -e "${GREEN}Dokku installation completed!${NC}"

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

# Add SSH keys for admin user
echo -e "${BLUE}Adding SSH keys for admin user...${NC}"
if [ -f ~/.ssh/authorized_keys ]; then
    cat ~/.ssh/authorized_keys | dokku ssh-keys:add admin
    echo -e "${GREEN}SSH keys added successfully!${NC}"
else
    echo -e "${YELLOW}Warning: ~/.ssh/authorized_keys not found. You'll need to add SSH keys manually later.${NC}"
    echo -e "${YELLOW}Use: cat ~/.ssh/authorized_keys | dokku ssh-keys:add admin${NC}"
fi

# Configure global domain for multiple applications
echo -e "${BLUE}Configuring global domain for multiple applications...${NC}"
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || hostname -I | awk '{print $1}')
if [ -n "$SERVER_IP" ]; then
    # Check if the IP is IPv6 (contains colons) and format for sslip.io
    if [[ "$SERVER_IP" == *":"* ]]; then
        # IPv6 address: replace colons with dashes for sslip.io compatibility
        FORMATTED_IP=$(echo "$SERVER_IP" | sed 's/:/-/g')
        echo -e "${YELLOW}Detected IPv6 address: $SERVER_IP${NC}"
        echo -e "${BLUE}Formatting for sslip.io: $FORMATTED_IP${NC}"
        SSLIP_DOMAIN="${FORMATTED_IP}.sslip.io"
    else
        # IPv4 address: use as-is
        echo -e "${YELLOW}Detected IPv4 address: $SERVER_IP${NC}"
        SSLIP_DOMAIN="${SERVER_IP}.sslip.io"
    fi

    dokku domains:set-global "$SSLIP_DOMAIN"
    echo -e "${GREEN}Global domain set to: $SSLIP_DOMAIN${NC}"
    echo -e "${CYAN}This allows multiple apps to run as subdomains (e.g., app1.$SSLIP_DOMAIN, app2.$SSLIP_DOMAIN)${NC}"
else
    echo -e "${YELLOW}Could not detect server IP automatically.${NC}"
    echo -e "${YELLOW}Please run manually: dokku domains:set-global <formatted-ip>.sslip.io${NC}"
    echo -e "${YELLOW}For IPv6, replace colons with dashes (e.g., 2a01-4f8-c013-ae--1.sslip.io)${NC}"
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
