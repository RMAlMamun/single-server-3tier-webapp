# BMI & Health Tracker — Manual Deployment Guide

**Complete step-by-step deployment guide with verification commands**

This guide walks you through manually deploying the BMI & Health Tracker application on AWS EC2 Ubuntu. Each step includes verification commands to ensure everything is working correctly.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [AWS EC2 Setup](#step-1-aws-ec2-setup)
3. [Server Preparation](#step-2-server-preparation)
4. [Install Node.js via NVM](#step-3-install-nodejs-via-nvm)
5. [Install PostgreSQL](#step-4-install-postgresql)
6. [Install Nginx](#step-5-install-nginx)
7. [Install PM2](#step-6-install-pm2)
8. [Database Configuration](#step-7-database-configuration)
9. [Clone/Upload Project](#step-8-cloneupload-project)
10. [Backend Configuration](#step-9-backend-configuration)
11. [Deploy Backend](#step-10-deploy-backend)
12. [Deploy Frontend](#step-11-deploy-frontend)
13. [Configure PM2](#step-12-configure-pm2)
14. [Configure Nginx](#step-13-configure-nginx)
15. [Health Checks](#step-14-health-checks)
16. [SSL/HTTPS (Optional)](#step-15-ssl-https-optional)
17. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- ✅ AWS Account with EC2 access
- ✅ SSH client (Terminal, PuTTY, or similar)
- ✅ Basic Linux command knowledge
- ✅ Domain name (optional, for HTTPS)
- ✅ Project files ready (git repo or zip file)

---

## Step 1: AWS EC2 Setup

### 1.1 Launch EC2 Instance

1. **AWS Console** → EC2 Dashboard → **Launch Instance**
2. **Configuration:**
   - **Name**: `bmi-health-tracker-server`
   - **AMI**: Ubuntu Server 22.04 LTS
   - **Instance Type**: `t2.small` (minimum) or `t2.medium` (recommended)
   - **Key Pair**: Create/select your `.pem` key
   - **Storage**: 20 GB gp3

3. **Security Group Rules:**

| Type  | Protocol | Port | Source    | Description      |
|-------|----------|------|-----------|------------------|
| SSH   | TCP      | 22   | My IP     | SSH access       |
| HTTP  | TCP      | 80   | 0.0.0.0/0 | Web traffic      |
| HTTPS | TCP      | 443  | 0.0.0.0/0 | Secure traffic   |

4. **Launch** and wait for "Running" status

### 1.2 Connect to Server

```bash
# Set key permissions (first time only)
chmod 400 your-key.pem

# Connect
ssh -i your-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

**✅ Verify:**
```bash
whoami        # Should show: ubuntu
pwd           # Should show: /home/ubuntu
uname -a      # Should show Ubuntu info
```

---

## Step 2: Server Preparation

### 2.1 Update System

```bash
sudo apt update && sudo apt upgrade -y
```

**✅ Verify:**
```bash
sudo apt update
# Should show: All packages are up to date
```

### 2.2 Install Essential Tools

```bash
sudo apt install -y git curl wget build-essential ca-certificates gnupg
```

**✅ Verify:**
```bash
git --version          # Should show git version
curl --version         # Should show curl version
gcc --version          # Should show gcc version
```

---

## Step 3: Install Node.js via NVM

### 3.1 Install NVM

```bash
# Download and install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Load NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
```

**✅ Verify:**
```bash
command -v nvm        # Should show: nvm
nvm --version         # Should show: 0.39.7
```

### 3.2 Install Node.js LTS

```bash
# Install Node.js
nvm install --lts
nvm use --lts
nvm alias default lts/*
```

**✅ Verify:**
```bash
node -v               # Should show: v20.x.x or v22.x.x
npm -v                # Should show: 10.x.x or higher
which node            # Should show path with .nvm
```

---

## Step 4: Install PostgreSQL

### 4.1 Install PostgreSQL

```bash
sudo apt install -y postgresql postgresql-contrib
```

**✅ Verify:**
```bash
psql --version                    # Should show: psql (PostgreSQL) 14.x
sudo systemctl status postgresql  # Should show: active (running)
```

### 4.2 Enable PostgreSQL Service

```bash
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

**✅ Verify:**
```bash
sudo systemctl is-active postgresql    # Should show: active
sudo systemctl is-enabled postgresql   # Should show: enabled
```

---

## Step 5: Install Nginx

### 5.1 Install Nginx

```bash
sudo apt install -y nginx
```

**✅ Verify:**
```bash
nginx -v                         # Should show: nginx version
sudo systemctl status nginx      # Should show: active (running)
```

### 5.2 Enable Nginx Service

```bash
sudo systemctl start nginx
sudo systemctl enable nginx
```

**✅ Verify:**
```bash
curl http://localhost           # Should show Nginx welcome page
```

---

## Step 6: Install PM2

### 6.1 Install PM2 Globally

```bash
npm install -g pm2
```

**✅ Verify:**
```bash
pm2 -v                          # Should show: 5.x.x
which pm2                       # Should show path with .nvm
```

---

## Step 7: Database Configuration

### 7.1 Choose Database Credentials

**Decide on these values (you'll need them later):**
- Database Name: `bmidb` (default)
- Database User: `bmi_user` (default)
- Database Password: `[choose a strong password]`

### 7.2 Create Database and User

```bash
# Switch to postgres user
sudo -u postgres psql
```

**Inside PostgreSQL prompt:**
```sql
-- Create database
CREATE DATABASE bmidb;

-- Create user with password (replace YOUR_PASSWORD)
CREATE USER bmi_user WITH PASSWORD 'YOUR_PASSWORD';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE bmidb TO bmi_user;
GRANT ALL ON SCHEMA public TO bmi_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO bmi_user;

-- Exit
\q
```

**✅ Verify:**
```bash
# Check if database exists
sudo -u postgres psql -l | grep bmidb

# Check if user exists
sudo -u postgres psql -c "SELECT 1 FROM pg_roles WHERE rolname='bmi_user'"
```

### 7.3 Configure pg_hba.conf for Password Authentication

```bash
# Find pg_hba.conf location
sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file'

# Backup original
sudo cp /etc/postgresql/14/main/pg_hba.conf /etc/postgresql/14/main/pg_hba.conf.backup

# Edit the file
sudo nano /etc/postgresql/14/main/pg_hba.conf
```

**Add this line after `# IPv4 local connections:`**
```
host    bmidb    bmi_user    127.0.0.1/32    md5
```

**Save:** `Ctrl+O`, `Enter`, `Ctrl+X`

### 7.4 Reload PostgreSQL

```bash
sudo systemctl reload postgresql
```

**✅ Verify:**
```bash
# Test connection (enter your password when prompted)
psql -U bmi_user -d bmidb -h localhost -c "SELECT 1;"

# Should show:
#  ?column?
# ----------
#         1
```

---

## Step 8: Clone/Upload Project

### 8.1 Clone from Git (Option A)

```bash
cd ~
git clone YOUR_REPO_URL single-ec2-three-tier-app
cd single-ec2-three-tier-app
```

### 8.2 Upload via SCP (Option B)

**From your local machine:**
```bash
# Zip project (exclude node_modules)
zip -r bmi-app.zip . -x "*/node_modules/*" -x "*/.git/*"

# Upload to EC2
scp -i your-key.pem bmi-app.zip ubuntu@YOUR_EC2_IP:~

# On EC2, extract
unzip bmi-app.zip -d single-ec2-three-tier-app
cd single-ec2-three-tier-app
```

**✅ Verify:**
```bash
ls -la
# Should see: backend/, frontend/, README.md, etc.

ls backend/src
# Should see: server.js, routes.js, db.js, calculations.js

ls frontend/src
# Should see: App.jsx, main.jsx, api.js, etc.
```

---

## Step 9: Backend Configuration

### 9.1 Create .env File

```bash
cd ~/single-ec2-three-tier-app/backend

# Create .env file
nano .env
```

**Add this content (replace YOUR_PASSWORD with your actual password):**
```env
# Database Configuration
DATABASE_URL=postgresql://bmi_user:YOUR_PASSWORD@localhost:5432/bmidb

# Alternative individual settings
DB_USER=bmi_user
DB_PASSWORD=YOUR_PASSWORD
DB_NAME=bmidb
DB_HOST=localhost
DB_PORT=5432

# Server Configuration
PORT=3000
NODE_ENV=production

# CORS Configuration
CORS_ORIGIN=*
```

**Save:** `Ctrl+O`, `Enter`, `Ctrl+X`

### 9.2 Set Permissions

```bash
chmod 600 .env
```

**✅ Verify:**
```bash
cat .env                    # Should show your configuration
ls -l .env                  # Should show: -rw------- (600)
```

---

## Step 10: Deploy Backend

### 10.1 Install Dependencies

```bash
cd ~/single-ec2-three-tier-app/backend
npm install --production
```

**✅ Verify:**
```bash
ls node_modules             # Should show many packages
test -d node_modules/express && echo "Express installed" || echo "Missing express"
test -d node_modules/pg && echo "PostgreSQL driver installed" || echo "Missing pg"
```

### 10.2 Run Database Migrations

```bash
cd ~/single-ec2-three-tier-app/backend

# Source .env for credentials
source .env

# Run all migrations
for migration in migrations/*.sql; do
    if [ -f "$migration" ]; then
        echo "Running: $(basename $migration)"
        PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d $DB_NAME -h localhost -f "$migration"
    fi
done
```

**✅ Verify:**
```bash
# Check if table exists
PGPASSWORD=$DB_PASSWORD psql -U bmi_user -d bmidb -h localhost -c "\d measurements"

# Should show table structure with columns:
# - id, weight_kg, height_cm, age, sex, activity_level
# - bmi, bmi_category, bmr, daily_calories
# - measurement_date, created_at
```

### 10.3 Test Database Connection

```bash
source .env
PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d $DB_NAME -h localhost -c "SELECT 1;"
```

**✅ Verify:**
```bash
# Should show:
#  ?column?
# ----------
#         1
# (1 row)
```

---

## Step 11: Deploy Frontend

### 11.1 Install Dependencies

```bash
cd ~/single-ec2-three-tier-app/frontend
npm install
```

**✅ Verify:**
```bash
ls node_modules             # Should show many packages
test -d node_modules/react && echo "React installed" || echo "Missing react"
test -d node_modules/vite && echo "Vite installed" || echo "Missing vite"
```

### 11.2 Build for Production

```bash
npm run build
```

**✅ Verify:**
```bash
ls -la dist/                # Should show index.html and assets/
test -f dist/index.html && echo "Build successful" || echo "Build failed"
du -sh dist/                # Should show build size (~500KB - 1MB)
```

### 11.3 Deploy to Nginx Directory

```bash
# Create directory
sudo mkdir -p /var/www/bmi-health-tracker

# Copy built files
sudo cp -r dist/* /var/www/bmi-health-tracker/

# Set ownership
sudo chown -R www-data:www-data /var/www/bmi-health-tracker

# Set permissions
sudo chmod -R 755 /var/www/bmi-health-tracker
```

**✅ Verify:**
```bash
ls -la /var/www/bmi-health-tracker/
# Should show: index.html, assets/, etc.

sudo -u www-data test -r /var/www/bmi-health-tracker/index.html && echo "Readable" || echo "Permission issue"
```

---

## Step 12: Configure PM2

### 12.1 Start Backend with PM2

```bash
cd ~/single-ec2-three-tier-app/backend
pm2 start src/server.js --name bmi-backend --env production
```

**✅ Verify:**
```bash
pm2 status
# Should show: bmi-backend | online

pm2 logs bmi-backend --lines 20
# Should show: "Server running on port 3000" and "Connected to PostgreSQL"
```

### 12.2 Save PM2 Configuration

```bash
pm2 save
```

**✅ Verify:**
```bash
cat ~/.pm2/dump.pm2
# Should show saved process list
```

### 12.3 Setup PM2 Auto-start on Reboot

```bash
pm2 startup systemd -u ubuntu --hp /home/ubuntu
```

**Copy and run the command shown in output** (it will look like):
```bash
sudo env PATH=$PATH:/home/ubuntu/.nvm/versions/node/v20.x.x/bin ...
```

**✅ Verify:**
```bash
systemctl status pm2-ubuntu
# Should show: active (exited)

# Simulate reboot test
pm2 resurrect
```

### 12.4 Test Backend API

```bash
curl http://localhost:3000/health
# Should show: {"status":"ok","database":"connected"}

curl http://localhost:3000/api/measurements
# Should show: {"rows":[]}
```

**✅ Verify:**
```bash
# Test with all endpoints
curl -s http://localhost:3000/health | grep -q "ok" && echo "Health check OK" || echo "Health check FAILED"
```

---

## Step 13: Configure Nginx

### 13.1 Get EC2 Public IP

```bash
# Method 1: IMDSv2 (recommended)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Your Public IP: $PUBLIC_IP"

# Method 2: From AWS Console
# Copy from EC2 instance details
```

### 13.2 Create Nginx Configuration

```bash
sudo nano /etc/nginx/sites-available/bmi-health-tracker
```

**Add this configuration (replace YOUR_IP or use _ for catch-all):**
```nginx
server {
    listen 80;
    listen [::]:80;
    
    server_name YOUR_EC2_PUBLIC_IP;  # Or use _ for catch-all

    # Frontend static files
    root /var/www/bmi-health-tracker;
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
        try_files $uri $uri/ /index.html;
        
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
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        
        # Standard proxy headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Disable caching for API
        proxy_cache_bypass $http_upgrade;
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
```

**Save:** `Ctrl+O`, `Enter`, `Ctrl+X`

### 13.3 Enable Site

```bash
# Create symlink
sudo ln -sf /etc/nginx/sites-available/bmi-health-tracker /etc/nginx/sites-enabled/

# Remove default site
sudo rm -f /etc/nginx/sites-enabled/default
```

**✅ Verify:**
```bash
ls -la /etc/nginx/sites-enabled/
# Should show symlink to bmi-health-tracker

sudo nginx -t
# Should show: syntax is ok, test is successful
```

### 13.4 Restart Nginx

```bash
sudo systemctl restart nginx
```

**✅ Verify:**
```bash
sudo systemctl status nginx
# Should show: active (running)

curl -I http://localhost
# Should show: HTTP/1.1 200 OK
```

---

## Step 14: Health Checks

### 14.1 Test Backend Health

```bash
# Health endpoint
curl http://localhost:3000/health

# API endpoint
curl http://localhost:3000/api/measurements

# Via Nginx
curl http://localhost/api/measurements
```

**✅ Expected:**
```json
{"status":"ok","database":"connected"}
{"rows":[]}
```

### 14.2 Test Frontend

```bash
# Via Nginx
curl -I http://localhost

# Check specific files
curl -I http://localhost/assets/
```

**✅ Expected:**
```
HTTP/1.1 200 OK
Content-Type: text/html
```

### 14.3 Test Full Stack

```bash
# Create a test measurement
curl -X POST http://localhost/api/measurements \
  -H "Content-Type: application/json" \
  -d '{
    "weightKg": 70,
    "heightCm": 175,
    "age": 30,
    "sex": "male",
    "activity": "moderate",
    "measurementDate": "2025-12-15"
  }'

# Retrieve measurements
curl http://localhost/api/measurements
```

**✅ Expected:**
```json
{
  "measurement": {
    "id": 1,
    "weight_kg": "70.00",
    "bmi": "22.9",
    ...
  }
}
```

### 14.4 Check PM2 Status

```bash
pm2 status
pm2 logs bmi-backend --lines 50
```

**✅ Expected:**
```
┌────┬────────────────┬─────────┬─────────┬──────┬────────┐
│ id │ name           │ mode    │ status  │ cpu  │ memory │
├────┼────────────────┼─────────┼─────────┼──────┼────────┤
│ 0  │ bmi-backend    │ fork    │ online  │ 0%   │ 50mb   │
└────┴────────────────┴─────────┴─────────┴──────┴────────┘
```

### 14.5 Check Database Connection

```bash
cd ~/single-ec2-three-tier-app/backend
source .env

PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d $DB_NAME -h localhost -c \
  "SELECT COUNT(*) FROM measurements;"
```

**✅ Expected:**
```
 count
-------
     1
```

### 14.6 Check Logs

```bash
# Nginx access logs
sudo tail -f /var/log/nginx/bmi-access.log

# Nginx error logs
sudo tail -f /var/log/nginx/bmi-error.log

# PM2 logs
pm2 logs bmi-backend --lines 100

# PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-14-main.log
```

---

## Step 15: SSL/HTTPS (Optional)

### 15.1 Install Certbot

```bash
sudo apt install -y certbot python3-certbot-nginx
```

**✅ Verify:**
```bash
certbot --version
# Should show: certbot 2.x.x
```

### 15.2 Obtain SSL Certificate

**Prerequisites:**
- Domain name pointing to your EC2 IP
- Port 80 and 443 open in security group

```bash
# Update Nginx server_name with your domain
sudo nano /etc/nginx/sites-available/bmi-health-tracker
# Change: server_name YOUR_DOMAIN.com;

# Test and reload
sudo nginx -t && sudo systemctl reload nginx

# Obtain certificate
sudo certbot --nginx -d YOUR_DOMAIN.com
```

**Follow prompts:**
1. Enter email
2. Agree to terms
3. Choose redirect option (2 - recommended)

**✅ Verify:**
```bash
sudo certbot certificates
# Should show your domain with expiry date

# Test HTTPS
curl -I https://YOUR_DOMAIN.com
# Should show: HTTP/2 200
```

### 15.3 Test Auto-renewal

```bash
sudo certbot renew --dry-run
```

**✅ Expected:**
```
Congratulations, all simulated renewals succeeded
```

---

## Troubleshooting

### Backend Issues

**Problem: Backend not starting**
```bash
# Check logs
pm2 logs bmi-backend --err --lines 50

# Common issues:
# 1. Database connection - check .env credentials
# 2. Port already in use - check: sudo lsof -ti:3000
# 3. Module missing - run: npm install
```

**Problem: Database connection failed**
```bash
# Test connection manually
cd ~/single-ec2-three-tier-app/backend
source .env
PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d $DB_NAME -h localhost

# Check pg_hba.conf
sudo cat /etc/postgresql/14/main/pg_hba.conf | grep bmi

# Reload PostgreSQL
sudo systemctl reload postgresql
```

### Frontend Issues

**Problem: 404 Not Found**
```bash
# Check files exist
ls -la /var/www/bmi-health-tracker/

# Check permissions
sudo -u www-data test -r /var/www/bmi-health-tracker/index.html && echo "OK" || echo "FAIL"

# Verify Nginx config
sudo nginx -t
```

**Problem: White screen / blank page**
```bash
# Check browser console for errors
# Check if API is accessible
curl http://YOUR_IP/api/measurements

# Check Nginx error logs
sudo tail -f /var/log/nginx/bmi-error.log
```

### Nginx Issues

**Problem: 502 Bad Gateway**
```bash
# Check backend is running
pm2 status
curl http://localhost:3000/health

# Check Nginx config
sudo nginx -t

# Check logs
sudo tail -f /var/log/nginx/bmi-error.log
```

**Problem: Configuration test failed**
```bash
# Check syntax
sudo nginx -t

# Common issues:
# - Missing semicolon
# - Invalid server_name
# - Wrong proxy_pass URL

# View specific error
sudo nginx -t 2>&1 | tail -5
```

### PM2 Issues

**Problem: Process not restarting on reboot**
```bash
# Reinstall startup script
pm2 unstartup
pm2 startup systemd -u ubuntu --hp /home/ubuntu
# Run the sudo command shown

pm2 save
sudo systemctl enable pm2-ubuntu
```

**Problem: High memory usage**
```bash
pm2 monit
pm2 reload bmi-backend  # Zero-downtime reload
```

### Database Issues

**Problem: Password authentication failed**
```bash
# Check user password
sudo -u postgres psql -c "ALTER USER bmi_user WITH PASSWORD 'NEW_PASSWORD';"

# Update .env file
nano ~/single-ec2-three-tier-app/backend/.env

# Restart backend
pm2 restart bmi-backend
```

**Problem: Table does not exist**
```bash
# Run migrations again
cd ~/single-ec2-three-tier-app/backend
source .env

for migration in migrations/*.sql; do
    PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d $DB_NAME -h localhost -f "$migration"
done
```

### Useful Commands

```bash
# Check all services
systemctl status postgresql nginx
pm2 status

# Restart everything
sudo systemctl restart postgresql nginx
pm2 restart all

# View all logs
pm2 logs bmi-backend --lines 100
sudo tail -f /var/log/nginx/bmi-*.log

# Check disk space
df -h

# Check memory
free -h

# Check processes
ps aux | grep -E 'node|nginx|postgres'

# Test network connectivity
curl http://localhost:3000/health
curl http://localhost/api/measurements
curl http://YOUR_IP
```

---

## Summary Checklist

After completing all steps, verify:

- [ ] ✅ EC2 instance running
- [ ] ✅ Node.js installed via NVM
- [ ] ✅ PostgreSQL installed and running
- [ ] ✅ Nginx installed and running
- [ ] ✅ PM2 installed
- [ ] ✅ Database created with correct user/password
- [ ] ✅ pg_hba.conf configured for md5 authentication
- [ ] ✅ Project files uploaded/cloned
- [ ] ✅ Backend .env file created with correct credentials
- [ ] ✅ Backend dependencies installed
- [ ] ✅ Database migrations applied
- [ ] ✅ Frontend dependencies installed
- [ ] ✅ Frontend built successfully
- [ ] ✅ Frontend deployed to /var/www/bmi-health-tracker
- [ ] ✅ PM2 running backend
- [ ] ✅ PM2 configured for auto-start
- [ ] ✅ Nginx configured with reverse proxy
- [ ] ✅ Health checks passing
- [ ] ✅ Application accessible via browser
- [ ] ✅ API endpoints working
- [ ] ✅ Database queries working
- [ ] ✅ SSL certificate installed (optional)

---

## Application Access

**URL:** `http://YOUR_EC2_PUBLIC_IP`  
**API:** `http://YOUR_EC2_PUBLIC_IP/api/measurements`  
**Health:** `http://YOUR_EC2_PUBLIC_IP/api/health`

---

## Useful Commands Reference

### PM2 Commands
```bash
pm2 status                    # View process status
pm2 logs bmi-backend         # View logs
pm2 restart bmi-backend      # Restart process
pm2 stop bmi-backend         # Stop process
pm2 start bmi-backend        # Start process
pm2 delete bmi-backend       # Remove process
pm2 save                      # Save current process list
pm2 monit                     # Monitor CPU/Memory
```

### Nginx Commands
```bash
sudo nginx -t                           # Test configuration
sudo systemctl start nginx              # Start Nginx
sudo systemctl stop nginx               # Stop Nginx
sudo systemctl restart nginx            # Restart Nginx
sudo systemctl reload nginx             # Reload config
sudo systemctl status nginx             # Check status
```

### PostgreSQL Commands
```bash
sudo systemctl start postgresql         # Start PostgreSQL
sudo systemctl stop postgresql          # Stop PostgreSQL
sudo systemctl restart postgresql       # Restart PostgreSQL
sudo systemctl status postgresql        # Check status
sudo -u postgres psql                   # Enter PostgreSQL prompt
psql -U bmi_user -d bmidb -h localhost # Connect as app user
```

### Database Backup
```bash
# Backup database
PGPASSWORD=YOUR_PASSWORD pg_dump -U bmi_user -h localhost bmidb > backup_$(date +%Y%m%d).sql

# Restore database
PGPASSWORD=YOUR_PASSWORD psql -U bmi_user -d bmidb -h localhost < backup_20251215.sql
```

---

**Deployment Complete!** 🎉

Your BMI Health Tracker application should now be running at `http://YOUR_EC2_PUBLIC_IP`

**Next Steps:**
1. Test all features in the browser
2. Set up SSL with Let's Encrypt (if using domain)
3. Configure regular database backups
4. Set up monitoring (optional)
5. Configure firewall rules (UFW)

---

**Last Updated:** December 15, 2025  
**Version:** 2.0.0  
**Compatible with:** IMPLEMENTATION_AUTO.sh v2.0.0

---
## 🧑‍💻 Author
**Md. Sarowar Alam**  
Lead DevOps Engineer, Hogarth Worldwide  
📧 Email: sarowar@hotmail.com  
🔗 LinkedIn: [linkedin.com/in/sarowar](https://www.linkedin.com/in/sarowar/)  
---
sudo apt install -y postgresql postgresql-contrib

# Start and enable PostgreSQL service
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Verify it's running
sudo systemctl status postgresql
```

### 3.2 Create Database and User

```bash
# Switch to postgres user and create database user
sudo -u postgres createuser --interactive --pwprompt

# Enter details:
# Username: bmi_user
# Password: [ostad2025]
# Superuser: n
# Create databases: n
# Create roles: n

# Create database owned by bmi_user
sudo -u postgres createdb -O bmi_user bmidb

# Test connection
psql -U bmi_user -d bmidb -h localhost
# Enter password when prompted
# Type \q to quit
```

### 3.3 Configure PostgreSQL for Local Connections (if needed)

```bash
# Edit pg_hba.conf to ensure local connections work
sudo nano /etc/postgresql/*/main/pg_hba.conf

# Ensure this line exists (should be there by default):
# local   all             all                                     md5
# host    all             all             127.0.0.1/32            md5

# Restart PostgreSQL
sudo systemctl restart postgresql
```

---

## Part 4: Deploy the Application

### 4.1 Clone or Upload Project

**Option A: Clone from GitHub (recommended)**
```bash
cd /home/ubuntu
git clone https://github.com/YOUR_USERNAME/bmi-health-tracker.git
cd bmi-health-tracker
```

**Option B: Upload via SCP**
```bash
# On your local machine:
scp -i your-key.pem -r ./bmi-health-tracker ubuntu@YOUR_EC2_PUBLIC_IP:/home/ubuntu/

# Then SSH and navigate:
ssh -i your-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
cd /home/ubuntu/bmi-health-tracker
```

**Option C: Upload as ZIP**
```bash
# On local machine:
zip -r bmi-health-tracker.zip bmi-health-tracker
scp -i your-key.pem bmi-health-tracker.zip ubuntu@YOUR_EC2_PUBLIC_IP:/home/ubuntu/

# On server:
sudo apt install -y unzip
unzip bmi-health-tracker.zip
cd bmi-health-tracker
```

### 4.2 Setup Backend

```bash
cd /home/ubuntu/bmi-health-tracker/backend

# Create environment file from example
cp .env.example .env

# Edit environment variables
nano .env
```

**Configure `.env` file:**
```env
PORT=3000
DATABASE_URL=postgresql://bmi_user:YOUR_DB_PASSWORD@localhost:5432/bmidb
NODE_ENV=production
```

Replace `YOUR_DB_PASSWORD` with the password you created for `bmi_user`.

**Install backend dependencies:**
```bash
npm install --production
```

**Run database migration:**
```bash
# Apply the schema to create the measurements table
psql -U bmi_user -d bmidb -h localhost -f migrations/001_create_measurements.sql
# Enter password when prompted
```

**Test backend locally (optional):**
```bash
npm start
# Should see: "Server started"
# Press Ctrl+C to stop
```

### 4.3 Setup Frontend

```bash
cd /home/ubuntu/bmi-health-tracker/frontend

# Install dependencies
npm install

# Build for production
npm run build
```

This creates a `dist/` folder with optimized static files.

**Deploy built files to Nginx web directory:**
```bash
# Create directory for frontend
sudo mkdir -p /var/www/bmi-health-tracker

# Copy built files
sudo cp -r dist/* /var/www/bmi-health-tracker/

# Set proper ownership
sudo chown -R www-data:www-data /var/www/bmi-health-tracker

# Verify files copied
ls -la /var/www/bmi-health-tracker
```

---

## Part 5: Process Management with PM2

PM2 keeps your Node.js backend running continuously and restarts it on crashes or server reboots.

### 5.1 Install PM2 Globally

```bash
npm install -g pm2
```

### 5.2 Start Backend with PM2

```bash
cd /home/ubuntu/bmi-health-tracker/backend

# Start the backend server
pm2 start src/server.js --name bmi-backend

# Check status
pm2 status

# View logs
pm2 logs bmi-backend

# Save PM2 process list
pm2 save
```

### 5.3 Configure Auto-Start on Reboot

```bash
# Generate startup script
pm2 startup systemd -u ubuntu --hp /home/ubuntu

# Run the command that PM2 outputs (it will be something like):
# sudo env PATH=$PATH:/home/ubuntu/.nvm/versions/node/vXX.X.X/bin ...
# Copy and paste that exact command

# Verify auto-start is configured
sudo systemctl status pm2-ubuntu
```

### 5.4 Useful PM2 Commands

```bash
pm2 list                    # List all processes
pm2 restart bmi-backend     # Restart backend
pm2 stop bmi-backend        # Stop backend
pm2 delete bmi-backend      # Remove from PM2
pm2 logs bmi-backend        # View live logs
pm2 logs bmi-backend --lines 100  # Last 100 lines
pm2 monit                   # Monitor CPU/memory
```

---

## Part 6: Nginx Configuration

### 6.1 Create Nginx Site Configuration

```bash
sudo nano /etc/nginx/sites-available/bmi-health-tracker
```

**Paste this configuration:**

```nginx
server {
    listen 80;
    listen [::]:80;
    
    # Replace with your domain or EC2 public IP
    server_name YOUR_DOMAIN_OR_IP;

    # Frontend static files
    root /var/www/bmi-health-tracker;
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
        try_files $uri $uri/ /index.html;
        
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
        
        # WebSocket support (if needed in future)
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        
        # Standard proxy headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Disable caching for API
        proxy_cache_bypass $http_upgrade;
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
```

**Replace `YOUR_DOMAIN_OR_IP` with:**
- Your domain name (e.g., `bmi.example.com`) if you have one
- Your EC2 public IP (e.g., `3.15.123.45`) if you don't have a domain

### 6.2 Enable the Site

```bash
# Create symbolic link to enable site
sudo ln -s /etc/nginx/sites-available/bmi-health-tracker /etc/nginx/sites-enabled/

# Remove default site (optional)
sudo rm /etc/nginx/sites-enabled/default

# Test Nginx configuration
sudo nginx -t

# If test passes, reload Nginx
sudo systemctl reload nginx

# Check Nginx status
sudo systemctl status nginx
```

### 6.3 Verify Nginx is Running

```bash
# Start Nginx if not running
sudo systemctl start nginx

# Enable auto-start on boot
sudo systemctl enable nginx
```

---

## Part 7: Firewall Configuration (UFW)

Secure your server by enabling Ubuntu's firewall.

### 7.1 Configure UFW

```bash
# Check UFW status
sudo ufw status

# Allow SSH (CRITICAL - do this first!)
sudo ufw allow OpenSSH
# Or if using custom SSH port:
# sudo ufw allow 2222/tcp

# Allow HTTP traffic
sudo ufw allow 'Nginx HTTP'

# Allow HTTPS traffic (for future SSL)
sudo ufw allow 'Nginx HTTPS'

# Or allow specific ports:
# sudo ufw allow 80/tcp
# sudo ufw allow 443/tcp

# Enable firewall
sudo ufw enable

# Verify rules
sudo ufw status verbose
```

**Expected output:**
```
Status: active

To                         Action      From
--                         ------      ----
OpenSSH                    ALLOW       Anywhere
Nginx HTTP                 ALLOW       Anywhere
Nginx HTTPS                ALLOW       Anywhere
```

---

## Part 8: SSL/HTTPS Setup (Optional but Recommended)

Use Let's Encrypt to secure your site with free SSL certificates.

### 8.1 Prerequisites

- A domain name pointed to your EC2 instance's public IP
- DNS A record configured (wait 5-10 minutes for propagation)

### 8.2 Install Certbot

```bash
# Install Certbot and Nginx plugin
sudo apt install -y certbot python3-certbot-nginx
```

### 8.3 Obtain SSL Certificate

```bash
# Replace YOUR_DOMAIN with your actual domain
sudo certbot --nginx -d YOUR_DOMAIN

# Or for both www and non-www:
# sudo certbot --nginx -d example.com -d www.example.com
```

**Follow the prompts:**
1. Enter email address
2. Agree to terms
3. Choose whether to share email with EFF
4. Choose whether to redirect HTTP to HTTPS (recommended: Yes)

### 8.4 Test Auto-Renewal

```bash
# Test renewal process (dry run)
sudo certbot renew --dry-run

# Certificates auto-renew via systemd timer
sudo systemctl status certbot.timer
```

### 8.5 Verify HTTPS

Visit `https://YOUR_DOMAIN` in your browser. You should see a padlock icon.

---

## Part 9: Testing & Verification

### 9.1 Test Backend API

```bash
# Test from server
curl http://localhost:3000/api/measurements

# Test from public internet (replace with your IP/domain)
curl http://YOUR_EC2_PUBLIC_IP/api/measurements
```

Expected response: `{"rows":[]}` (empty array initially)

### 9.2 Test Frontend

Open browser and navigate to:
- `http://YOUR_EC2_PUBLIC_IP` or
- `http://YOUR_DOMAIN` or
- `https://YOUR_DOMAIN` (if SSL configured)

**Check these features:**
1. ✅ Form displays with all 5 input fields
2. ✅ Submit a measurement
3. ✅ Measurement appears in the recent list
4. ✅ Trend chart displays (may be empty initially)
5. ✅ Check browser console for errors (F12)

### 9.3 Test Database

```bash
# Connect to database
psql -U bmi_user -d bmidb -h localhost

# View all measurements
SELECT * FROM measurements;

# Count total measurements
SELECT COUNT(*) FROM measurements;

# Exit
\q
```

### 9.4 Monitor Logs

**Backend logs:**
```bash
pm2 logs bmi-backend
pm2 logs bmi-backend --lines 50
```

**Nginx access logs:**
```bash
sudo tail -f /var/log/nginx/bmi-access.log
```

**Nginx error logs:**
```bash
sudo tail -f /var/log/nginx/bmi-error.log
```

**PostgreSQL logs:**
```bash
sudo tail -f /var/log/postgresql/postgresql-*-main.log
```

---

## Part 10: Maintenance & Troubleshooting

### 10.1 Update Application

```bash
# Navigate to project directory
cd /home/ubuntu/bmi-health-tracker

# Pull latest changes (if using Git)
git pull origin main

# Update backend
cd backend
npm install --production
pm2 restart bmi-backend

# Update frontend
cd ../frontend
npm install
npm run build
sudo rm -rf /var/www/bmi-health-tracker/*
sudo cp -r dist/* /var/www/bmi-health-tracker/
sudo chown -R www-data:www-data /var/www/bmi-health-tracker
```

### 10.2 Common Issues & Solutions

**Issue: Backend not accessible**
```bash
# Check PM2 status
pm2 status

# Restart backend
pm2 restart bmi-backend

# Check logs
pm2 logs bmi-backend --lines 100
```

**Issue: Database connection failed**
```bash
# Verify PostgreSQL is running
sudo systemctl status postgresql

# Test connection
psql -U bmi_user -d bmidb -h localhost

# Check backend .env file has correct DATABASE_URL
cat /home/ubuntu/bmi-health-tracker/backend/.env
```

**Issue: Nginx 502 Bad Gateway**
```bash
# Verify backend is running
pm2 status
curl http://localhost:3000/api/measurements

# Check Nginx error logs
sudo tail -100 /var/log/nginx/bmi-error.log

# Test Nginx config
sudo nginx -t
sudo systemctl restart nginx
```

**Issue: Cannot connect via HTTP**
```bash
# Check UFW firewall
sudo ufw status

# Ensure ports 80/443 are open
sudo ufw allow 'Nginx Full'

# Check Nginx is listening
sudo netstat -tlnp | grep nginx

# Check AWS Security Group has port 80/443 open
```

**Issue: Frontend shows blank page**
```bash
# Check if files were copied
ls -la /var/www/bmi-health-tracker/

# Check browser console for errors (F12)

# Verify Nginx is serving files
curl http://YOUR_EC2_PUBLIC_IP

# Check Nginx error logs
sudo tail -50 /var/log/nginx/bmi-error.log
```

### 10.3 Backup Database

```bash
# Create backup directory
mkdir -p /home/ubuntu/backups

# Backup database
pg_dump -U bmi_user -h localhost bmidb > /home/ubuntu/backups/bmidb_$(date +%Y%m%d_%H%M%S).sql

# Restore database (if needed)
psql -U bmi_user -h localhost bmidb < /home/ubuntu/backups/bmidb_20251212_120000.sql
```

### 10.4 Automated Backups (Optional)

Create a backup script:
```bash
nano /home/ubuntu/backup-db.sh
```

Add:
```bash
#!/bin/bash
BACKUP_DIR="/home/ubuntu/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR
pg_dump -U bmi_user -h localhost bmidb > $BACKUP_DIR/bmidb_$TIMESTAMP.sql
# Keep only last 7 days
find $BACKUP_DIR -name "bmidb_*.sql" -mtime +7 -delete
```

Make executable and add to cron:
```bash
chmod +x /home/ubuntu/backup-db.sh

# Add to crontab (daily at 2 AM)
crontab -e
# Add this line:
0 2 * * * /home/ubuntu/backup-db.sh
```

### 10.5 Server Resource Monitoring

```bash
# Check disk space
df -h

# Check memory usage
free -h

# Check CPU usage
top
# Press 'q' to quit

# Check PM2 resource usage
pm2 monit

# Check system resources
htop  # (install with: sudo apt install htop)
```

---

## Part 11: Server Structure Overview

After successful deployment, your server structure looks like:

```
/home/ubuntu/
├── bmi-health-tracker/
│   ├── backend/
│   │   ├── src/
│   │   │   ├── server.js
│   │   │   ├── routes.js
│   │   │   ├── db.js
│   │   │   └── calculations.js
│   │   ├── migrations/
│   │   │   └── 001_create_measurements.sql
│   │   ├── .env                    # Environment variables
│   │   ├── package.json
│   │   └── node_modules/
│   └── frontend/
│       ├── dist/                   # Build output (copied to /var/www)
│       ├── src/
│       ├── package.json
│       └── node_modules/
│
/var/www/bmi-health-tracker/        # Production frontend files
├── index.html
├── assets/
│   ├── index-[hash].js
│   └── index-[hash].css
└── ...

/etc/nginx/
└── sites-available/
    └── bmi-health-tracker          # Nginx configuration

/var/log/nginx/
├── bmi-access.log                  # Access logs
└── bmi-error.log                   # Error logs
```

---

## Part 12: Security Best Practices

### 12.1 Keep System Updated

```bash
# Update regularly
sudo apt update && sudo apt upgrade -y

# Enable automatic security updates
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

### 12.2 Secure SSH

```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Recommended changes:
# PermitRootLogin no
# PasswordAuthentication no
# Port 2222  # Change default port (optional)

# Restart SSH
sudo systemctl restart sshd
```

### 12.3 Use Strong Database Password

Ensure your PostgreSQL user has a strong password (at least 16 characters, mixed case, numbers, symbols).

### 12.4 Environment Variables

Never commit `.env` file to Git. Keep it secure with proper permissions:
```bash
chmod 600 /home/ubuntu/bmi-health-tracker/backend/.env
```

### 12.5 Regular Backups

- Backup database daily (see Part 10.4)
- Backup application code to Git
- Consider AWS snapshots for entire EC2 instance

---

## Part 13: Cost Optimization

### 13.1 EC2 Instance Sizing

- **Development/Testing**: t2.micro (1 vCPU, 1 GB RAM) - Free tier eligible
- **Low Traffic**: t2.small (1 vCPU, 2 GB RAM) - ~$17/month
- **Medium Traffic**: t2.medium (2 vCPU, 4 GB RAM) - ~$34/month

### 13.2 Use Reserved Instances

For production, consider 1-year Reserved Instances for ~40% savings.

### 13.3 Stop Instance When Not Needed

```bash
# From AWS Console or CLI
aws ec2 stop-instances --instance-ids i-1234567890abcdef0
```

Note: You still pay for EBS storage when stopped.

---

## Deployment Complete! 🎉

Your BMI Health Tracker is now live and accessible!

### Quick Access Commands

```bash
# SSH to server
ssh -i your-key.pem ubuntu@YOUR_EC2_PUBLIC_IP

# Check backend status
pm2 status

# View backend logs
pm2 logs bmi-backend

# Restart backend
pm2 restart bmi-backend

# Check Nginx status
sudo systemctl status nginx

# Reload Nginx config
sudo nginx -t && sudo systemctl reload nginx

# View database
psql -U bmi_user -d bmidb -h localhost
```

---

## Need Help?

**Common Resources:**
- AWS EC2 Documentation: https://docs.aws.amazon.com/ec2/
- Nginx Documentation: https://nginx.org/en/docs/
- PM2 Documentation: https://pm2.keymetrics.io/docs/
- PostgreSQL Documentation: https://www.postgresql.org/docs/

**Checklist:**
- [ ] EC2 instance running
- [ ] Security group configured (ports 22, 80, 443)
- [ ] Node.js and PostgreSQL installed
- [ ] Database created and migrated
- [ ] Backend running via PM2
- [ ] Frontend built and deployed
- [ ] Nginx configured and running
- [ ] Firewall enabled
- [ ] Application accessible via browser
- [ ] SSL certificate installed (optional)
- [ ] Backups configured

---

**Last Updated**: December 12, 2025  
**Version**: 2.0
