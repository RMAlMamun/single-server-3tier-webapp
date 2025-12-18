# PostgreSQL Database Administration Guide

Complete PostgreSQL administration guide for BMI Health Tracker including backup strategies, restoration procedures, remote GUI access, and high availability configuration.

---

## Table of Contents

1. [Database Overview](#1-database-overview)
2. [Backup Strategies](#2-backup-strategies)
3. [Automated Backup with Cron Jobs](#3-automated-backup-with-cron-jobs)
4. [Backup Restoration](#4-backup-restoration)
5. [Remote GUI Access (pgAdmin)](#5-remote-gui-access-pgadmin)
6. [High Availability Configuration](#6-high-availability-configuration)
7. [Monitoring and Maintenance](#7-monitoring-and-maintenance)
8. [Security Hardening](#8-security-hardening)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Database Overview

### 1.1 Current Database Configuration

**Database Details:**
- **Database Name:** `bmi_tracker`
- **User:** `bmi_user`
- **PostgreSQL Version:** 12+
- **Server:** AWS EC2 Ubuntu 22.04 LTS
- **Port:** 5432 (localhost only)
- **Connection Pool:** Max 20 connections

**Database Schema:**
```sql
-- Main table
CREATE TABLE measurements (
    id SERIAL PRIMARY KEY,
    weight_kg DECIMAL(5,2) NOT NULL,
    height_cm DECIMAL(5,2) NOT NULL,
    age INTEGER NOT NULL,
    sex VARCHAR(10) NOT NULL,
    activity_level VARCHAR(20) NOT NULL,
    bmi DECIMAL(5,2) NOT NULL,
    bmr DECIMAL(7,2) NOT NULL,
    daily_calories DECIMAL(7,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    measurement_date DATE NOT NULL DEFAULT CURRENT_DATE
);

-- Indexes
CREATE INDEX idx_created_at ON measurements(created_at);
CREATE INDEX idx_measurement_date ON measurements(measurement_date);
```

### 1.2 Database Size Estimation

```bash
# Check database size
sudo -u postgres psql -c "SELECT pg_size_pretty(pg_database_size('bmi_tracker'));"

# Check table size
sudo -u postgres psql -d bmi_tracker -c "SELECT pg_size_pretty(pg_total_relation_size('measurements'));"

# Check row count
sudo -u postgres psql -d bmi_tracker -c "SELECT COUNT(*) FROM measurements;"
```

---

## 2. Backup Strategies

### 2.1 Logical Backup (pg_dump)

**Advantages:**
- Human-readable SQL format
- Portable across PostgreSQL versions
- Selective backup (specific tables)
- Small file size with compression

**Best for:** Development, migrations, point-in-time snapshots

#### Full Database Backup

```bash
# Basic backup
sudo -u postgres pg_dump bmi_tracker > /backup/bmi_tracker_$(date +%Y%m%d).sql

# Compressed backup (recommended)
sudo -u postgres pg_dump bmi_tracker | gzip > /backup/bmi_tracker_$(date +%Y%m%d).sql.gz

# Custom format (faster restore, parallel)
sudo -u postgres pg_dump -Fc bmi_tracker > /backup/bmi_tracker_$(date +%Y%m%d).dump
```

#### Backup with Connection Details

```bash
# If using password authentication
export PGPASSWORD='your_password'
pg_dump -h localhost -U bmi_user -d bmi_tracker | gzip > /backup/bmi_tracker_$(date +%Y%m%d).sql.gz
unset PGPASSWORD
```

#### Schema-Only Backup

```bash
# Backup structure without data
sudo -u postgres pg_dump --schema-only bmi_tracker > /backup/schema_$(date +%Y%m%d).sql
```

#### Data-Only Backup

```bash
# Backup data without structure
sudo -u postgres pg_dump --data-only bmi_tracker > /backup/data_$(date +%Y%m%d).sql
```

#### Specific Table Backup

```bash
# Backup only measurements table
sudo -u postgres pg_dump -t measurements bmi_tracker | gzip > /backup/measurements_$(date +%Y%m%d).sql.gz
```

### 2.2 Physical Backup (pg_basebackup)

**Advantages:**
- Faster backup and restore
- Suitable for large databases
- Required for Point-In-Time Recovery (PITR)
- Foundation for replication

**Best for:** Production, disaster recovery, high availability

```bash
# Stop all write operations (optional but recommended)
# Create base backup
sudo -u postgres pg_basebackup -D /backup/base_backup_$(date +%Y%m%d) -Ft -z -P

# Options explained:
# -D: Output directory
# -Ft: Tar format
# -z: Compress with gzip
# -P: Show progress
```

### 2.3 Backup Best Practices

**Retention Policy:**
- Daily backups: Keep last 7 days
- Weekly backups: Keep last 4 weeks
- Monthly backups: Keep last 12 months

**Storage Locations:**
1. Local: `/var/backups/postgresql/` (fast access)
2. Remote: AWS S3 or separate server (disaster recovery)
3. Offsite: Another AWS region (geographical redundancy)

**Backup Verification:**
- Test restore monthly
- Check backup file integrity
- Monitor backup job status
- Verify backup file sizes

---

## 3. Automated Backup with Cron Jobs

### 3.1 Create Backup Directory

```bash
# Create backup directory
sudo mkdir -p /var/backups/postgresql/daily
sudo mkdir -p /var/backups/postgresql/weekly
sudo mkdir -p /var/backups/postgresql/monthly
sudo chown -R postgres:postgres /var/backups/postgresql
sudo chmod 700 /var/backups/postgresql
```

### 3.2 Backup Script

Create comprehensive backup script: `/usr/local/bin/backup_bmi_db.sh`

```bash
#!/bin/bash

# BMI Tracker Database Backup Script
# Description: Automated PostgreSQL backup with rotation and verification

set -e  # Exit on error

# Configuration
DB_NAME="bmi_tracker"
DB_USER="bmi_user"
BACKUP_DIR="/var/backups/postgresql"
DAILY_DIR="$BACKUP_DIR/daily"
WEEKLY_DIR="$BACKUP_DIR/weekly"
MONTHLY_DIR="$BACKUP_DIR/monthly"
LOG_FILE="/var/log/postgresql/backup.log"
DATE=$(date +%Y%m%d_%H%M%S)
DAY_OF_WEEK=$(date +%u)  # 1=Monday, 7=Sunday
DAY_OF_MONTH=$(date +%d)
RETENTION_DAILY=7
RETENTION_WEEKLY=4
RETENTION_MONTHLY=12

# S3 Configuration (optional - for remote backup)
S3_BUCKET="s3://your-backup-bucket/bmi-tracker"
AWS_REGION="us-east-1"

# Email notification (optional)
ADMIN_EMAIL="admin@example.com"

# Functions
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

send_notification() {
    local status=$1
    local message=$2
    
    # Send email (requires mailutils)
    if command -v mail &> /dev/null; then
        echo "$message" | mail -s "BMI DB Backup: $status" "$ADMIN_EMAIL"
    fi
    
    # Send to syslog
    logger -t bmi_db_backup "$status: $message"
}

check_disk_space() {
    local available=$(df -BG "$BACKUP_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available" -lt 5 ]; then
        log_message "WARNING: Low disk space ($available GB available)"
        return 1
    fi
    return 0
}

create_backup() {
    local backup_file=$1
    local backup_type=$2
    
    log_message "Starting $backup_type backup to $backup_file"
    
    # Create compressed backup
    if sudo -u postgres pg_dump -Fc "$DB_NAME" > "$backup_file"; then
        log_message "Backup created successfully: $backup_file"
        
        # Verify backup
        local size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file")
        if [ "$size" -gt 1000 ]; then
            log_message "Backup verification passed (Size: $size bytes)"
            
            # Calculate checksum
            local checksum=$(sha256sum "$backup_file" | awk '{print $1}')
            echo "$checksum" > "$backup_file.sha256"
            log_message "Checksum: $checksum"
            
            return 0
        else
            log_message "ERROR: Backup file too small, possible corruption"
            return 1
        fi
    else
        log_message "ERROR: Backup failed"
        return 1
    fi
}

upload_to_s3() {
    local file=$1
    
    if command -v aws &> /dev/null && [ -n "$S3_BUCKET" ]; then
        log_message "Uploading to S3: $S3_BUCKET"
        if aws s3 cp "$file" "$S3_BUCKET/$(basename $file)" --region "$AWS_REGION"; then
            log_message "S3 upload successful"
            # Upload checksum too
            aws s3 cp "$file.sha256" "$S3_BUCKET/$(basename $file).sha256" --region "$AWS_REGION"
        else
            log_message "WARNING: S3 upload failed"
        fi
    fi
}

cleanup_old_backups() {
    local dir=$1
    local retention=$2
    
    log_message "Cleaning up old backups in $dir (keeping last $retention)"
    
    # Remove old backup files
    find "$dir" -name "*.dump" -type f -mtime +"$retention" -delete
    find "$dir" -name "*.sha256" -type f -mtime +"$retention" -delete
    
    local removed=$(find "$dir" -name "*.dump" -type f -mtime +"$retention" | wc -l)
    log_message "Removed $removed old backup(s)"
}

# Main execution
main() {
    log_message "========== Backup Process Started =========="
    
    # Check prerequisites
    if ! check_disk_space; then
        send_notification "FAILED" "Insufficient disk space for backup"
        exit 1
    fi
    
    # Daily backup (always)
    DAILY_BACKUP="$DAILY_DIR/bmi_tracker_daily_$DATE.dump"
    if create_backup "$DAILY_BACKUP" "daily"; then
        upload_to_s3 "$DAILY_BACKUP"
        cleanup_old_backups "$DAILY_DIR" "$RETENTION_DAILY"
        
        # Weekly backup (every Sunday)
        if [ "$DAY_OF_WEEK" -eq 7 ]; then
            WEEKLY_BACKUP="$WEEKLY_DIR/bmi_tracker_weekly_$DATE.dump"
            cp "$DAILY_BACKUP" "$WEEKLY_BACKUP"
            cp "$DAILY_BACKUP.sha256" "$WEEKLY_BACKUP.sha256"
            log_message "Weekly backup created"
            cleanup_old_backups "$WEEKLY_DIR" $((RETENTION_WEEKLY * 7))
        fi
        
        # Monthly backup (first day of month)
        if [ "$DAY_OF_MONTH" -eq "01" ]; then
            MONTHLY_BACKUP="$MONTHLY_DIR/bmi_tracker_monthly_$DATE.dump"
            cp "$DAILY_BACKUP" "$MONTHLY_BACKUP"
            cp "$DAILY_BACKUP.sha256" "$MONTHLY_BACKUP.sha256"
            log_message "Monthly backup created"
            cleanup_old_backups "$MONTHLY_DIR" $((RETENTION_MONTHLY * 30))
        fi
        
        log_message "========== Backup Process Completed Successfully =========="
        send_notification "SUCCESS" "Database backup completed successfully"
        exit 0
    else
        log_message "========== Backup Process Failed =========="
        send_notification "FAILED" "Database backup failed - check logs"
        exit 1
    fi
}

# Run main function
main
```

Make script executable:

```bash
sudo chmod +x /usr/local/bin/backup_bmi_db.sh
sudo chown postgres:postgres /usr/local/bin/backup_bmi_db.sh
```

### 3.3 Configure Cron Job

```bash
# Edit postgres user crontab
sudo crontab -e -u postgres

# Add daily backup at 2:00 AM
0 2 * * * /usr/local/bin/backup_bmi_db.sh >> /var/log/postgresql/backup.log 2>&1

# Alternative schedules:

# Every 6 hours
0 */6 * * * /usr/local/bin/backup_bmi_db.sh >> /var/log/postgresql/backup.log 2>&1

# Every day at 2:00 AM and 2:00 PM
0 2,14 * * * /usr/local/bin/backup_bmi_db.sh >> /var/log/postgresql/backup.log 2>&1

# Every Sunday at 3:00 AM (weekly backup)
0 3 * * 0 /usr/local/bin/backup_bmi_db.sh >> /var/log/postgresql/backup.log 2>&1
```

### 3.4 Create Log File

```bash
# Create log directory
sudo mkdir -p /var/log/postgresql
sudo touch /var/log/postgresql/backup.log
sudo chown postgres:postgres /var/log/postgresql/backup.log
sudo chmod 640 /var/log/postgresql/backup.log
```

### 3.5 Test Backup Script

```bash
# Test manual execution
sudo -u postgres /usr/local/bin/backup_bmi_db.sh

# Verify backup was created
ls -lh /var/backups/postgresql/daily/

# Check logs
tail -f /var/log/postgresql/backup.log
```

### 3.6 Backup Monitoring Script

Create monitoring script: `/usr/local/bin/check_backup_status.sh`

```bash
#!/bin/bash

# Check if backup ran successfully in last 24 hours
BACKUP_DIR="/var/backups/postgresql/daily"
LAST_BACKUP=$(find "$BACKUP_DIR" -name "*.dump" -type f -mtime -1 | head -1)

if [ -n "$LAST_BACKUP" ]; then
    echo "[OK] Recent backup found: $LAST_BACKUP"
    ls -lh "$LAST_BACKUP"
    exit 0
else
    echo "[FAIL] No backup found in last 24 hours"
    exit 1
fi
```

---

## 4. Backup Restoration

### 4.1 Pre-Restoration Checklist

**Before restoring:**
1. ✓ Stop application services
2. ✓ Verify backup file integrity
3. ✓ Ensure sufficient disk space
4. ✓ Create current database backup
5. ✓ Document current database state

### 4.2 Restore from Logical Backup

#### Restore Full Database (SQL Format)

```bash
# Stop backend application
pm2 stop bmi-backend

# Option 1: Drop and recreate database (DESTRUCTIVE)
sudo -u postgres psql -c "DROP DATABASE IF EXISTS bmi_tracker;"
sudo -u postgres psql -c "CREATE DATABASE bmi_tracker OWNER bmi_user;"

# Restore from plain SQL backup
gunzip < /var/backups/postgresql/daily/bmi_tracker_20251216.sql.gz | sudo -u postgres psql bmi_tracker

# Option 2: Restore to existing database (appends data)
gunzip < /var/backups/postgresql/daily/bmi_tracker_20251216.sql.gz | sudo -u postgres psql bmi_tracker

# Verify restoration
sudo -u postgres psql -d bmi_tracker -c "SELECT COUNT(*) FROM measurements;"

# Restart application
pm2 restart bmi-backend
```

#### Restore from Custom Format

```bash
# Stop backend
pm2 stop bmi-backend

# Drop and recreate database
sudo -u postgres psql -c "DROP DATABASE IF EXISTS bmi_tracker;"
sudo -u postgres psql -c "CREATE DATABASE bmi_tracker OWNER bmi_user;"

# Restore using pg_restore (supports parallel jobs)
sudo -u postgres pg_restore -d bmi_tracker -j 4 /var/backups/postgresql/daily/bmi_tracker_20251216.dump

# Options:
# -j 4: Use 4 parallel jobs (faster)
# -c: Clean (drop) database objects before recreating
# -C: Create database before restoring
# --if-exists: Use DROP IF EXISTS

# Restart application
pm2 restart bmi-backend
```

#### Restore Specific Table

```bash
# Restore only measurements table
sudo -u postgres pg_restore -d bmi_tracker -t measurements /backup/bmi_tracker_20251216.dump
```

### 4.3 Restore to Different Database Name

```bash
# Useful for testing or migration

# Create new database
sudo -u postgres psql -c "CREATE DATABASE bmi_tracker_test OWNER bmi_user;"

# Restore to test database
sudo -u postgres pg_restore -d bmi_tracker_test /backup/bmi_tracker_20251216.dump

# Compare data
sudo -u postgres psql -d bmi_tracker_test -c "SELECT COUNT(*) FROM measurements;"
```

### 4.4 Point-in-Time Recovery (PITR)

**Requirements:** WAL archiving enabled

```bash
# Enable WAL archiving in postgresql.conf
sudo nano /etc/postgresql/12/main/postgresql.conf

# Add/modify:
wal_level = replica
archive_mode = on
archive_command = 'test ! -f /var/lib/postgresql/12/archive/%f && cp %p /var/lib/postgresql/12/archive/%f'
archive_timeout = 300  # 5 minutes

# Restart PostgreSQL
sudo systemctl restart postgresql

# Create archive directory
sudo mkdir -p /var/lib/postgresql/12/archive
sudo chown postgres:postgres /var/lib/postgresql/12/archive
sudo chmod 700 /var/lib/postgresql/12/archive
```

**Restore to specific point in time:**

```bash
# Stop PostgreSQL
sudo systemctl stop postgresql

# Remove current data directory
sudo rm -rf /var/lib/postgresql/12/main/*

# Extract base backup
sudo -u postgres tar -xzf /backup/base_backup_20251216.tar.gz -C /var/lib/postgresql/12/main/

# Create recovery.conf
sudo -u postgres nano /var/lib/postgresql/12/main/recovery.conf

# Add:
restore_command = 'cp /var/lib/postgresql/12/archive/%f %p'
recovery_target_time = '2025-12-16 14:30:00'
recovery_target_action = 'promote'

# Start PostgreSQL
sudo systemctl start postgresql
```

### 4.5 Verification After Restore

```bash
# Connect to database
sudo -u postgres psql -d bmi_tracker

-- Check table structure
\dt

-- Check row counts
SELECT COUNT(*) FROM measurements;

-- Check recent data
SELECT * FROM measurements ORDER BY created_at DESC LIMIT 10;

-- Verify indexes
SELECT * FROM pg_indexes WHERE tablename = 'measurements';

-- Check database size
SELECT pg_size_pretty(pg_database_size('bmi_tracker'));

-- Exit
\q
```

### 4.6 Emergency Restoration Script

Create quick restore script: `/usr/local/bin/restore_bmi_db.sh`

```bash
#!/bin/bash

# Emergency Database Restoration Script

if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup_file>"
    echo "Example: $0 /var/backups/postgresql/daily/bmi_tracker_20251216.dump"
    exit 1
fi

BACKUP_FILE=$1

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "WARNING: This will replace the current database!"
echo "Backup file: $BACKUP_FILE"
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Restoration cancelled"
    exit 0
fi

# Stop application
echo "Stopping application..."
pm2 stop bmi-backend

# Create safety backup
echo "Creating safety backup of current database..."
sudo -u postgres pg_dump -Fc bmi_tracker > /tmp/bmi_tracker_safety_$(date +%Y%m%d_%H%M%S).dump

# Drop and recreate database
echo "Dropping existing database..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS bmi_tracker;"
sudo -u postgres psql -c "CREATE DATABASE bmi_tracker OWNER bmi_user;"

# Restore
echo "Restoring database..."
sudo -u postgres pg_restore -d bmi_tracker -j 4 "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "[OK] Database restored successfully"
    
    # Verify
    echo "Verifying data..."
    sudo -u postgres psql -d bmi_tracker -c "SELECT COUNT(*) FROM measurements;"
    
    # Restart application
    echo "Restarting application..."
    pm2 restart bmi-backend
    
    echo "Restoration completed successfully!"
else
    echo "[FAIL] Restoration failed - check logs"
    exit 1
fi
```

Make executable:
```bash
sudo chmod +x /usr/local/bin/restore_bmi_db.sh
```

---

## 5. Remote GUI Access (pgAdmin)

### 5.1 Install pgAdmin on EC2 Server

```bash
# Add pgAdmin repository
curl -fsS https://www.pgadmin.org/static/packages_pgadmin_org.pub | sudo gpg --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg

sudo sh -c 'echo "deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" > /etc/apt/sources.list.d/pgadmin4.list'

# Update and install
sudo apt update
sudo apt install pgadmin4-web -y

# Configure Apache2 to run on port 8080 (to avoid conflict with Nginx on port 80)
sudo nano /etc/apache2/ports.conf

# Change:
# Listen 80
# To:
Listen 8080

# Also update the default site configuration
sudo nano /etc/apache2/sites-available/000-default.conf

# Change:
# <VirtualHost *:80>
# To:
<VirtualHost *:8080>

# Setup pgAdmin (creates web server configuration)
sudo /usr/pgadmin4/bin/setup-web.sh

# During setup:
# - Email address (admin login): your_email@example.com
# - Password: (set a strong password)
# - Configure Apache? Type "Y" (it will now use port 8080)

# Start Apache2
sudo systemctl start apache2
sudo systemctl enable apache2

# Verify pgAdmin is accessible on port 8080
curl http://127.0.0.1:8080/pgadmin4/
# Should return pgAdmin HTML (not your BMI tracker)
```

### 5.2 Configure Nginx Proxy for pgAdmin

Create separate Nginx site configuration for pgAdmin (does not interfere with main BMI tracker site):

```bash
# Create new site configuration
sudo nano /etc/nginx/sites-available/pgAdmin
```

Add the following configuration:

```nginx
server {
    listen 5050;
    server_name YOUR_DOMAIN_OR_IP;

    # pgAdmin web interface
    location / {
        proxy_pass http://127.0.0.1:8080/pgadmin4/;
        proxy_set_header Host $host:$server_port;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Script-Name /pgadmin4;
        
        # WebSocket support (for query tool)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts for long-running queries
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 600;
        
        # Authentication (optional - recommended)
        auth_basic "Database Administration";
        auth_basic_user_file /etc/nginx/.htpasswd_pgadmin;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
}
```

Enable the site and configure authentication:

```bash
# Install apache2-utils for htpasswd
sudo apt install apache2-utils -y

# Create password file
sudo htpasswd -c /etc/nginx/.htpasswd_pgadmin dbadmin
# Enter password when prompted

# Secure the file
sudo chmod 640 /etc/nginx/.htpasswd_pgadmin
sudo chown www-data:www-data /etc/nginx/.htpasswd_pgadmin

# Enable the site
sudo ln -s /etc/nginx/sites-available/pgAdmin /etc/nginx/sites-enabled/

# Open firewall port for pgAdmin
sudo ufw allow 5050/tcp

# Test and reload Nginx
sudo nginx -t
sudo systemctl reload nginx
```

### 5.3 Access pgAdmin Remotely

**Access URL:** `http://YOUR_EC2_PUBLIC_IP:5050`

**Login:**
- Email: (the one you provided during setup)
- Password: (the one you set during setup)

### 5.4 Add Database Connection in pgAdmin

**Step-by-step:**

1. Open pgAdmin in browser
2. Right-click "Servers" → "Create" → "Server"
3. **General Tab:**
   - Name: `BMI Tracker DB`
4. **Connection Tab:**
   - Host: `localhost` (or `127.0.0.1`)
   - Port: `5432`
   - Maintenance database: `bmidb`
   - Username: `bmi_user`
   - Password: `your_password`
   - Save password: ✓ (checked)
5. Click "Save"

### 5.5 SSH Tunnel Method (More Secure)

**Instead of exposing pgAdmin, use SSH tunnel:**

```bash
# From your local machine
ssh -L 5050:localhost:5050 ubuntu@YOUR_EC2_PUBLIC_IP

# Access pgAdmin locally at:
# http://localhost:5050
```

**For PostgreSQL direct access:**

```bash
# From your local machine
ssh -L 5432:localhost:5432 ubuntu@YOUR_EC2_PUBLIC_IP

# Connect using local pgAdmin or any PostgreSQL client:
# Host: localhost
# Port: 5432
# Database: bmi_tracker
# User: bmi_user
```

### 5.6 Cloud-Based pgAdmin (Alternative)

**Use pgAdmin desktop application on your local machine:**

1. Download pgAdmin from: https://www.pgadmin.org/download/
2. Install on your local Windows/Mac/Linux
3. Create SSH tunnel as above
4. Add server connection:
   - Host: `localhost`
   - Port: `5432`
   - Database: `bmi_tracker`

**Advantages:**
- No web server required
- More secure (no internet exposure)
- Better performance
- Local tool, familiar interface

### 5.7 Security Considerations for Remote Access

**If you must expose pgAdmin publicly:**

```bash
# 1. Use HTTPS only
sudo certbot --nginx -d pgadmin.your-domain.com

# 2. IP Whitelisting in Nginx
location /pgadmin/ {
    # Only allow specific IPs
    allow YOUR_OFFICE_IP;
    allow YOUR_HOME_IP;
    deny all;
    
    proxy_pass http://127.0.0.1:5050/;
    # ... rest of configuration
}

# 3. Use strong authentication
auth_basic "Database Administration";
auth_basic_user_file /etc/nginx/.htpasswd_pgadmin;

# 4. Firewall rules
sudo ufw allow from YOUR_IP to any port 80
sudo ufw allow from YOUR_IP to any port 443

# 5. Fail2ban for pgAdmin
sudo nano /etc/fail2ban/jail.local

[pgadmin]
enabled = true
port = http,https
filter = pgadmin
logpath = /var/log/nginx/access.log
maxretry = 3
bantime = 3600
```

### 5.8 pgAdmin Configuration File

```bash
# Edit pgAdmin config
sudo nano /usr/pgadmin4/web/config_local.py

# Add security settings:
SESSION_COOKIE_SECURE = True
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = 'Lax'
CSRF_COOKIE_SECURE = True

# Set session timeout (in seconds)
SESSION_EXPIRATION_TIME = 3600  # 1 hour

# Master password for saving server passwords
MASTER_PASSWORD_REQUIRED = True
```

---

## 6. High Availability Configuration

### 6.1 High Availability Architecture Options

#### Option 1: Streaming Replication (Recommended for Production)

**Architecture:**
```
┌─────────────────────────┐
│   Primary Database      │
│   (Master - Read/Write) │
│   EC2 Instance 1        │
└──────────┬──────────────┘
           │
           │ Streaming
           │ Replication
           ▼
┌─────────────────────────┐
│   Standby Database      │
│   (Replica - Read Only) │
│   EC2 Instance 2        │
└─────────────────────────┘
```

**Benefits:**
- Automatic failover capability
- Zero data loss (synchronous replication)
- Read scalability (read from replicas)
- Disaster recovery

#### Option 2: Connection Pooling (PgBouncer)

**Benefits:**
- Better connection management
- Reduced connection overhead
- Improved performance under load
- Connection reuse

#### Option 3: Load Balancing (HAProxy + Multiple Replicas)

**Benefits:**
- Distribute read traffic
- Higher throughput
- Better resource utilization

### 6.2 Setup Streaming Replication

#### On Primary Server (Master)

**Step 1: Configure PostgreSQL for Replication**

```bash
# Edit postgresql.conf
sudo nano /etc/postgresql/12/main/postgresql.conf

# Add/modify:
listen_addresses = '*'  # Or specific IPs
wal_level = replica
max_wal_senders = 3
max_replication_slots = 3
hot_standby = on
archive_mode = on
archive_command = 'test ! -f /var/lib/postgresql/12/archive/%f && cp %p /var/lib/postgresql/12/archive/%f'
```

**Step 2: Create Replication User**

```bash
sudo -u postgres psql

-- Create replication user
CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'strong_replica_password';

-- Exit
\q
```

**Step 3: Configure pg_hba.conf**

```bash
sudo nano /etc/postgresql/12/main/pg_hba.conf

# Add replication access (replace STANDBY_IP with actual IP)
host    replication     replicator      STANDBY_SERVER_IP/32         md5
host    replication     replicator      10.0.0.0/16                  md5
```

**Step 4: Restart PostgreSQL**

```bash
sudo systemctl restart postgresql
```

**Step 5: Create Replication Slot**

```bash
sudo -u postgres psql

-- Create replication slot
SELECT * FROM pg_create_physical_replication_slot('standby_slot');

-- Verify
SELECT * FROM pg_replication_slots;

\q
```

#### On Standby Server (Replica)

**Step 1: Stop PostgreSQL**

```bash
sudo systemctl stop postgresql
```

**Step 2: Clear Data Directory**

```bash
# Backup existing data (if any)
sudo mv /var/lib/postgresql/12/main /var/lib/postgresql/12/main.backup

# Create new empty directory
sudo mkdir -p /var/lib/postgresql/12/main
sudo chown postgres:postgres /var/lib/postgresql/12/main
sudo chmod 700 /var/lib/postgresql/12/main
```

**Step 3: Create Base Backup from Primary**

```bash
# On standby server, run as postgres user
sudo -u postgres pg_basebackup -h PRIMARY_SERVER_IP -D /var/lib/postgresql/12/main -U replicator -P -v -R -X stream -C -S standby_slot

# Options explained:
# -h: Primary server hostname/IP
# -D: Data directory
# -U: Replication user
# -P: Show progress
# -v: Verbose
# -R: Create standby.signal and write recovery settings
# -X stream: Stream WAL while backing up
# -C: Create replication slot
# -S: Replication slot name
```

**Step 4: Configure Standby**

```bash
# Edit postgresql.auto.conf (created by pg_basebackup with -R option)
sudo -u postgres nano /var/lib/postgresql/12/main/postgresql.auto.conf

# Verify it contains:
primary_conninfo = 'host=PRIMARY_SERVER_IP port=5432 user=replicator password=strong_replica_password'
primary_slot_name = 'standby_slot'

# Create standby.signal file (if not created automatically)
sudo -u postgres touch /var/lib/postgresql/12/main/standby.signal
```

**Step 5: Start Standby PostgreSQL**

```bash
sudo systemctl start postgresql
```

**Step 6: Verify Replication**

```bash
# On primary server
sudo -u postgres psql

-- Check replication status
SELECT * FROM pg_stat_replication;

-- Should show:
-- application_name | state     | sync_state
-- standby_slot     | streaming | async

\q

# On standby server
sudo -u postgres psql

-- Check recovery status
SELECT pg_is_in_recovery();

-- Should return: t (true)

-- Check replication lag
SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();

\q
```

### 6.3 Automatic Failover with Patroni

**Patroni** provides automatic failover and high availability.

#### Install Patroni

```bash
# On both primary and standby

# Install dependencies
sudo apt install python3-pip python3-dev libpq-dev -y

# Install Patroni
sudo pip3 install patroni[etcd] psycopg2-binary

# Install etcd (distributed configuration)
sudo apt install etcd -y
```

#### Configure Patroni

Create `/etc/patroni/patroni.yml` on primary:

```yaml
scope: bmi_cluster
namespace: /db/
name: primary_node

restapi:
  listen: 0.0.0.0:8008
  connect_address: PRIMARY_IP:8008

etcd:
  host: PRIMARY_IP:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 100
        shared_buffers: 256MB

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 0.0.0.0/0 md5
    - host all all 0.0.0.0/0 md5

postgresql:
  listen: 0.0.0.0:5432
  connect_address: PRIMARY_IP:5432
  data_dir: /var/lib/postgresql/12/main
  bin_dir: /usr/lib/postgresql/12/bin
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: strong_replica_password
    superuser:
      username: postgres
      password: postgres_password

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
```

Similar configuration for standby with different `name` and IPs.

#### Start Patroni

```bash
# Create systemd service
sudo nano /etc/systemd/system/patroni.service

[Unit]
Description=Patroni (PostgreSQL HA)
After=syslog.target network.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni/patroni.yml
KillMode=process
TimeoutSec=30
Restart=no

[Install]
WantedBy=multi-user.target

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable patroni
sudo systemctl start patroni

# Check status
sudo systemctl status patroni
```

### 6.4 Connection Pooling with PgBouncer

#### Install PgBouncer

```bash
sudo apt install pgbouncer -y
```

#### Configure PgBouncer

```bash
# Edit configuration
sudo nano /etc/pgbouncer/pgbouncer.ini

[databases]
bmi_tracker = host=127.0.0.1 port=5432 dbname=bmi_tracker

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
admin_users = postgres
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
min_pool_size = 10
reserve_pool_size = 5
reserve_pool_timeout = 5
max_db_connections = 50
max_user_connections = 50
server_lifetime = 3600
server_idle_timeout = 600
```

#### Create User List

```bash
# Create userlist
sudo nano /etc/pgbouncer/userlist.txt

# Add (format: "username" "md5_hashed_password")
"bmi_user" "md5PASSWORD_HASH_HERE"

# Generate password hash:
echo -n "passwordusername" | md5sum
# Use output in userlist.txt as: md5<hash>
```

#### Update Backend Connection

```bash
# In backend/.env, change:
DB_HOST=localhost
DB_PORT=6432  # PgBouncer port instead of 5432
```

#### Start PgBouncer

```bash
sudo systemctl enable pgbouncer
sudo systemctl start pgbouncer
sudo systemctl status pgbouncer

# Test connection
psql -h localhost -p 6432 -U bmi_user -d bmi_tracker
```

### 6.5 Load Balancing with HAProxy

**For read scaling across multiple replicas:**

```bash
# Install HAProxy
sudo apt install haproxy -y

# Configure
sudo nano /etc/haproxy/haproxy.cfg

global
    maxconn 1000

defaults
    mode tcp
    timeout connect 5s
    timeout client 50s
    timeout server 50s

# Write traffic to primary
listen postgres_write
    bind *:5433
    option pgsql-check user haproxy
    server primary PRIMARY_IP:5432 check

# Read traffic distributed across replicas
listen postgres_read
    bind *:5434
    balance roundrobin
    option pgsql-check user haproxy
    server primary PRIMARY_IP:5432 check
    server replica1 REPLICA1_IP:5432 check
    server replica2 REPLICA2_IP:5432 check

# Restart HAProxy
sudo systemctl restart haproxy
```

### 6.6 Monitoring Replication Health

```bash
# Create monitoring script
sudo nano /usr/local/bin/check_replication.sh

#!/bin/bash

# Check replication lag
LAG=$(sudo -u postgres psql -At -c "SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()))::INT;")

if [ "$LAG" -gt 60 ]; then
    echo "WARNING: Replication lag is $LAG seconds"
    # Send alert
else
    echo "OK: Replication lag is $LAG seconds"
fi

# Check replication status
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"
```

---

## 7. Monitoring and Maintenance

### 7.1 Database Performance Monitoring

#### Install pg_stat_statements

```bash
# Enable extension
sudo -u postgres psql -d bmi_tracker

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

\q

# Configure PostgreSQL
sudo nano /etc/postgresql/12/main/postgresql.conf

# Add:
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.max = 10000
pg_stat_statements.track = all

# Restart
sudo systemctl restart postgresql
```

#### Query Performance Analysis

```sql
-- Top 10 slowest queries
SELECT 
    substring(query, 1, 50) AS short_query,
    round(total_exec_time::numeric, 2) AS total_time,
    calls,
    round(mean_exec_time::numeric, 2) AS mean,
    round((100 * total_exec_time / sum(total_exec_time::numeric) OVER ())::numeric, 2) AS percentage_cpu
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

-- Most called queries
SELECT 
    substring(query, 1, 50) AS short_query,
    calls,
    round(total_exec_time::numeric, 2) AS total_time,
    round(mean_exec_time::numeric, 2) AS mean
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 10;

-- Reset statistics
SELECT pg_stat_statements_reset();
```

### 7.2 Database Size Monitoring

```bash
# Create monitoring script
sudo nano /usr/local/bin/monitor_db_size.sh

#!/bin/bash

echo "=== Database Size Report ==="
sudo -u postgres psql -d bmi_tracker -c "
SELECT 
    pg_size_pretty(pg_database_size('bmi_tracker')) AS database_size,
    pg_size_pretty(pg_total_relation_size('measurements')) AS table_size,
    (SELECT COUNT(*) FROM measurements) AS row_count;
"

# Make executable
sudo chmod +x /usr/local/bin/monitor_db_size.sh
```

### 7.3 Vacuum and Analyze

**Automatic Vacuuming (Enabled by Default):**

```bash
# Check autovacuum settings
sudo -u postgres psql -c "SHOW autovacuum;"

# Configure autovacuum
sudo nano /etc/postgresql/12/main/postgresql.conf

autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = 1min
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50
```

**Manual Vacuum:**

```bash
# Vacuum single table
sudo -u postgres psql -d bmi_tracker -c "VACUUM ANALYZE measurements;"

# Vacuum entire database
sudo -u postgres psql -d bmi_tracker -c "VACUUM ANALYZE;"

# Full vacuum (locks table, reclaims more space)
sudo -u postgres psql -d bmi_tracker -c "VACUUM FULL measurements;"
```

**Scheduled Vacuum (Cron):**

```bash
# Add to crontab
sudo crontab -e -u postgres

# Weekly full vacuum (Sunday 4 AM)
0 4 * * 0 psql -d bmi_tracker -c "VACUUM ANALYZE;" >> /var/log/postgresql/vacuum.log 2>&1
```

### 7.4 Index Maintenance

```sql
-- Check index usage
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan;

-- Find unused indexes
SELECT 
    schemaname,
    tablename,
    indexname
FROM pg_stat_user_indexes
WHERE idx_scan = 0 
AND indexname NOT LIKE '%_pkey'
AND schemaname = 'public';

-- Reindex (if needed)
REINDEX TABLE measurements;
REINDEX DATABASE bmi_tracker;
```

### 7.5 Connection Monitoring

```sql
-- Current connections
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    state,
    query_start,
    substring(query, 1, 50) as query
FROM pg_stat_activity
WHERE datname = 'bmi_tracker';

-- Kill idle connections
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE datname = 'bmi_tracker' 
AND state = 'idle' 
AND state_change < current_timestamp - INTERVAL '1 hour';
```

### 7.6 Log Analysis

```bash
# View PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-12-main.log

# Search for errors
sudo grep "ERROR" /var/log/postgresql/postgresql-12-main.log

# Slow query log
sudo nano /etc/postgresql/12/main/postgresql.conf

# Enable slow query logging
log_min_duration_statement = 1000  # Log queries taking > 1 second

# Restart
sudo systemctl restart postgresql
```

### 7.7 Comprehensive Monitoring Script

```bash
sudo nano /usr/local/bin/db_health_check.sh

#!/bin/bash

echo "========================================="
echo "BMI Tracker Database Health Check"
echo "Date: $(date)"
echo "========================================="

# Database is running
if sudo systemctl is-active --quiet postgresql; then
    echo "[OK] PostgreSQL is running"
else
    echo "[FAIL] PostgreSQL is not running"
    exit 1
fi

# Connection test
if sudo -u postgres psql -d bmi_tracker -c "SELECT 1;" > /dev/null 2>&1; then
    echo "[OK] Database connection successful"
else
    echo "[FAIL] Cannot connect to database"
    exit 1
fi

# Database size
echo ""
echo "Database Size:"
sudo -u postgres psql -d bmi_tracker -At -c "SELECT pg_size_pretty(pg_database_size('bmi_tracker'));"

# Row count
echo ""
echo "Measurement Records:"
sudo -u postgres psql -d bmi_tracker -At -c "SELECT COUNT(*) FROM measurements;"

# Active connections
echo ""
echo "Active Connections:"
sudo -u postgres psql -At -c "SELECT COUNT(*) FROM pg_stat_activity WHERE datname = 'bmi_tracker';"

# Last backup
echo ""
echo "Last Backup:"
ls -lht /var/backups/postgresql/daily/ | head -2

# Disk space
echo ""
echo "Disk Space:"
df -h /var/backups/postgresql

echo ""
echo "========================================="
echo "Health check completed"
echo "========================================="

# Make executable
sudo chmod +x /usr/local/bin/db_health_check.sh
```

Run automatically:

```bash
# Add to crontab
sudo crontab -e

# Run health check daily at 9 AM
0 9 * * * /usr/local/bin/db_health_check.sh | mail -s "BMI DB Health Check" admin@example.com
```

---

## 8. Security Hardening

### 8.1 PostgreSQL Security Checklist

```bash
# 1. Disable remote root access
sudo nano /etc/postgresql/12/main/pg_hba.conf

# Change:
local   all             postgres                                peer

# 2. Restrict network access
host    all             all             127.0.0.1/32            md5
host    all             all             10.0.0.0/16             md5  # VPC only

# 3. Use strong passwords
sudo -u postgres psql

ALTER USER bmi_user WITH PASSWORD 'ComplexP@ssw0rd!2025';
ALTER USER postgres WITH PASSWORD 'AnotherStr0ng!Pass';

\q

# 4. Enable SSL (if needed for external access)
sudo nano /etc/postgresql/12/main/postgresql.conf

ssl = on
ssl_cert_file = '/etc/postgresql/12/main/server.crt'
ssl_key_file = '/etc/postgresql/12/main/server.key'

# 5. Set connection limits
sudo nano /etc/postgresql/12/main/postgresql.conf

max_connections = 100
superuser_reserved_connections = 3

# 6. Enable logging
log_connections = on
log_disconnections = on
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '

# Restart PostgreSQL
sudo systemctl restart postgresql
```

### 8.2 Firewall Rules

```bash
# PostgreSQL should NOT be exposed to internet
sudo ufw status

# Only allow from localhost
sudo ufw deny 5432
sudo ufw allow from 127.0.0.1 to any port 5432

# If using replication, allow from replica IPs only
sudo ufw allow from REPLICA_IP to any port 5432
```

### 8.3 Audit Logging

```bash
# Enable pgAudit extension
sudo apt install postgresql-12-pgaudit -y

# Configure
sudo nano /etc/postgresql/12/main/postgresql.conf

shared_preload_libraries = 'pgaudit'
pgaudit.log = 'write, ddl'
pgaudit.log_catalog = off

# Restart
sudo systemctl restart postgresql

# Enable in database
sudo -u postgres psql -d bmi_tracker

CREATE EXTENSION pgaudit;

\q
```

### 8.4 Backup Encryption

```bash
# Encrypt backups with GPG
sudo apt install gnupg -y

# Generate encryption key
gpg --gen-key

# Modify backup script to encrypt
pg_dump bmi_tracker | gzip | gpg --encrypt --recipient your@email.com > backup_$(date +%Y%m%d).sql.gz.gpg

# Decrypt for restore
gpg --decrypt backup_20251216.sql.gz.gpg | gunzip | psql bmi_tracker
```

---

## 9. Troubleshooting

### 9.1 Common Issues

#### Issue: Cannot Connect to Database

```bash
# Check if PostgreSQL is running
sudo systemctl status postgresql

# Check listening ports
sudo netstat -tlnp | grep 5432

# Check pg_hba.conf
sudo nano /etc/postgresql/12/main/pg_hba.conf

# Check logs
sudo tail -100 /var/log/postgresql/postgresql-12-main.log
```

#### Issue: Slow Query Performance

```sql
-- Analyze query plan
EXPLAIN ANALYZE SELECT * FROM measurements WHERE created_at > '2025-12-01';

-- Check for missing indexes
SELECT * FROM pg_stat_user_tables WHERE schemaname = 'public';

-- Add index if needed
CREATE INDEX idx_created_at ON measurements(created_at);
```

#### Issue: Database Growing Too Large

```bash
# Find largest tables
sudo -u postgres psql -d bmi_tracker

SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

# Archive old data
DELETE FROM measurements WHERE created_at < NOW() - INTERVAL '1 year';

# Vacuum to reclaim space
VACUUM FULL measurements;
```

#### Issue: Replication Lag

```bash
# On primary
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"

# On standby
sudo -u postgres psql -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();"

# Check network connectivity
ping REPLICA_IP
```

### 9.2 Emergency Recovery

#### Database Corruption

```bash
# Check for corruption
sudo -u postgres pg_checksums -D /var/lib/postgresql/12/main --check

# If corrupted, restore from backup
/usr/local/bin/restore_bmi_db.sh /var/backups/postgresql/daily/latest.dump
```

#### Lost Data Directory

```bash
# Restore from most recent backup
sudo -u postgres pg_basebackup -D /var/lib/postgresql/12/main -Fp -Xs -P
```

### 9.3 Performance Tuning

```bash
# Tune PostgreSQL for your EC2 instance
sudo nano /etc/postgresql/12/main/postgresql.conf

# For t3.medium (2 vCPU, 4GB RAM)
shared_buffers = 1GB
effective_cache_size = 3GB
maintenance_work_mem = 256MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 10MB
min_wal_size = 1GB
max_wal_size = 4GB

# Restart
sudo systemctl restart postgresql
```

---

## Quick Reference Commands

```bash
# Backup
sudo -u postgres pg_dump -Fc bmi_tracker > backup.dump

# Restore
sudo -u postgres pg_restore -d bmi_tracker backup.dump

# Check health
sudo systemctl status postgresql
sudo -u postgres psql -c "SELECT version();"

# View connections
sudo -u postgres psql -c "SELECT * FROM pg_stat_activity;"

# Database size
sudo -u postgres psql -c "SELECT pg_size_pretty(pg_database_size('bmi_tracker'));"

# Test connection
psql -h localhost -U bmi_user -d bmi_tracker -c "SELECT COUNT(*) FROM measurements;"
```

---

## Additional Resources

- PostgreSQL Official Documentation: https://www.postgresql.org/docs/
- pgAdmin Documentation: https://www.pgadmin.org/docs/
- Patroni Documentation: https://patroni.readthedocs.io/
- PgBouncer Documentation: https://www.pgbouncer.org/
- AWS RDS PostgreSQL: https://aws.amazon.com/rds/postgresql/

---

**Document Version:** 1.0  
**Last Updated:** December 16, 2025  
**Author:** BMI Health Tracker DevOps Team
