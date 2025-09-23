# Dokku Deployment Scripts

A collection of bash scripts to automate Dokku server setup and Rails application deployment on Ubuntu servers.

## Scripts Overview

### 1. `setup-dokku-server.sh`
**Purpose**: Prepares a fresh Ubuntu server for Dokku deployment with all necessary plugins and configurations.

**Features**:
- Installs latest Dokku version
- Configures firewall (UFW) with proper ports
- Installs essential plugins (PostgreSQL, Redis, Let's Encrypt)
- Sets up SSL certificate auto-renewal
- Configures global file upload limits
- Sets up automatic domain configuration

### 2. `setup-dokku-app.sh`
**Purpose**: Creates and configures a new Rails application with database, cache, and AWS backup integration.

**Features**:
- Creates Dokku application
- Sets up PostgreSQL database with automated S3 backups
- Configures Redis cache
- Sets Rails production environment variables
- Scales application processes

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
1. Updates system packages
2. Configures firewall (SSH, HTTP, HTTPS)
3. Installs Dokku and essential plugins
4. Sets up SSL certificate auto-renewal
5. Configures global upload limits (20MB default)
6. Reboots the server

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
2. Sets up PostgreSQL database (`<app-name>db`)
3. Configures automated S3 backups (Sunday & Thursday at midnight)
4. Sets up Redis cache (`<app-name>red`)
5. Configures Rails production environment
6. Scales to 1 web worker and 1 background worker

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

### 1. Complete Dokku Web Setup
After the server reboots, visit your server's IP address in a web browser to complete the Dokku setup:
- Add your SSH public key
- Set the hostname/domain

### 2. Deploy Your Application
```bash
# Add Dokku remote to your Rails app
git remote add dokku dokku@your-server-ip:myapp

# Deploy
git push dokku main
```

### 3. Set Custom Domain (Optional)
```bash
# SSH into your server
dokku domains:set myapp yourdomain.com

# Enable SSL
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
- **With sslip.io**: `https://myapp.YOUR_SERVER_IP.sslip.io`
- **With custom domain**: `https://yourdomain.com`

## File Upload Limits

- **Default global limit**: 20MB
- **Per-app configuration**: Use `dokku-configure-upload-limits.sh`
- **Modern Dokku method**: `dokku nginx:set myapp client-max-body-size 50m`

## Database Backups

- **Schedule**: Every Sunday and Thursday at midnight
- **Location**: AWS S3 bucket (configurable, default: "my-app-backups")
- **Retention**: Configured by Dokku postgres plugin settings

## Troubleshooting

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

## Security Notes

- Scripts configure UFW firewall with minimal required ports
- SSL certificates are automatically managed with Let's Encrypt
- Database backups are encrypted in transit to S3
- AWS credentials are passed as parameters (not hardcoded)

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