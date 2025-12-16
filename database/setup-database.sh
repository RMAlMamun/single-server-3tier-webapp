#!/bin/bash

################################################################################
# BMI Health Tracker - Complete Database Setup Script
# 
# This script handles EVERYTHING related to PostgreSQL database setup:
# - PostgreSQL installation (if not installed)
# - Service configuration and startup
# - User and database creation
# - Running migrations
# - Connection testing
# - Security configuration
# - Sample data seeding (optional)
#
# Usage: sudo ./setup-database.sh
################################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DB_USER="bmi_user"
DB_NAME="bmidb"
DB_VERSION="14"  # PostgreSQL version

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}"
    echo "========================================"
    echo "$1"
    echo "========================================"
    echo -e "${NC}"
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

################################################################################
# PostgreSQL Installation Check
################################################################################

check_postgresql_installed() {
    print_header "Checking PostgreSQL Installation"
    
    if command -v psql &> /dev/null; then
        INSTALLED_VERSION=$(psql --version | awk '{print $3}' | cut -d. -f1)
        print_success "PostgreSQL $INSTALLED_VERSION is already installed"
        return 0
    else
        print_warning "PostgreSQL is not installed"
        return 1
    fi
}

install_postgresql() {
    print_header "Installing PostgreSQL $DB_VERSION"
    
    print_info "Updating package lists..."
    apt update -qq
    
    print_info "Installing PostgreSQL $DB_VERSION..."
    apt install -y postgresql-$DB_VERSION postgresql-contrib-$DB_VERSION
    
    print_success "PostgreSQL $DB_VERSION installed successfully"
}

################################################################################
# PostgreSQL Service Management
################################################################################

start_postgresql_service() {
    print_header "Starting PostgreSQL Service"
    
    # Start PostgreSQL service
    systemctl start postgresql
    print_success "PostgreSQL service started"
    
    # Enable on boot
    systemctl enable postgresql
    print_success "PostgreSQL service enabled on boot"
    
    # Check status
    if systemctl is-active --quiet postgresql; then
        print_success "PostgreSQL service is running"
    else
        print_error "PostgreSQL service failed to start"
        systemctl status postgresql
        exit 1
    fi
}

################################################################################
# Database User and Database Creation
################################################################################

create_database_user() {
    print_header "Creating Database User"
    
    # Check if user already exists
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
        print_warning "User '$DB_USER' already exists"
        read -p "Do you want to drop and recreate? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo -u postgres psql -c "DROP USER IF EXISTS $DB_USER CASCADE;"
            print_info "Dropped existing user '$DB_USER'"
        else
            print_info "Keeping existing user"
            return 0
        fi
    fi
    
    # Get password
    while true; do
        read -sp "Enter password for database user '$DB_USER': " DB_PASS
        echo
        read -sp "Confirm password: " DB_PASS_CONFIRM
        echo
        
        if [ "$DB_PASS" = "$DB_PASS_CONFIRM" ]; then
            break
        else
            print_error "Passwords do not match. Please try again."
        fi
    done
    
    # Store password for later use
    export DB_PASSWORD="$DB_PASS"
    
    # Create user
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
    print_success "User '$DB_USER' created successfully"
}

create_database() {
    print_header "Creating Database"
    
    # Check if database already exists
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        print_warning "Database '$DB_NAME' already exists"
        read -p "Do you want to drop and recreate? (WARNING: All data will be lost!) (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Terminate existing connections
            sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB_NAME';" 2>/dev/null || true
            sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;"
            print_info "Dropped existing database '$DB_NAME'"
        else
            print_info "Keeping existing database"
            return 0
        fi
    fi
    
    # Create database
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
    print_success "Database '$DB_NAME' created successfully"
    
    # Grant privileges
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
    sudo -u postgres psql -d $DB_NAME -c "GRANT ALL ON SCHEMA public TO $DB_USER;"
    sudo -u postgres psql -d $DB_NAME -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;"
    sudo -u postgres psql -d $DB_NAME -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;"
    print_success "Privileges granted to '$DB_USER'"
}

################################################################################
# Database Configuration
################################################################################

configure_postgresql() {
    print_header "Configuring PostgreSQL"
    
    # Find postgresql.conf location
    PG_CONF=$(sudo -u postgres psql -tAc "SHOW config_file")
    PG_HBA=$(sudo -u postgres psql -tAc "SHOW hba_file")
    
    print_info "PostgreSQL config: $PG_CONF"
    print_info "pg_hba.conf: $PG_HBA"
    
    # Backup original configs
    cp "$PG_CONF" "${PG_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$PG_HBA" "${PG_HBA}.backup.$(date +%Y%m%d_%H%M%S)"
    print_info "Backed up configuration files"
    
    # Update pg_hba.conf to allow local connections with password
    if ! grep -q "# BMI Health Tracker config" "$PG_HBA"; then
        cat >> "$PG_HBA" << EOF

# BMI Health Tracker config
local   $DB_NAME        $DB_USER                                md5
host    $DB_NAME        $DB_USER        127.0.0.1/32            md5
host    $DB_NAME        $DB_USER        ::1/128                 md5
EOF
        print_success "Updated pg_hba.conf for password authentication"
    fi
    
    # Optimize PostgreSQL settings for small applications
    if ! grep -q "# BMI Health Tracker tuning" "$PG_CONF"; then
        cat >> "$PG_CONF" << EOF

# BMI Health Tracker tuning
max_connections = 100
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 2621kB
min_wal_size = 1GB
max_wal_size = 4GB
EOF
        print_success "Added performance tuning to postgresql.conf"
    fi
    
    # Reload PostgreSQL to apply changes
    systemctl reload postgresql
    print_success "PostgreSQL configuration reloaded"
}

################################################################################
# Run Migrations
################################################################################

run_migrations() {
    print_header "Running Database Migrations"
    
    MIGRATIONS_DIR="$PROJECT_ROOT/backend/migrations"
    
    if [ ! -d "$MIGRATIONS_DIR" ]; then
        print_warning "Migrations directory not found at $MIGRATIONS_DIR"
        return 0
    fi
    
    # Set password for psql
    export PGPASSWORD="$DB_PASSWORD"
    
    # Find all migration files
    MIGRATION_FILES=$(find "$MIGRATIONS_DIR" -name "*.sql" | sort)
    
    if [ -z "$MIGRATION_FILES" ]; then
        print_warning "No migration files found"
        return 0
    fi
    
    print_info "Found $(echo "$MIGRATION_FILES" | wc -l) migration file(s)"
    
    # Run each migration
    for MIGRATION_FILE in $MIGRATION_FILES; do
        MIGRATION_NAME=$(basename "$MIGRATION_FILE")
        print_info "Running migration: $MIGRATION_NAME"
        
        if psql -U "$DB_USER" -d "$DB_NAME" -h localhost -f "$MIGRATION_FILE" 2>&1; then
            print_success "Migration $MIGRATION_NAME completed"
        else
            print_error "Migration $MIGRATION_NAME failed"
            exit 1
        fi
    done
    
    print_success "All migrations completed successfully"
    
    # Unset password
    unset PGPASSWORD
}

################################################################################
# Seed Sample Data (Optional)
################################################################################

seed_sample_data() {
    print_header "Seed Sample Data"
    
    read -p "Do you want to add sample data for testing? (y/n): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipping sample data"
        return 0
    fi
    
    print_info "Inserting sample BMI measurements..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    psql -U "$DB_USER" -d "$DB_NAME" -h localhost << 'EOF'
-- Sample measurements for testing
INSERT INTO measurements (weight_kg, height_cm, age, gender, created_at) VALUES
(70.5, 175, 25, 'male', NOW() - INTERVAL '10 days'),
(65.2, 162, 30, 'female', NOW() - INTERVAL '9 days'),
(85.0, 180, 35, 'male', NOW() - INTERVAL '8 days'),
(58.5, 155, 22, 'female', NOW() - INTERVAL '7 days'),
(92.3, 185, 40, 'male', NOW() - INTERVAL '6 days'),
(72.0, 168, 28, 'female', NOW() - INTERVAL '5 days'),
(68.5, 172, 26, 'male', NOW() - INTERVAL '4 days'),
(61.0, 160, 24, 'female', NOW() - INTERVAL '3 days'),
(78.5, 178, 32, 'male', NOW() - INTERVAL '2 days'),
(55.0, 158, 21, 'female', NOW() - INTERVAL '1 day');

SELECT COUNT(*) as total_measurements FROM measurements;
EOF
    
    unset PGPASSWORD
    
    print_success "Sample data inserted successfully"
}

################################################################################
# Test Database Connection
################################################################################

test_connection() {
    print_header "Testing Database Connection"
    
    export PGPASSWORD="$DB_PASSWORD"
    
    # Test connection
    if psql -U "$DB_USER" -d "$DB_NAME" -h localhost -c "SELECT version();" > /dev/null 2>&1; then
        print_success "Database connection successful"
    else
        print_error "Database connection failed"
        exit 1
    fi
    
    # List tables
    print_info "Existing tables:"
    psql -U "$DB_USER" -d "$DB_NAME" -h localhost -c "\dt"
    
    # Count records
    TABLE_COUNT=$(psql -U "$DB_USER" -d "$DB_NAME" -h localhost -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")
    print_info "Total tables: $TABLE_COUNT"
    
    unset PGPASSWORD
}

################################################################################
# Generate Environment File
################################################################################

generate_env_file() {
    print_header "Generating Environment Configuration"
    
    ENV_FILE="$PROJECT_ROOT/backend/.env"
    ENV_EXAMPLE="$PROJECT_ROOT/backend/.env.example"
    
    # Create .env file
    cat > "$ENV_FILE" << EOF
# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD

# Database URL (for some ORMs)
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME

# Server Configuration
PORT=3000
NODE_ENV=development

# Session Secret (generate a random string in production)
SESSION_SECRET=$(openssl rand -hex 32)

# CORS Settings
CORS_ORIGIN=http://localhost:5173
EOF
    
    print_success "Created $ENV_FILE"
    
    # Also create .env.example (without sensitive data)
    cat > "$ENV_EXAMPLE" << EOF
# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=bmidb
DB_USER=bmi_user
DB_PASSWORD=your_password_here

# Database URL
DATABASE_URL=postgresql://bmi_user:your_password@localhost:5432/bmidb

# Server Configuration
PORT=3000
NODE_ENV=development

# Session Secret
SESSION_SECRET=your_secret_here

# CORS Settings
CORS_ORIGIN=http://localhost:5173
EOF
    
    print_success "Created $ENV_EXAMPLE"
    
    # Set proper permissions
    chmod 600 "$ENV_FILE"
    chmod 644 "$ENV_EXAMPLE"
    
    print_warning "IMPORTANT: The .env file contains sensitive credentials"
    print_warning "Make sure it's listed in .gitignore"
}

################################################################################
# Create Database Backup Script
################################################################################

create_backup_script() {
    print_header "Creating Backup Script"
    
    BACKUP_SCRIPT="$SCRIPT_DIR/backup-database.sh"
    
    cat > "$BACKUP_SCRIPT" << 'BACKUP_EOF'
#!/bin/bash

# Database Backup Script for BMI Health Tracker

set -e

# Configuration
DB_USER="bmi_user"
DB_NAME="bmidb"
BACKUP_DIR="$HOME/bmi_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.sql"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Get password
read -sp "Enter database password: " DB_PASSWORD
echo

export PGPASSWORD="$DB_PASSWORD"

# Create backup
echo "Creating backup..."
pg_dump -U "$DB_USER" -h localhost "$DB_NAME" > "$BACKUP_FILE"

# Compress backup
gzip "$BACKUP_FILE"

echo "Backup created: ${BACKUP_FILE}.gz"

# Keep only last 7 backups
cd "$BACKUP_DIR"
ls -t ${DB_NAME}_*.sql.gz | tail -n +8 | xargs -r rm

echo "Backup complete!"

unset PGPASSWORD
BACKUP_EOF
    
    chmod +x "$BACKUP_SCRIPT"
    print_success "Created backup script: $BACKUP_SCRIPT"
}

################################################################################
# Create Database Restore Script
################################################################################

create_restore_script() {
    print_header "Creating Restore Script"
    
    RESTORE_SCRIPT="$SCRIPT_DIR/restore-database.sh"
    
    cat > "$RESTORE_SCRIPT" << 'RESTORE_EOF'
#!/bin/bash

# Database Restore Script for BMI Health Tracker

set -e

# Configuration
DB_USER="bmi_user"
DB_NAME="bmidb"
BACKUP_DIR="$HOME/bmi_backups"

if [ -z "$1" ]; then
    echo "Usage: $0 <backup_file.sql.gz>"
    echo ""
    echo "Available backups:"
    ls -lh "$BACKUP_DIR"/*.sql.gz 2>/dev/null || echo "No backups found"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Get password
read -sp "Enter database password: " DB_PASSWORD
echo

export PGPASSWORD="$DB_PASSWORD"

# Decompress if needed
if [[ "$BACKUP_FILE" == *.gz ]]; then
    echo "Decompressing backup..."
    gunzip -k "$BACKUP_FILE"
    BACKUP_FILE="${BACKUP_FILE%.gz}"
fi

# Drop existing connections
echo "Terminating existing connections..."
psql -U "$DB_USER" -h localhost -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB_NAME';" 2>/dev/null || true

# Restore
echo "Restoring database..."
psql -U "$DB_USER" -h localhost "$DB_NAME" < "$BACKUP_FILE"

echo "Database restored successfully!"

unset PGPASSWORD
RESTORE_EOF
    
    chmod +x "$RESTORE_SCRIPT"
    print_success "Created restore script: $RESTORE_SCRIPT"
}

################################################################################
# Display Summary
################################################################################

display_summary() {
    print_header "Database Setup Complete!"
    
    echo ""
    echo -e "${GREEN}✓ PostgreSQL installed and running${NC}"
    echo -e "${GREEN}✓ Database '$DB_NAME' created${NC}"
    echo -e "${GREEN}✓ User '$DB_USER' created with privileges${NC}"
    echo -e "${GREEN}✓ Migrations completed${NC}"
    echo -e "${GREEN}✓ Connection tested successfully${NC}"
    echo -e "${GREEN}✓ Environment file generated${NC}"
    echo -e "${GREEN}✓ Backup/Restore scripts created${NC}"
    echo ""
    
    print_info "Database Connection Details:"
    echo "  Host:     localhost"
    echo "  Port:     5432"
    echo "  Database: $DB_NAME"
    echo "  User:     $DB_USER"
    echo ""
    
    print_info "Connection String:"
    echo "  postgresql://$DB_USER:[password]@localhost:5432/$DB_NAME"
    echo ""
    
    print_info "Configuration File:"
    echo "  $PROJECT_ROOT/backend/.env"
    echo ""
    
    print_info "Useful Commands:"
    echo "  Connect to database:"
    echo "    psql -U $DB_USER -d $DB_NAME -h localhost"
    echo ""
    echo "  Check PostgreSQL status:"
    echo "    sudo systemctl status postgresql"
    echo ""
    echo "  View PostgreSQL logs:"
    echo "    sudo journalctl -u postgresql -f"
    echo ""
    echo "  Backup database:"
    echo "    $SCRIPT_DIR/backup-database.sh"
    echo ""
    echo "  Restore database:"
    echo "    $SCRIPT_DIR/restore-database.sh <backup_file>"
    echo ""
    
    print_warning "Security Reminders:"
    echo "  1. Never commit .env file to Git"
    echo "  2. Use strong passwords in production"
    echo "  3. Regular backups are recommended"
    echo "  4. Restrict database access by IP in production"
    echo ""
}

################################################################################
# Main Execution
################################################################################

main() {
    print_header "BMI Health Tracker - Complete Database Setup"
    
    echo "This script will set up PostgreSQL database for BMI Health Tracker"
    echo ""
    echo "It will:"
    echo "  1. Install PostgreSQL (if not installed)"
    echo "  2. Configure PostgreSQL service"
    echo "  3. Create database user and database"
    echo "  4. Run all migrations"
    echo "  5. Test connections"
    echo "  6. Generate configuration files"
    echo "  7. Create backup/restore scripts"
    echo ""
    
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Setup cancelled"
        exit 1
    fi
    
    # Check if running as root
    check_root
    
    # Step 1: Check/Install PostgreSQL
    if ! check_postgresql_installed; then
        install_postgresql
    fi
    
    # Step 2: Start PostgreSQL service
    start_postgresql_service
    
    # Step 3: Configure PostgreSQL
    configure_postgresql
    
    # Step 4: Create database user
    create_database_user
    
    # Step 5: Create database
    create_database
    
    # Step 6: Run migrations
    run_migrations
    
    # Step 7: Seed sample data (optional)
    seed_sample_data
    
    # Step 8: Test connection
    test_connection
    
    # Step 9: Generate environment file
    generate_env_file
    
    # Step 10: Create backup script
    create_backup_script
    
    # Step 11: Create restore script
    create_restore_script
    
    # Step 12: Display summary
    display_summary
    
    print_success "All done! Your database is ready to use."
}

# Run main function
main "$@"
