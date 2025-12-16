# BMI Health Tracker - Connectivity & Endpoint Testing Guide

This guide provides detailed instructions for testing database connectivity, backend API endpoints, and frontend accessibility from the EC2 server after deployment.

---

## Table of Contents

1. [Database Connectivity Testing](#1-database-connectivity-testing)
2. [Backend API Testing](#2-backend-api-testing)
3. [Frontend Testing](#3-frontend-testing)
4. [End-to-End Testing](#4-end-to-end-testing)
5. [Troubleshooting Connectivity](#5-troubleshooting-connectivity)

---

## 1. Database Connectivity Testing

### 1.1 Basic PostgreSQL Connection Test

```bash
# Test PostgreSQL is running
sudo systemctl status postgresql

# Expected output: "active (running)"
```

### 1.2 Connect to Database

```bash
# Connect using psql client
psql -U bmi_user -d bmidb -h localhost

# Enter password when prompted
```

**Expected:** You should see the PostgreSQL prompt: `bmidb=>`

### 1.3 Test Database Queries

Once connected to PostgreSQL:

```sql
-- 1. Test basic connectivity
SELECT NOW();
-- Expected: Current timestamp

-- 2. Check if measurements table exists
\dt
-- Expected: Shows "measurements" table

-- 3. View table structure
\d measurements
-- Expected: Shows all columns including measurement_date

-- 4. Count records
SELECT COUNT(*) FROM measurements;
-- Expected: Number of measurements (0 if fresh install)

-- 5. View recent measurements
SELECT id, weight_kg, height_cm, bmi, bmi_category, measurement_date, created_at
FROM measurements
ORDER BY measurement_date DESC
LIMIT 5;
-- Expected: List of recent measurements (or empty if none)

-- 6. Test 30-day trends query
SELECT measurement_date AS day, AVG(bmi) AS avg_bmi 
FROM measurements
WHERE measurement_date >= CURRENT_DATE - interval '30 days' 
GROUP BY measurement_date 
ORDER BY measurement_date;
-- Expected: BMI averages grouped by date

-- 7. Exit
\q
```

### 1.4 Connection String Test

```bash
# Test connection using DATABASE_URL
cd /home/ubuntu/bmi-health-tracker/backend
source .env

# Test with psql
psql $DATABASE_URL -c "SELECT 1;"
# Expected: Shows "1"

# Alternative test
PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d $DB_NAME -h $DB_HOST -c "SELECT 1;"
# Expected: Shows "1"
```

### 1.5 Check Database Configuration

```bash
# View PostgreSQL configuration
sudo -u postgres psql -c "SHOW hba_file;"
# Shows location of pg_hba.conf

# Check if bmi_user has correct permissions
sudo -u postgres psql -c "\du bmi_user"
# Expected: Shows role with permissions

# Check database owner
sudo -u postgres psql -c "\l bmidb"
# Expected: Shows bmidb database details
```

### 1.6 Test Database from Backend Code

```bash
cd /home/ubuntu/bmi-health-tracker/backend

# Test database connection using Node.js
node -e "
require('dotenv').config();
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('Connection failed:', err.message);
    process.exit(1);
  }
  console.log('Database connected at:', res.rows[0].now);
  pool.end();
});
"
```

**Expected output:**
```
Database connected at: 2025-12-16T14:30:00.000Z
```

---

## 2. Backend API Testing

### 2.1 Check Backend is Running

```bash
# Check PM2 status
pm2 status

# Expected output:
# ┌────┬────────────────┬─────────┬─────────┬──────┬────────┐
# │ id │ name           │ mode    │ status  │ cpu  │ memory │
# ├────┼────────────────┼─────────┼─────────┼──────┼────────┤
# │ 0  │ bmi-backend    │ fork    │ online  │ 0%   │ 50mb   │
# └────┴────────────────┴─────────┴─────────┴──────┴────────┘

# View backend logs
pm2 logs bmi-backend --lines 20

# Check backend is listening on port 3000
sudo netstat -tlnp | grep :3000
# Expected: Shows node process listening on 127.0.0.1:3000
```

### 2.2 Test Health Endpoint

```bash
# Simple test
curl http://localhost:3000/health

# Expected response:
# {"status":"ok","environment":"production"}

# Verbose test with headers
curl -v http://localhost:3000/health

# Pretty print JSON
curl -s http://localhost:3000/health | jq .
```

### 2.3 Test GET All Measurements

```bash
# Get all measurements
curl http://localhost:3000/api/measurements

# Expected response (empty initially):
# {"rows":[]}

# With pretty printing
curl -s http://localhost:3000/api/measurements | jq .

# Check response headers
curl -I http://localhost:3000/api/measurements
# Expected: HTTP/1.1 200 OK, Content-Type: application/json
```

### 2.4 Test POST Create Measurement

#### Test 1: Valid Measurement

```bash
curl -X POST http://localhost:3000/api/measurements \
  -H "Content-Type: application/json" \
  -d '{
    "weightKg": 70,
    "heightCm": 175,
    "age": 30,
    "sex": "male",
    "activity": "moderate"
  }'
```

**Expected response:**
```json
{
  "measurement": {
    "id": 1,
    "weight_kg": "70.00",
    "height_cm": "175.00",
    "age": 30,
    "sex": "male",
    "activity_level": "moderate",
    "bmi": "22.9",
    "bmi_category": "Normal",
    "bmr": 1732,
    "daily_calories": 2685,
    "measurement_date": "2025-12-16",
    "created_at": "2025-12-16T14:30:00.000Z"
  }
}
```

#### Test 2: With Custom Date

```bash
curl -X POST http://localhost:3000/api/measurements \
  -H "Content-Type: application/json" \
  -d '{
    "weightKg": 75,
    "heightCm": 180,
    "age": 28,
    "sex": "male",
    "activity": "active",
    "measurementDate": "2025-12-10"
  }'
```

**Expected:** Same format but with `measurement_date: "2025-12-10"`

#### Test 3: Invalid Data (Should Fail)

```bash
# Missing required fields
curl -X POST http://localhost:3000/api/measurements \
  -H "Content-Type: application/json" \
  -d '{
    "weightKg": 70
  }'

# Expected: 400 Bad Request
# {"error":"Missing required fields"}

# Invalid values
curl -X POST http://localhost:3000/api/measurements \
  -H "Content-Type: application/json" \
  -d '{
    "weightKg": -10,
    "heightCm": 175,
    "age": 30,
    "sex": "male",
    "activity": "moderate"
  }'

# Expected: 400 Bad Request
# {"error":"Invalid values: must be positive numbers"}
```

### 2.5 Test GET Trends Endpoint

```bash
# Get 30-day BMI trends
curl http://localhost:3000/api/measurements/trends

# Expected response (empty if no data):
# {"rows":[]}

# With data:
# {"rows":[
#   {"day":"2025-12-10","avg_bmi":"23.1"},
#   {"day":"2025-12-16","avg_bmi":"22.9"}
# ]}

# Pretty print
curl -s http://localhost:3000/api/measurements/trends | jq .
```

### 2.6 Test All Activity Levels

```bash
# Test each activity level
for activity in sedentary light moderate active very_active; do
  echo "Testing activity: $activity"
  curl -s -X POST http://localhost:3000/api/measurements \
    -H "Content-Type: application/json" \
    -d "{
      \"weightKg\": 70,
      \"heightCm\": 175,
      \"age\": 30,
      \"sex\": \"male\",
      \"activity\": \"$activity\",
      \"measurementDate\": \"2025-12-15\"
    }" | jq '.measurement | {activity: .activity_level, calories: .daily_calories}'
  echo ""
done
```

**Expected:** Different calorie values for each activity level

### 2.7 Test CORS Headers

```bash
# Test CORS headers
curl -H "Origin: http://localhost:5173" \
     -H "Access-Control-Request-Method: POST" \
     -H "Access-Control-Request-Headers: Content-Type" \
     -X OPTIONS http://localhost:3000/api/measurements -v

# Expected: Access-Control-Allow-Origin header in response
```

### 2.8 Backend API Endpoint Summary

| Endpoint | Method | Description | Request Body | Response |
|----------|--------|-------------|--------------|----------|
| `/health` | GET | Health check | None | `{"status":"ok","environment":"production"}` |
| `/api/measurements` | GET | Get all measurements | None | `{"rows":[...]}` |
| `/api/measurements` | POST | Create measurement | JSON with health data | `{"measurement":{...}}` |
| `/api/measurements/trends` | GET | Get 30-day BMI trends | None | `{"rows":[{"day":"...","avg_bmi":"..."}]}` |

### 2.9 Performance Testing

```bash
# Test response time
time curl -s http://localhost:3000/api/measurements > /dev/null

# Load test with multiple requests
for i in {1..10}; do
  curl -s http://localhost:3000/api/measurements > /dev/null &
done
wait
echo "10 parallel requests completed"

# Check if backend is still responsive
curl http://localhost:3000/health
```

---

## 3. Frontend Testing

### 3.1 Check Nginx is Running

```bash
# Check Nginx status
sudo systemctl status nginx

# Expected: "active (running)"

# Test Nginx configuration
sudo nginx -t

# Expected: "syntax is ok" and "test is successful"

# Check Nginx is listening on port 80
sudo netstat -tlnp | grep :80
# Expected: Shows nginx listening on 0.0.0.0:80
```

### 3.2 Test Frontend Static Files

```bash
# Test root page (index.html)
curl http://localhost/

# Expected: HTML content with <!DOCTYPE html>

# Test with verbose output
curl -v http://localhost/

# Check response headers
curl -I http://localhost/
# Expected: HTTP/1.1 200 OK, Content-Type: text/html

# Verify index.html exists
ls -la /var/www/bmi-health-tracker/index.html

# Check file permissions
sudo -u www-data test -r /var/www/bmi-health-tracker/index.html && echo "Readable" || echo "Permission denied"
```

### 3.3 Test Frontend Assets

```bash
# List all deployed files
ls -la /var/www/bmi-health-tracker/

# Expected structure:
# - index.html
# - assets/
#   - index-[hash].js
#   - index-[hash].css

# Test JavaScript files
curl -I http://localhost/assets/*.js
# Expected: HTTP/1.1 200 OK, Content-Type: application/javascript

# Test CSS files
curl -I http://localhost/assets/*.css
# Expected: HTTP/1.1 200 OK, Content-Type: text/css
```

### 3.4 Test API Proxy (Frontend → Backend)

```bash
# Test API through Nginx proxy
curl http://localhost/api/measurements

# Expected: Same response as direct backend call
# {"rows":[...]}

# Test health endpoint through proxy
curl http://localhost/api/health
# Note: This might return 404 as /api/health may not exist
# Use backend health: curl http://localhost:3000/health

# Create measurement through proxy
curl -X POST http://localhost/api/measurements \
  -H "Content-Type: application/json" \
  -d '{
    "weightKg": 70,
    "heightCm": 175,
    "age": 30,
    "sex": "male",
    "activity": "moderate"
  }'

# Expected: Same response as direct backend call
```

### 3.5 Test from Public IP

```bash
# Get your EC2 public IP
curl -s http://checkip.amazonaws.com

# Or using AWS metadata service (IMDSv2)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Public IP: $PUBLIC_IP"

# Test frontend from server using public IP
curl http://$PUBLIC_IP/

# Test API from server using public IP
curl http://$PUBLIC_IP/api/measurements
```

### 3.6 Test Frontend Routing

```bash
# Test root route
curl -I http://localhost/
# Expected: 200 OK

# Test non-existent route (React Router should serve index.html)
curl -I http://localhost/some-random-path
# Expected: 200 OK (Nginx serves index.html for SPA routing)

# Test API route
curl -I http://localhost/api/measurements
# Expected: 200 OK
```

### 3.7 Check Frontend Logs

```bash
# Nginx access logs
sudo tail -20 /var/log/nginx/bmi-access.log

# Nginx error logs
sudo tail -20 /var/log/nginx/bmi-error.log

# Watch logs in real-time
sudo tail -f /var/log/nginx/bmi-access.log

# Filter for errors only
sudo grep "error" /var/log/nginx/bmi-error.log
```

### 3.8 Test Compression

```bash
# Check if gzip compression is working
curl -H "Accept-Encoding: gzip" -I http://localhost/

# Expected headers:
# Content-Encoding: gzip

# Test with actual content
curl -H "Accept-Encoding: gzip" http://localhost/ | file -
# Expected: gzip compressed data
```

---

## 4. End-to-End Testing

### 4.1 Complete User Flow Test

```bash
#!/bin/bash
# Complete end-to-end test script

echo "=== BMI Health Tracker E2E Test ==="
echo ""

# 1. Check all services
echo "1. Checking services..."
sudo systemctl is-active postgresql > /dev/null && echo "[OK] PostgreSQL running" || echo "[FAIL] PostgreSQL not running"
sudo systemctl is-active nginx > /dev/null && echo "[OK] Nginx running" || echo "[FAIL] Nginx not running"
pm2 list | grep -q "bmi-backend.*online" && echo "[OK] Backend running" || echo "[FAIL] Backend not running"
echo ""

# 2. Test database connectivity
echo "2. Testing database..."
psql -U bmi_user -d bmidb -h localhost -c "SELECT 1;" > /dev/null 2>&1 && echo "[OK] Database connected" || echo "[FAIL] Database connection failed"
echo ""

# 3. Test backend API
echo "3. Testing backend API..."
HEALTH=$(curl -s http://localhost:3000/health)
echo "$HEALTH" | grep -q "ok" && echo "[OK] Backend health OK" || echo "[FAIL] Backend health check failed"

MEASUREMENTS=$(curl -s http://localhost:3000/api/measurements)
echo "$MEASUREMENTS" | grep -q "rows" && echo "[OK] Backend API responding" || echo "[FAIL] Backend API failed"
echo ""

# 4. Test frontend
echo "4. Testing frontend..."
curl -s http://localhost/ | grep -q "<!DOCTYPE html>" && echo "[OK] Frontend serving HTML" || echo "[FAIL] Frontend not accessible"
echo ""

# 5. Test API proxy
echo "5. Testing API proxy through Nginx..."
PROXY=$(curl -s http://localhost/api/measurements)
echo "$PROXY" | grep -q "rows" && echo "[OK] API proxy working" || echo "[FAIL] API proxy failed"
echo ""

# 6. Create test measurement
echo "6. Creating test measurement..."
RESULT=$(curl -s -X POST http://localhost:3000/api/measurements \
  -H "Content-Type: application/json" \
  -d '{
    "weightKg": 70,
    "heightCm": 175,
    "age": 30,
    "sex": "male",
    "activity": "moderate",
    "measurementDate": "2025-12-16"
  }')

echo "$RESULT" | grep -q "measurement" && echo "[OK] Measurement created" || echo "[FAIL] Failed to create measurement"

# Extract BMI from response
BMI=$(echo "$RESULT" | grep -o '"bmi":"[^"]*"' | cut -d'"' -f4)
echo "   BMI calculated: $BMI"
echo ""

# 7. Verify measurement was saved
echo "7. Verifying measurement in database..."
COUNT=$(psql -U bmi_user -d bmidb -h localhost -t -c "SELECT COUNT(*) FROM measurements;" 2>/dev/null | tr -d ' ')
echo "   Total measurements in database: $COUNT"
[ "$COUNT" -gt 0 ] && echo "[OK] Measurement saved to database" || echo "[FAIL] No measurements in database"
echo ""

# 8. Test trends endpoint
echo "8. Testing trends endpoint..."
TRENDS=$(curl -s http://localhost:3000/api/measurements/trends)
echo "$TRENDS" | grep -q "rows" && echo "[OK] Trends endpoint working" || echo "[FAIL] Trends endpoint failed"
echo ""

echo "=== Test Complete ==="
```

Save this script and run it:
```bash
chmod +x e2e-test.sh
./e2e-test.sh
```

### 4.2 Browser Testing Checklist

Open your browser and navigate to `http://YOUR_EC2_PUBLIC_IP`

**Manual Checks:**
1. [ ] Page loads without errors
2. [ ] Form displays with all 6 fields (including date picker)
3. [ ] Date picker defaults to today
4. [ ] Cannot select future dates
5. [ ] Can select past dates
6. [ ] Fill in all fields and submit
7. [ ] Success message appears
8. [ ] Measurement appears in the list immediately
9. [ ] Stats cards update with new values
10. [ ] BMI category shows correct color coding
11. [ ] Trend chart displays (may take a moment)
12. [ ] Browser console has no errors (F12)
13. [ ] Network tab shows successful API calls

**Browser Console Test:**
Press F12, go to Console tab, and run:
```javascript
// Test API from browser
fetch('/api/measurements')
  .then(r => r.json())
  .then(data => console.log('Measurements:', data))
  .catch(err => console.error('Error:', err));

// Test creating measurement
fetch('/api/measurements', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    weightKg: 75,
    heightCm: 180,
    age: 28,
    sex: 'male',
    activity: 'moderate'
  })
})
  .then(r => r.json())
  .then(data => console.log('Created:', data))
  .catch(err => console.error('Error:', err));
```

---

## 5. Troubleshooting Connectivity

### 5.1 Database Connection Issues

**Problem: "Connection refused"**
```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# If not running, start it
sudo systemctl start postgresql

# Check if listening on port 5432
sudo netstat -tlnp | grep 5432
```

**Problem: "Authentication failed"**
```bash
# Verify password is correct
cat /home/ubuntu/bmi-health-tracker/backend/.env | grep DB_PASSWORD

# Test with psql
psql -U bmi_user -d bmidb -h localhost

# Check pg_hba.conf
sudo cat /etc/postgresql/*/main/pg_hba.conf | grep bmi
# Should show: host bmidb bmi_user 127.0.0.1/32 md5

# Reload PostgreSQL if you made changes
sudo systemctl reload postgresql
```

**Problem: "Database does not exist"**
```bash
# List all databases
sudo -u postgres psql -c "\l" | grep bmidb

# If missing, create it
sudo -u postgres psql -c "CREATE DATABASE bmidb;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE bmidb TO bmi_user;"
```

### 5.2 Backend Connection Issues

**Problem: "Cannot connect to backend"**
```bash
# Check PM2 status
pm2 status

# If not running, start it
cd /home/ubuntu/bmi-health-tracker/backend
pm2 start src/server.js --name bmi-backend

# Check logs for errors
pm2 logs bmi-backend --lines 50

# Test port is open
curl http://localhost:3000/health
```

**Problem: "Port 3000 already in use"**
```bash
# Find process using port 3000
sudo lsof -ti:3000

# Kill the process
sudo kill -9 $(sudo lsof -ti:3000)

# Restart backend
pm2 restart bmi-backend
```

**Problem: "Backend crashes immediately"**
```bash
# Check error logs
pm2 logs bmi-backend --err --lines 50

# Common causes:
# 1. Database connection error - check .env
# 2. Missing dependencies - run npm install
# 3. Syntax error - check code

# Verify .env exists and is valid
cat /home/ubuntu/bmi-health-tracker/backend/.env

# Test backend manually
cd /home/ubuntu/bmi-health-tracker/backend
node src/server.js
# Watch for error messages
```

### 5.3 Frontend Connection Issues

**Problem: "404 Not Found"**
```bash
# Check if files were deployed
ls -la /var/www/bmi-health-tracker/

# Should contain:
# - index.html
# - assets/ directory

# If missing, rebuild and deploy:
cd /home/ubuntu/bmi-health-tracker/frontend
npm run build
sudo cp -r dist/* /var/www/bmi-health-tracker/
sudo chown -R www-data:www-data /var/www/bmi-health-tracker
```

**Problem: "Permission denied"**
```bash
# Fix permissions
sudo chown -R www-data:www-data /var/www/bmi-health-tracker
sudo chmod -R 755 /var/www/bmi-health-tracker

# Verify www-data can read files
sudo -u www-data test -r /var/www/bmi-health-tracker/index.html && echo "OK" || echo "FAIL"
```

**Problem: "502 Bad Gateway"**
```bash
# This means Nginx can't reach backend
# Check backend is running
pm2 status

# Check Nginx proxy configuration
sudo cat /etc/nginx/sites-available/bmi-health-tracker | grep proxy_pass
# Should show: proxy_pass http://127.0.0.1:3000/api/;

# Test backend directly
curl http://localhost:3000/api/measurements

# Restart Nginx
sudo nginx -t && sudo systemctl reload nginx
```

### 5.4 Firewall Issues

**Problem: "Can't access from browser but works locally"**
```bash
# Check AWS Security Group
# - Go to EC2 Console
# - Select instance → Security → Security groups
# - Verify port 80 is open to 0.0.0.0/0

# Check UFW firewall
sudo ufw status

# If blocking HTTP, allow it:
sudo ufw allow 'Nginx HTTP'

# Test from server
curl http://localhost/

# Get public IP and test
curl http://checkip.amazonaws.com
```

### 5.5 Quick Diagnostic Script

```bash
#!/bin/bash
# Quick diagnostic script

echo "=== Connectivity Diagnostic ==="
echo ""

echo "Services:"
systemctl is-active postgresql && echo "[OK] PostgreSQL" || echo "[FAIL] PostgreSQL"
systemctl is-active nginx && echo "[OK] Nginx" || echo "[FAIL] Nginx"
pm2 list | grep -q "bmi-backend.*online" && echo "[OK] Backend PM2" || echo "[FAIL] Backend PM2"
echo ""

echo "Ports:"
sudo netstat -tlnp | grep -q :5432 && echo "[OK] Port 5432 (PostgreSQL)" || echo "[FAIL] Port 5432"
sudo netstat -tlnp | grep -q :3000 && echo "[OK] Port 3000 (Backend)" || echo "[FAIL] Port 3000"
sudo netstat -tlnp | grep -q :80 && echo "[OK] Port 80 (Nginx)" || echo "[FAIL] Port 80"
echo ""

echo "Connectivity:"
psql -U bmi_user -d bmidb -h localhost -c "SELECT 1;" > /dev/null 2>&1 && echo "[OK] Database" || echo "[FAIL] Database"
curl -sf http://localhost:3000/health > /dev/null && echo "[OK] Backend API" || echo "[FAIL] Backend API"
curl -sf http://localhost/ > /dev/null && echo "[OK] Frontend" || echo "[FAIL] Frontend"
curl -sf http://localhost/api/measurements > /dev/null && echo "[OK] API Proxy" || echo "[FAIL] API Proxy"
echo ""

echo "Files:"
[ -f /var/www/bmi-health-tracker/index.html ] && echo "[OK] Frontend deployed" || echo "[FAIL] Frontend missing"
[ -f /home/ubuntu/bmi-health-tracker/backend/.env ] && echo "[OK] Backend .env" || echo "[FAIL] Backend .env missing"
echo ""
```

---

## Quick Reference Card

### Database
```bash
# Connect
psql -U bmi_user -d bmidb -h localhost

# Quick query
psql -U bmi_user -d bmidb -h localhost -c "SELECT COUNT(*) FROM measurements;"
```

### Backend
```bash
# Status
pm2 status

# Logs
pm2 logs bmi-backend

# Test
curl http://localhost:3000/health
curl http://localhost:3000/api/measurements
```

### Frontend
```bash
# Test
curl http://localhost/
curl http://localhost/api/measurements

# Logs
sudo tail -f /var/log/nginx/bmi-access.log
```

### All-in-One Test
```bash
echo "Database:" && psql -U bmi_user -d bmidb -h localhost -c "SELECT 1;" > /dev/null 2>&1 && echo "OK" || echo "FAIL"
echo "Backend:" && curl -sf http://localhost:3000/health > /dev/null && echo "OK" || echo "FAIL"
echo "Frontend:" && curl -sf http://localhost/ > /dev/null && echo "OK" || echo "FAIL"
echo "API Proxy:" && curl -sf http://localhost/api/measurements > /dev/null && echo "OK" || echo "FAIL"
```

---

**Last Updated**: December 16, 2025  
**Version**: 1.0  
**For**: BMI Health Tracker Deployment
