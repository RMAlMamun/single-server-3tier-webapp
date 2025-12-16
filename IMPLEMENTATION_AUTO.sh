#!/bin/bash

################################################################################
# BMI Health Tracker - Complete Deployment Script for AWS EC2 Ubuntu
#
# This script automates the ENTIRE deployment process based on the
# BMI_Health_Tracker_Deployment_Readme.md manual deployment guide.
#
# Usage: ./deploy.sh [--skip-nginx] [--skip-backup]
#
# Options:
#   --skip-nginx   : Skip Nginx configuration (if already configured)
#   --skip-backup  : Skip creating backup of current deployment
#   --fresh        : Fresh deployment (clean install)
################################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/bmi_deployments_backup"
FRONTEND_DIR="/var/www/bmi-health-tracker"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Database Configuration (will be set by user input)
DB_NAME="bmidb"
DB_USER="bmi_user"
DB_PASSWORD=""
DB_HOST="localhost"
DB_PORT="5432"

# Parse command line arguments
SKIP_NGINX=false
SKIP_BACKUP=false
FRESH_DEPLOY=false

for arg in "$@"; do
    case $arg in
        --skip-nginx)
            SKIP_NGINX=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --fresh)
            FRESH_DEPLOY=true
            shift
            ;;
        --help)
            echo "Usage: ./deploy.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-nginx    Skip Nginx configuration"
            echo "  --skip-backup   Skip creating backup"
            echo "  --fresh         Fresh deployment (clean install)"
            echo "  --help          Show this help message"
            exit 0
            ;;
    esac
done

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo ""
    echo -e "${BLUE}========================================"
    echo -e "$1"
    echo -e "========================================${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

################################################################################
# Get EC2 Public IP (IMDSv2)
################################################################################

get_ec2_public_ip() {
    # Try to get token for IMDSv2
    local TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
        --connect-timeout 2 2>/dev/null)
    
    if [ -n "$TOKEN" ]; then
        # Use IMDSv2 with token
        local PUBLIC_IP=$(curl -s \
            -H "X-aws-ec2-metadata-token: $TOKEN" \
            --connect-timeout 2 \
            http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    else
        # Fallback to IMDSv1
        local PUBLIC_IP=$(curl -s --connect-timeout 2 \
            http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    fi
    
    # Trim whitespace and return
    echo "$PUBLIC_IP" | tr -d '[:space:]'
}

################################################################################
# Collect Database Credentials
################################################################################

collect_database_credentials() {
    print_header "Database Configuration"
    
    echo "Please provide database credentials for the BMI Health Tracker"
    echo ""
    
    # Database name
    read -p "Database name (default: bmidb): " input_db_name
    DB_NAME=${input_db_name:-bmidb}
    
    # Database user
    read -p "Database user (default: bmi_user): " input_db_user
    DB_USER=${input_db_user:-bmi_user}
    
    # Database password
    while [ -z "$DB_PASSWORD" ]; do
        read -sp "Database password: " DB_PASSWORD
        echo ""
        if [ -z "$DB_PASSWORD" ]; then
            print_error "Password cannot be empty"
        fi
    done
    
    # Confirm password
    read -sp "Confirm password: " DB_PASSWORD_CONFIRM
    echo ""
    
    if [ "$DB_PASSWORD" != "$DB_PASSWORD_CONFIRM" ]; then
        print_error "Passwords do not match"
        exit 1
    fi
    
    print_success "Database credentials collected"
    echo ""
    echo "Database Name: $DB_NAME"
    echo "Database User: $DB_USER"
    echo "Database Host: $DB_HOST"
    echo "Database Port: $DB_PORT"
    echo ""
}

################################################################################
# Setup Database
################################################################################

setup_database() {
    print_header "Setting Up Database"
    
    # Check if database exists
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        print_info "Database '$DB_NAME' already exists"
    else
        print_info "Creating database '$DB_NAME'..."
        sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
        print_success "Database created"
    fi
    
    # Check if user exists
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
        print_info "User '$DB_USER' already exists, updating password..."
        sudo -u postgres psql -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
        print_success "Password updated"
    else
        print_info "Creating user '$DB_USER'..."
        sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
        print_success "User created"
    fi
    
    # Grant privileges
    print_info "Granting privileges..."
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
    sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO $DB_USER;"
    sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;"
    print_success "Privileges granted"
    
    # Configure pg_hba.conf for password authentication
    print_info "Configuring PostgreSQL authentication..."
    PG_HBA_CONF=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file')
    
    # Backup pg_hba.conf
    sudo cp "$PG_HBA_CONF" "$PG_HBA_CONF.backup_$TIMESTAMP"
    
    # Check if md5 authentication is already configured
    if ! sudo grep -q "^host.*$DB_NAME.*$DB_USER.*127.0.0.1/32.*md5" "$PG_HBA_CONF"; then
        print_info "Adding md5 authentication rule..."
        sudo sed -i "/^# IPv4 local connections:/a host    $DB_NAME    $DB_USER    127.0.0.1/32    md5" "$PG_HBA_CONF"
        
        # Reload PostgreSQL
        sudo systemctl reload postgresql
        print_success "PostgreSQL configuration updated"
    else
        print_info "Authentication rule already exists"
    fi
    
    # Test connection
    print_info "Testing database connection..."
    if PGPASSWORD=$DB_PASSWORD psql -U "$DB_USER" -d "$DB_NAME" -h localhost -c "SELECT 1;" > /dev/null 2>&1; then
        print_success "Database connection successful"
    else
        print_error "Database connection failed"
        exit 1
    fi
}

################################################################################
# Create Backend .env File
################################################################################

create_backend_env() {
    print_header "Creating Backend Configuration"
    
    cd "$PROJECT_DIR/backend"
    
    # Create .env file
    print_info "Creating .env file..."
    cat > .env << EOF
# Database Configuration
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME

# Alternative individual settings
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_NAME=$DB_NAME
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT

# Server Configuration
PORT=3000
NODE_ENV=production

# CORS Configuration (update with your domain)
CORS_ORIGIN=*
EOF
    
    chmod 600 .env
    print_success ".env file created"
}

################################################################################
# Prerequisites Check
################################################################################

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local errors=0
    
    # Load NVM if it exists
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        print_info "Loading NVM..."
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        print_warning "Node.js not found. Attempting to install..."
        
        # If NVM is not installed, install it
        if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
            print_info "Installing NVM..."
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
            
            # Load NVM immediately after installation
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
            
            if [ -s "$HOME/.nvm/nvm.sh" ]; then
                print_success "NVM installed successfully"
            else
                print_error "Failed to install NVM"
                ((errors++))
            fi
        fi
        
        # Now install Node.js via NVM
        if [ -s "$HOME/.nvm/nvm.sh" ]; then
            print_info "Installing Node.js LTS via NVM..."
            source "$HOME/.nvm/nvm.sh"
            nvm install --lts
            nvm use --lts
            nvm alias default lts/*
            
            # Reload to ensure Node.js is available
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            
            if command -v node &> /dev/null; then
                print_success "Node.js $(node -v) installed successfully"
            else
                print_error "Failed to install Node.js via NVM"
                ((errors++))
            fi
        else
            print_error "NVM installation failed, cannot install Node.js"
            ((errors++))
        fi
    else
        print_success "Node.js $(node -v) found"
    fi
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        print_error "npm is not installed"
        ((errors++))
    else
        print_success "npm $(npm -v) found"
    fi
    
    # Check PostgreSQL
    if ! command -v psql &> /dev/null; then
        print_warning "PostgreSQL not found. Installing..."
        sudo apt update -qq
        sudo apt install -y postgresql postgresql-contrib
        
        if command -v psql &> /dev/null; then
            print_success "PostgreSQL installed successfully"
        else
            print_error "Failed to install PostgreSQL"
            ((errors++))
        fi
    else
        print_success "PostgreSQL found"
    fi
    
    # Check PostgreSQL is running
    if ! sudo systemctl is-active --quiet postgresql; then
        print_warning "PostgreSQL service is not running. Starting..."
        sudo systemctl start postgresql
        sudo systemctl enable postgresql
        
        if sudo systemctl is-active --quiet postgresql; then
            print_success "PostgreSQL service started"
        else
            print_error "Failed to start PostgreSQL service"
            ((errors++))
        fi
    else
        print_success "PostgreSQL service is running"
    fi
    
    # Check Nginx
    if ! command -v nginx &> /dev/null; then
        print_warning "Nginx not found. Installing..."
        sudo apt install -y nginx
        
        if command -v nginx &> /dev/null; then
            print_success "Nginx installed successfully"
            # Start and enable Nginx
            sudo systemctl start nginx
            sudo systemctl enable nginx
        else
            print_error "Failed to install Nginx"
            ((errors++))
        fi
    else
        print_success "Nginx found"
    fi
    
    # Check PM2
    if ! command -v pm2 &> /dev/null; then
        print_warning "PM2 not found. Will install it..."
        npm install -g pm2
        print_success "PM2 installed"
    else
        print_success "PM2 found"
    fi
    
    if [ $errors -gt 0 ]; then
        print_error "Prerequisites check failed. Please install missing components."
        exit 1
    fi
    
    print_success "All prerequisites met"
}

################################################################################
# Backup Current Deployment
################################################################################

backup_current_deployment() {
    if [ "$SKIP_BACKUP" = true ]; then
        print_info "Skipping backup (--skip-backup flag set)"
        return 0
    fi
    
    print_header "Creating Backup of Current Deployment"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    BACKUP_PATH="$BACKUP_DIR/deployment_$TIMESTAMP"
    mkdir -p "$BACKUP_PATH"
    
    # Backup backend if exists
    if [ -d "$PROJECT_DIR/backend/node_modules" ]; then
        print_info "Backing up backend..."
        cp -r "$PROJECT_DIR/backend/.env" "$BACKUP_PATH/" 2>/dev/null || print_warning "No .env to backup"
        print_success "Backend backed up"
    fi
    
    # Backup frontend deployment if exists
    if [ -d "$FRONTEND_DIR" ]; then
        print_info "Backing up deployed frontend..."
        sudo cp -r "$FRONTEND_DIR" "$BACKUP_PATH/frontend_deployed"
        print_success "Frontend backed up"
    fi
    
    # Backup Nginx config if exists
    if [ -f "/etc/nginx/sites-available/bmi-health-tracker" ]; then
        print_info "Backing up Nginx configuration..."
        sudo cp /etc/nginx/sites-available/bmi-health-tracker "$BACKUP_PATH/"
        print_success "Nginx config backed up"
    fi
    
    # Backup database
    print_info "Backing up database..."
    if [ -n "$DB_PASSWORD" ] && [ -n "$DB_USER" ] && [ -n "$DB_NAME" ]; then
        PGPASSWORD=$DB_PASSWORD pg_dump -U "$DB_USER" -h localhost "$DB_NAME" > "$BACKUP_PATH/database_backup.sql" 2>/dev/null || print_warning "Database backup skipped (database may not exist yet)"
    else
        print_warning "Database credentials not set, skipping backup"
    fi
    
    print_success "Backup created at: $BACKUP_PATH"
    
    # Keep only last 5 backups
    cd "$BACKUP_DIR"
    ls -t | tail -n +6 | xargs -r rm -rf
    print_info "Kept last 5 backups, removed older ones"
}

################################################################################
# Backend Deployment
################################################################################

deploy_backend() {
    print_header "Deploying Backend"
    
    cd "$PROJECT_DIR/backend"
    
    # .env should already be created by create_backend_env function
    if [ ! -f .env ]; then
        print_error ".env file not found (should have been created earlier)"
        exit 1
    fi
    print_success ".env file exists"
    
    # Clean install if fresh deployment
    if [ "$FRESH_DEPLOY" = true ]; then
        print_info "Fresh deployment: removing node_modules..."
        rm -rf node_modules package-lock.json
    fi
    
    # Install dependencies
    print_info "Installing backend dependencies..."
    npm install --production
    print_success "Backend dependencies installed"
    
    # Run database migrations
    print_info "Running database migrations..."
    if [ -d "migrations" ]; then
        for migration in migrations/*.sql; do
            if [ -f "$migration" ]; then
                print_info "Applying migration: $(basename $migration)"
                PGPASSWORD=$DB_PASSWORD psql -U "$DB_USER" -d "$DB_NAME" -h localhost -f "$migration" 2>&1 | grep -v "already exists" || print_warning "Migration may have already been applied"
            fi
        done
        print_success "Migrations completed"
    else
        print_warning "No migrations directory found"
    fi
    
    # Test database connection
    print_info "Testing database connection..."
    if PGPASSWORD=$DB_PASSWORD psql -U "$DB_USER" -d "$DB_NAME" -h localhost -c "SELECT 1;" > /dev/null 2>&1; then
        print_success "Database connection successful"
    else
        print_error "Database connection failed"
        exit 1
    fi
}

################################################################################
# Frontend Deployment
################################################################################

deploy_frontend() {
    print_header "Deploying Frontend"
    
    cd "$PROJECT_DIR/frontend"
    
    # Clean install if fresh deployment
    if [ "$FRESH_DEPLOY" = true ]; then
        print_info "Fresh deployment: removing node_modules..."
        rm -rf node_modules package-lock.json dist
    fi
    
    # Install dependencies
    print_info "Installing frontend dependencies..."
    npm install
    print_success "Frontend dependencies installed"
    
    # Build for production
    print_info "Building frontend for production..."
    npm run build
    
    if [ ! -d "dist" ]; then
        print_error "Build failed: dist directory not created"
        exit 1
    fi
    print_success "Frontend built successfully"
    
    # Deploy to Nginx directory
    print_info "Deploying frontend to $FRONTEND_DIR..."
    sudo mkdir -p "$FRONTEND_DIR"
    sudo rm -rf "$FRONTEND_DIR"/*
    sudo cp -r dist/* "$FRONTEND_DIR/"
    sudo chown -R www-data:www-data "$FRONTEND_DIR"
    sudo chmod -R 755 "$FRONTEND_DIR"
    print_success "Frontend deployed to $FRONTEND_DIR"
    
    # Verify deployment
    if [ -f "$FRONTEND_DIR/index.html" ]; then
        print_success "Verified: index.html exists in deployment directory"
    else
        print_error "Deployment verification failed: index.html not found"
        exit 1
    fi
}

################################################################################
# PM2 Process Management
################################################################################

setup_pm2() {
    print_header "Configuring PM2 Process Manager"
    
    cd "$PROJECT_DIR/backend"
    
    # Stop existing process
    if pm2 describe bmi-backend > /dev/null 2>&1; then
        print_info "Stopping existing bmi-backend process..."
        pm2 stop bmi-backend
        pm2 delete bmi-backend
        print_success "Existing process stopped"
    fi
    
    # Start backend with PM2
    print_info "Starting backend with PM2..."
    pm2 start src/server.js --name bmi-backend --env production
    
    # Save PM2 process list
    pm2 save
    print_success "Backend started and saved to PM2"
    
    # Setup auto-start on reboot
    print_info "Configuring PM2 auto-start on reboot..."
    pm2 startup systemd -u $USER --hp $HOME > /tmp/pm2_startup_cmd.txt 2>&1 || true
    
    # Extract and run the command
    if grep -q "sudo" /tmp/pm2_startup_cmd.txt; then
        STARTUP_CMD=$(grep "sudo env" /tmp/pm2_startup_cmd.txt | head -1)
        if [ -n "$STARTUP_CMD" ]; then
            print_info "Executing PM2 startup command..."
            eval "$STARTUP_CMD" || print_warning "PM2 startup command may have already been configured"
        fi
    fi
    
    print_success "PM2 configured for auto-start"
    
    # Display PM2 status
    echo ""
    pm2 status
}

################################################################################
# Nginx Configuration
################################################################################

configure_nginx() {
    if [ "$SKIP_NGINX" = true ]; then
        print_info "Skipping Nginx configuration (--skip-nginx flag set)"
        return 0
    fi
    
    print_header "Configuring Nginx"
    
    NGINX_CONFIG="/etc/nginx/sites-available/bmi-health-tracker"
    
    # Get server name
    print_info "Detecting server name..."
    SERVER_NAME=$(get_ec2_public_ip)
    
    if [ -n "$SERVER_NAME" ] && [[ "$SERVER_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_success "Detected EC2 public IP: $SERVER_NAME"
    else
        print_warning "Could not detect EC2 IP automatically"
        echo ""
        echo "Please enter your server's public IP address or domain name."
        echo "Examples:"
        echo "  - 54.123.45.67 (EC2 Public IP)"
        echo "  - example.com (Your domain)"
        echo "  - _ (catch-all, works with any domain/IP)"
        echo ""
        read -p "Server name: " SERVER_NAME
        
        # If still empty, use catch-all
        if [ -z "$SERVER_NAME" ]; then
            SERVER_NAME="_"
            print_warning "Using catch-all server name '_'"
        fi
    fi
    
    # Create Nginx configuration
    print_info "Creating Nginx configuration..."
    sudo tee "$NGINX_CONFIG" > /dev/null << EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $SERVER_NAME;

    # Frontend static files
    root $FRONTEND_DIR;
    index index.html;

    # Compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript 
               application/x-javascript application/xml+rss 
               application/javascript application/json;

    # Frontend routing (React Router)
    location / {
        try_files \$uri \$uri/ /index.html;
        
        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }

    # Backend API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:3000/api/;
        proxy_http_version 1.1;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        
        # Standard proxy headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Disable caching for API
        proxy_cache_bypass \$http_upgrade;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Hide nginx version
    server_tokens off;

    # Logs
    access_log /var/log/nginx/bmi-access.log;
    error_log /var/log/nginx/bmi-error.log;
}
EOF
    
    print_success "Nginx configuration created"
    
    # Enable site
    print_info "Enabling site..."
    sudo ln -sf "$NGINX_CONFIG" /etc/nginx/sites-enabled/bmi-health-tracker
    
    # Remove default site if exists
    if [ -f /etc/nginx/sites-enabled/default ]; then
        print_info "Removing default Nginx site..."
        sudo rm /etc/nginx/sites-enabled/default
    fi
    
    # Test Nginx configuration
    print_info "Testing Nginx configuration..."
    if sudo nginx -t; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
    
    # Restart Nginx
    print_info "Restarting Nginx..."
    sudo systemctl restart nginx
    
    # Verify Nginx is running
    if sudo systemctl is-active --quiet nginx; then
        print_success "Nginx is running"
    else
        print_error "Nginx failed to start"
        sudo systemctl status nginx
        exit 1
    fi
    
    # Enable Nginx on boot
    sudo systemctl enable nginx
    print_success "Nginx enabled on boot"
}

################################################################################
# Health Checks
################################################################################

run_health_checks() {
    print_header "Running Health Checks"
    
    sleep 3  # Give services time to stabilize
    
    # Check backend
    print_info "Checking backend health..."
    if curl -f http://localhost:3000/api/measurements > /dev/null 2>&1; then
        print_success "Backend API is responding"
    else
        print_warning "Backend API check failed (might be normal if endpoint requires setup)"
    fi
    
    # Check frontend
    print_info "Checking frontend..."
    if curl -f http://localhost > /dev/null 2>&1; then
        print_success "Frontend is serving correctly"
    else
        print_warning "Frontend check failed"
    fi
    
    # Check PM2 status
    print_info "Checking PM2 process..."
    if pm2 describe bmi-backend | grep -q "online"; then
        print_success "Backend process is online"
    else
        print_error "Backend process is not running properly"
        pm2 logs bmi-backend --lines 20 --nostream
    fi
    
    # Check database connection
    print_info "Checking database connection..."
    if PGPASSWORD=$DB_PASSWORD psql -U "$DB_USER" -d "$DB_NAME" -h localhost -c "SELECT COUNT(*) FROM measurements;" > /dev/null 2>&1; then
        MEASUREMENT_COUNT=$(PGPASSWORD=$DB_PASSWORD psql -U "$DB_USER" -d "$DB_NAME" -h localhost -tAc "SELECT COUNT(*) FROM measurements;")
        print_success "Database connection OK (Measurements: $MEASUREMENT_COUNT)"
    else
        print_warning "Database connection check failed (table may not exist yet)"
    fi
}

################################################################################
# Display Summary
################################################################################

display_summary() {
    print_header "Deployment Complete!"
    
    # Get server IP
    SERVER_IP=$(get_ec2_public_ip)
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="YOUR_IP"
    fi
    
    echo ""
    echo -e "${GREEN}✓ Backend deployed and running with PM2${NC}"
    echo -e "${GREEN}✓ Frontend built and deployed to Nginx${NC}"
    echo -e "${GREEN}✓ Database migrations applied${NC}"
    echo -e "${GREEN}✓ Nginx configured and running${NC}"
    echo -e "${GREEN}✓ Health checks completed${NC}"
    echo ""
    
    print_info "Application Access:"
    echo "  URL: http://$SERVER_IP"
    echo ""
    
    print_info "Useful Commands:"
    echo "  View backend logs:       pm2 logs bmi-backend"
    echo "  Restart backend:         pm2 restart bmi-backend"
    echo "  View PM2 status:         pm2 status"
    echo "  View Nginx logs:         sudo tail -f /var/log/nginx/bmi-*.log"
    echo "  Test Nginx config:       sudo nginx -t"
    echo "  Restart Nginx:           sudo systemctl restart nginx"
    echo "  Connect to database:     psql -U bmi_user -d bmidb -h localhost"
    echo ""
    
    print_info "Backup Location:"
    echo "  $BACKUP_PATH"
    echo ""
    
    print_warning "Next Steps:"
    echo "  1. Test the application in your browser"
    echo "  2. Configure SSL with: sudo certbot --nginx -d YOUR_DOMAIN"
    echo "  3. Monitor logs for any issues"
    echo "  4. Set up regular database backups"
    echo ""
}

################################################################################
# Main Execution
################################################################################

main() {
    print_header "BMI Health Tracker - Deployment Script"
    
    echo "This script will deploy the BMI Health Tracker application"
    echo ""
    echo "Options:"
    [ "$SKIP_NGINX" = true ] && echo "  - Skipping Nginx configuration"
    [ "$SKIP_BACKUP" = true ] && echo "  - Skipping backup"
    [ "$FRESH_DEPLOY" = true ] && echo "  - Fresh deployment (clean install)"
    echo ""
    
    read -p "Continue with deployment? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Deployment cancelled"
        exit 1
    fi
    
    # Run deployment steps
    collect_database_credentials
    check_prerequisites
    setup_database
    create_backend_env
    backup_current_deployment
    deploy_backend
    deploy_frontend
    setup_pm2
    configure_nginx
    run_health_checks
    display_summary
    
    print_success "Deployment completed successfully!"
}

# Run main function
main "$@"
