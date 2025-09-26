#!/bin/bash

# Dokku Rails Application Setup Script
# This script checks for Dokku installation and creates a new application
# Usage: ./setup-dokku-app.sh <app-name> <aws-access-key-id> <aws-secret-access-key> <s3-backup-bucket>

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get S3 backup bucket from command line argument
BACKUP_BUCKET="${4:-my-app-backups}"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if Dokku is installed
check_dokku_installation() {
    print_status "Checking Dokku installation..."
    
    if ! command -v dokku &> /dev/null; then
        print_error "Dokku is not installed or not in PATH"
        print_error "Please install Dokku first: https://dokku.com/docs/getting-started/installation/"
        exit 1
    fi
    
    print_success "Dokku is installed"
    dokku version
}

# Function to check if required plugins are installed
check_required_plugins() {
    print_status "Checking required Dokku plugins..."
    
    local required_plugins=("postgres" "redis" "letsencrypt")
    local missing_plugins=()
    
    for plugin in "${required_plugins[@]}"; do
        if ! dokku plugin:list 2>/dev/null | grep -q "$plugin"; then
            print_error "Plugin '$plugin' is not installed"
            missing_plugins+=("$plugin")
        else
            print_success "Plugin '$plugin' is installed"
        fi
    done
    
    if [ ${#missing_plugins[@]} -gt 0 ]; then
        print_error "Missing required plugins: ${missing_plugins[*]}"
        print_error "Please install the missing plugins before running this script:"
        echo
        for plugin in "${missing_plugins[@]}"; do
            case $plugin in
                "postgres")
                    echo "  sudo dokku plugin:install https://github.com/dokku/dokku-postgres.git"
                    ;;
                "redis")
                    echo "  sudo dokku plugin:install https://github.com/dokku/dokku-redis.git"
                    ;;
                "letsencrypt")
                    echo "  sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git"
                    ;;
            esac
        done
        echo
        exit 1
    fi
}

# Function to validate AWS credentials
validate_aws_credentials() {
    local aws_access_key="$1"
    local aws_secret_key="$2"
    
    if [[ -z "$aws_access_key" ]]; then
        print_error "AWS Access Key ID is required"
        print_error "Usage: $0 <app-name> <aws-access-key-id> <aws-secret-access-key> <s3-backup-bucket>"
        exit 1
    fi

    if [[ -z "$aws_secret_key" ]]; then
        print_error "AWS Secret Access Key is required"
        print_error "Usage: $0 <app-name> <aws-access-key-id> <aws-secret-access-key> <s3-backup-bucket>"
        exit 1
    fi
    
    print_success "AWS credentials provided"
}

# Function to get application name from command line argument
get_app_name() {
    local app_name="$1"
    
    # Check if app name is provided
    if [[ -z "$app_name" ]]; then
        print_error "Application name is required"
        print_error "Usage: $0 <app-name> <aws-access-key-id> <aws-secret-access-key> <s3-backup-bucket>"
        exit 1
    fi
    
    # Validate app name format
    if [[ ! "$app_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]] && [[ ! "$app_name" =~ ^[a-zA-Z0-9]$ ]]; then
        print_error "Invalid application name. Use only letters, numbers, and hyphens. Must start and end with alphanumeric characters."
        exit 1
    fi
    
    # Check if app already exists
    if dokku apps:list | grep -q "^$app_name$"; then
        print_warning "Application '$app_name' already exists, continuing with existing app"
    fi
    
    echo "$app_name"
}

# Function to create Dokku application
create_app() {
    local app_name=$1
    
    print_status "Creating Dokku application: $app_name"
    
    if ! dokku apps:list | grep -q "^$app_name$"; then
        dokku apps:create "$app_name"
        print_success "Application '$app_name' created"
    else
        print_warning "Application '$app_name' already exists, skipping creation"
    fi
}

# Function to setup PostgreSQL database
setup_postgres() {
    local app_name=$1
    local aws_access_key=$2
    local aws_secret_key=$3
    local db_name="${app_name}db"
    
    print_status "Setting up PostgreSQL database: $db_name"
    
    # Create database if it doesn't exist
    if ! dokku postgres:list | grep -q "^$db_name"; then
        dokku postgres:create "$db_name"
        print_success "PostgreSQL database '$db_name' created"
    else
        print_warning "PostgreSQL database '$db_name' already exists, skipping creation"
    fi
    
    # Link database to app
    print_status "Linking database to application..."
    dokku postgres:link "$db_name" "$app_name"
    print_success "Database linked to application"
    
    # Setup backup authentication with AWS credentials
    print_status "Setting up database backup authentication..."
    dokku postgres:backup-auth "$db_name" "$aws_access_key" "$aws_secret_key"
    print_success "Database backup authentication configured"
    
    # Setup backup schedule (every Sunday and Thursday at midnight)
    print_status "Setting up database backup schedule..."
    dokku postgres:backup-schedule "$db_name" "0 0 * * 0,4" "$BACKUP_BUCKET"
    print_success "Database backup schedule configured"
}

# Function to setup Redis
setup_redis() {
    local app_name=$1
    local redis_name="${app_name}red"
    
    print_status "Setting up Redis: $redis_name"
    
    # Create Redis instance if it doesn't exist
    if ! dokku redis:list | grep -q "^$redis_name"; then
        dokku redis:create "$redis_name"
        print_success "Redis instance '$redis_name' created"
    else
        print_warning "Redis instance '$redis_name' already exists, skipping creation"
    fi
    
    # Link Redis to app
    print_status "Linking Redis to application..."
    dokku redis:link "$redis_name" "$app_name"
    print_success "Redis linked to application"
}

# Function to configure Rails environment
configure_rails_env() {
    local app_name=$1
    
    print_status "Configuring Rails environment variables..."
    
    dokku config:set "$app_name" \
        RAILS_ENV=production \
        RACK_ENV=production \
        RAILS_SERVE_STATIC_FILES=true \
        RAILS_LOG_TO_STDOUT=true
    
    print_success "Rails environment configured"
}

# Function to scale application processes
scale_processes() {
    local app_name=$1
    
    print_status "Scaling application processes..."
    
    dokku ps:scale "$app_name" web=1 worker=1
    print_success "Application processes scaled (web=1, worker=1)"
}

# Function to display setup summary
display_summary() {
    local app_name=$1
    
    echo
    print_success "=== SETUP COMPLETE ==="
    echo -e "${GREEN}Application:${NC} $app_name"
    echo -e "${GREEN}Database:${NC} ${app_name}db (PostgreSQL)"
    echo -e "${GREEN}Cache:${NC} ${app_name}red (Redis)"
    echo -e "${GREEN}Environment:${NC} Production"
    echo -e "${GREEN}Backup Bucket:${NC} $BACKUP_BUCKET"
    echo -e "${GREEN}Backup Schedule:${NC} AWS authenticated & scheduled (Sun/Thu at midnight)"
    echo -e "${GREEN}Scaling:${NC} web=1, worker=1"
    echo
}

# Main function
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Dokku Rails Application Setup      ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    # Validate AWS credentials first
    validate_aws_credentials "$2" "$3"
    
    # Check Dokku installation
    check_dokku_installation
    
    # Check required plugins
    check_required_plugins
    
    # Get application name from user or command line argument
    app_name=$(get_app_name "$1")
    
    echo
    print_status "Starting setup for application: $app_name"
    echo
    
    # Create application
    create_app "$app_name"
    
    # Setup PostgreSQL with AWS credentials
    setup_postgres "$app_name" "$2" "$3"
    
    # Setup Redis
    setup_redis "$app_name"
    
    # Configure Rails environment
    configure_rails_env "$app_name"
    
    # Scale processes
    scale_processes "$app_name"
    
    # Display summary
    display_summary "$app_name"
}

# Run main function
main "$@"
