# BMI Health Tracker - Complete Project Reconstruction Guide

**⚠️ IMPORTANT: This file contains EVERYTHING needed to recreate the entire project from scratch!**

---

## Overview
A full-stack 3-tier web application for tracking Body Mass Index (BMI), Basal Metabolic Rate (BMR), and daily calorie requirements. The application features trend visualization, custom measurement dates for historical data entry, and stores all measurement data in PostgreSQL.

**Deployment Target**: Single Ubuntu EC2 server

**Key Features**:
- Health metrics calculation (BMI, BMR, Daily Calories)
- Custom measurement dates for entering past data
- 30-day BMI trend visualization
- Historical data tracking
- Production-ready deployment with automated script

---

## Quick Recreation Steps

1. Create directory structure (see below)
2. Copy all file contents from this document
3. Run `npm install` in backend and frontend
4. Setup database with migration SQL
5. Configure `.env` file
6. Deploy following deployment guide

---

## Complete Directory Structure

```
bmi-health-tracker/
├── .gitignore
├── README.md
├── AGENT.md (this file)
├── CONNECTIVITY.md
├── DEPLOYMENT_CHECKLIST.md
├── DEPLOYMENT_READY.md
├── IMPLEMENTATION_GUIDE.md
├── FINAL_AUDIT.md
├── BMI_Health_Tracker_Deployment_Readme.md
├── DevOpsReadme.md
├── deploy.sh
├── setup-database.sh
├── IMPLEMENTATION_AUTO.sh (automated deployment)
│
├── backend/
│   ├── src/
│   │   ├── server.js
│   │   ├── routes.js
│   │   ├── db.js
│   │   └── calculations.js
│   ├── migrations/
│   │   ├── 001_create_measurements.sql
│   │   └── 002_add_measurement_date.sql
│   ├── .env.example
│   ├── ecosystem.config.js
│   └── package.json
│
└── frontend/
    ├── src/
    │   ├── components/
    │   │   ├── MeasurementForm.jsx
    │   │   └── TrendChart.jsx
    │   ├── App.jsx
    │   ├── main.jsx
    │   ├── api.js
    │   └── index.css
    ├── index.html
    ├── vite.config.js
    └── package.json
```

---

## Architecture

### 3-Tier Structure
1. **Frontend (Presentation Layer)**: React 18.2 + Vite 5.0
2. **Backend (Application Layer)**: Node.js + Express REST API
3. **Database (Data Layer)**: PostgreSQL

### Connectivity Flow
```
Browser → Vite Dev Server (5173) → Proxy → Express API (3000) → PostgreSQL (5432)
Browser → Nginx (80/443) → Express API (3000) → PostgreSQL (5432) [Production]
```

---

## Tech Stack

### Backend
- Node.js (18+ LTS)
- Express.js 4.18
- PostgreSQL with pg 8.10
- CORS 2.8
- dotenv 16.0
- body-parser 1.20

### Frontend
- React 18.2
- Vite 5.0
- Axios 1.4
- Chart.js 4.4
- react-chartjs-2 5.2

---

## Complete File Contents

### 1. Backend Files

#### backend/package.json
```json
{
  "name": "bmi-health-backend",
  "version": "1.0.0",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "nodemon src/server.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "dotenv": "^16.0.0",
    "express": "^4.18.2",
    "pg": "^8.10.0",
    "body-parser": "^1.20.2"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
```

#### backend/src/server.js
```javascript
require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const routes = require('./routes');

const app = express();
const PORT = process.env.PORT || 3000;
const NODE_ENV = process.env.NODE_ENV || 'development';

// CORS configuration
const corsOptions = {
  origin: NODE_ENV === 'production' 
    ? process.env.FRONTEND_URL || 'http://localhost'
    : ['http://localhost:5173', 'http://localhost:3000'],
  credentials: true,
  optionsSuccessStatus: 200
};

app.use(cors(corsOptions));
app.use(bodyParser.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', environment: NODE_ENV });
});

// API routes
app.use('/api', routes);

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// Error handler
app.use((err, req, res, next) => {
  console.error('Server error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📊 Environment: ${NODE_ENV}`);
  console.log(`🔗 API available at: http://localhost:${PORT}/api`);
});
```

#### backend/src/routes.js
```javascript
const express = require('express');
const router = express.Router();
const db = require('./db');
const { calculateMetrics } = require('./calculations');

// POST /api/measurements - Create new measurement
router.post('/measurements', async (req, res) => {
  try {
    const { weightKg, heightCm, age, sex, activity, measurementDate } = req.body;
    
    // Validation
    if (!weightKg || !heightCm || !age || !sex) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    if (weightKg <= 0 || heightCm <= 0 || age <= 0) {
      return res.status(400).json({ error: 'Invalid values: must be positive numbers' });
    }
    
    const m = calculateMetrics({ weightKg, heightCm, age, sex, activity });
    // Use provided date or default to today
    const date = measurementDate || new Date().toISOString().split('T')[0];
    const q = `INSERT INTO measurements (weight_kg,height_cm,age,sex,activity_level,bmi,bmi_category,bmr,daily_calories,measurement_date,created_at)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,now()) RETURNING *`;
    const v = [weightKg, heightCm, age, sex, activity, m.bmi, m.bmiCategory, m.bmr, m.dailyCalories, date];
    const r = await db.query(q, v);
    res.status(201).json({ measurement: r.rows[0] });
  } catch (e) {
    console.error('Error creating measurement:', e);
    res.status(500).json({ error: e.message || 'Failed to create measurement' });
  }
});

// GET /api/measurements - Get all measurements (ordered by measurement_date)
router.get('/measurements', async (req, res) => {
  try {
    const r = await db.query('SELECT * FROM measurements ORDER BY measurement_date DESC, created_at DESC');
    res.json({ rows: r.rows });
  } catch (e) {
    console.error('Error fetching measurements:', e);
    res.status(500).json({ error: 'Failed to fetch measurements' });
  }
});

// GET /api/measurements/trends - Get 30-day BMI trends (using measurement_date)
router.get('/measurements/trends', async (req, res) => {
  try {
    const q = `SELECT measurement_date AS day, AVG(bmi) AS avg_bmi 
    FROM measurements
    WHERE measurement_date >= CURRENT_DATE - interval '30 days' 
    GROUP BY measurement_date 
    ORDER BY measurement_date`;
    const r = await db.query(q);
    res.json({ rows: r.rows });
  } catch (e) {
    console.error('Error fetching trends:', e);
    res.status(500).json({ error: 'Failed to fetch trends' });
  }
});

module.exports = router;
```

#### backend/src/db.js
```javascript
const { Pool } = require('pg');

// PostgreSQL connection pool configuration
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 20, // Maximum number of clients in the pool
  idleTimeoutMillis: 30000, // Close idle clients after 30 seconds
  connectionTimeoutMillis: 2000, // Return error after 2 seconds if can't connect
});

// Handle pool errors
pool.on('error', (err, client) => {
  console.error('Unexpected error on idle PostgreSQL client:', err);
  process.exit(-1);
});

// Test connection on startup
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('❌ Database connection failed:', err.message);
    process.exit(1);
  } else {
    console.log('✅ Database connected successfully at:', res.rows[0].now);
  }
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool
};
```

#### backend/src/calculations.js
```javascript
function bmiCategory(b) {
  if (b < 18.5) return 'Underweight';
  if (b < 25) return 'Normal';
  if (b < 30) return 'Overweight';
  return 'Obese';
}

function calculateMetrics({ weightKg, heightCm, age, sex, activity }) {
  const h = heightCm / 100;
  const bmi = +(weightKg / (h * h)).toFixed(1);
  
  let bmr = sex === 'male'
    ? 10 * weightKg + 6.25 * heightCm - 5 * age + 5
    : 10 * weightKg + 6.25 * heightCm - 5 * age - 161;
  
  const mult = {
    sedentary: 1.2,
    light: 1.375,
    moderate: 1.55,
    active: 1.725,
    very_active: 1.9
  }[activity] || 1.2;
  
  return {
    bmi,
    bmiCategory: bmiCategory(bmi),
    bmr: Math.round(bmr),
    dailyCalories: Math.round(bmr * mult)
  };
}

module.exports = { calculateMetrics };
```

#### backend/.env.example
```env
PORT=3000
DATABASE_URL=postgresql://bmi_user:strongpassword@localhost:5432/bmidb
NODE_ENV=production
FRONTEND_URL=http://localhost
```

#### backend/ecosystem.config.js
```javascript
module.exports = {
  apps: [{
    name: 'bmi-backend',
    script: './src/server.js',
    cwd: '/home/ubuntu/bmi-health-tracker/backend',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    time: true,
    merge_logs: true,
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
  }]
};
```

#### backend/migrations/001_create_measurements.sql
```sql
-- BMI Health Tracker Database Migration
-- Version: 001
-- Description: Create measurements table
-- Date: 2025-12-12

-- Create measurements table
CREATE TABLE IF NOT EXISTS measurements (
  id SERIAL PRIMARY KEY,
  weight_kg NUMERIC(5,2) NOT NULL CHECK (weight_kg > 0 AND weight_kg < 1000),
  height_cm NUMERIC(5,2) NOT NULL CHECK (height_cm > 0 AND height_cm < 300),
  age INTEGER NOT NULL CHECK (age > 0 AND age < 150),
  sex VARCHAR(10) NOT NULL CHECK (sex IN ('male', 'female')),
  activity_level VARCHAR(30) CHECK (activity_level IN ('sedentary', 'light', 'moderate', 'active', 'very_active')),
  bmi NUMERIC(4,1) NOT NULL,
  bmi_category VARCHAR(30),
  bmr INTEGER,
  daily_calories INTEGER,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_measurements_created_at ON measurements(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_measurements_bmi ON measurements(bmi);

-- Add comments for documentation
COMMENT ON TABLE measurements IS 'Stores user health measurements including BMI, BMR, and calorie data';
COMMENT ON COLUMN measurements.weight_kg IS 'Weight in kilograms';
COMMENT ON COLUMN measurements.height_cm IS 'Height in centimeters';
COMMENT ON COLUMN measurements.age IS 'Age in years';
COMMENT ON COLUMN measurements.sex IS 'Biological sex (male/female)';
COMMENT ON COLUMN measurements.activity_level IS 'Physical activity level';
COMMENT ON COLUMN measurements.bmi IS 'Body Mass Index';
COMMENT ON COLUMN measurements.bmi_category IS 'BMI category (Underweight/Normal/Overweight/Obese)';
COMMENT ON COLUMN measurements.bmr IS 'Basal Metabolic Rate in calories';
COMMENT ON COLUMN measurements.daily_calories IS 'Daily calorie needs based on activity';

-- Display confirmation
SELECT 'Migration 001 completed successfully - measurements table created' AS status;
```

#### backend/migrations/002_add_measurement_date.sql
```sql
-- BMI Health Tracker Database Migration
-- Version: 002
-- Description: Add measurement_date column for custom date tracking
-- Date: 2025-12-15

-- Add measurement_date column if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name='measurements' AND column_name='measurement_date'
    ) THEN
        ALTER TABLE measurements 
        ADD COLUMN measurement_date DATE NOT NULL DEFAULT CURRENT_DATE;
        
        -- Update existing records to use created_at date
        UPDATE measurements 
        SET measurement_date = DATE(created_at);
        
        -- Create index for better performance
        CREATE INDEX idx_measurements_measurement_date ON measurements(measurement_date DESC);
        
        RAISE NOTICE 'Column measurement_date added successfully';
    ELSE
        RAISE NOTICE 'Column measurement_date already exists';
    END IF;
END $$;

-- Add comment
COMMENT ON COLUMN measurements.measurement_date IS 'Date when the measurement was taken (user-specified or current date)';

-- Display confirmation
SELECT 'Migration 002 completed successfully - measurement_date column added' AS status;
```

---

### 2. Frontend Files

#### frontend/package.json
```json
{
  "name": "bmi-health-frontend",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview --port 5173"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "axios": "^1.4.0",
    "chart.js": "^4.4.0",
    "react-chartjs-2": "^5.2.0"
  },
  "devDependencies": {
    "vite": "^5.0.0",
    "@vitejs/plugin-react": "^4.2.0"
  }
}
```

#### frontend/vite.config.js
```javascript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:3000',
        changeOrigin: true
      }
    }
  }
});
```

#### frontend/index.html
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta name="description" content="BMI and Health Tracker - Track your Body Mass Index, BMR, and daily calorie needs" />
  <title>BMI & Health Tracker</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
```

#### frontend/src/main.jsx
```javascript
import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import './index.css';

createRoot(document.getElementById('root')).render(<App />);
```

#### frontend/src/api.js
```javascript
import axios from 'axios';

const api = axios.create({
  baseURL: '/api',
  timeout: 10000, // 10 second timeout
  headers: {
    'Content-Type': 'application/json'
  }
});

// Request interceptor
api.interceptors.request.use(
  config => {
    return config;
  },
  error => {
    console.error('Request error:', error);
    return Promise.reject(error);
  }
);

// Response interceptor for error handling
api.interceptors.response.use(
  response => response,
  error => {
    if (error.response) {
      // Server responded with error status
      console.error('API Error:', error.response.status, error.response.data);
    } else if (error.request) {
      // Request made but no response
      console.error('Network Error: No response from server');
    } else {
      // Something else happened
      console.error('Error:', error.message);
    }
    return Promise.reject(error);
  }
);

export default api;
```

#### frontend/src/App.jsx
```javascript
import React, { useEffect, useState } from 'react';
import MeasurementForm from './components/MeasurementForm';
import TrendChart from './components/TrendChart';
import api from './api';

export default function App() {
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  
  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const r = await api.get('/measurements');
      setRows(r.data.rows);
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to load measurements');
    } finally {
      setLoading(false);
    }
  };
  
  useEffect(() => { load() }, []);
  
  // Calculate stats
  const latestMeasurement = rows[0];
  const totalMeasurements = rows.length;
  
  return (
    <>
      <header className="app-header">
        <h1>BMI & Health Tracker</h1>
        <p className="app-subtitle">Track your health metrics and reach your fitness goals</p>
      </header>

      <div className="container">
        {/* Add Measurement Card */}
        <div className="card">
          <div className="card-header">
            <h2>📝 Add New Measurement</h2>
          </div>
          <MeasurementForm onSaved={load} />
        </div>

        {/* Stats Cards */}
        {latestMeasurement && (
          <div className="stats-grid">
            <div className="stat-card">
              <span className="stat-value">{latestMeasurement.bmi}</span>
              <span className="stat-label">Current BMI</span>
            </div>
            <div className="stat-card" style={{ background: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)' }}>
              <span className="stat-value">{latestMeasurement.bmr}</span>
              <span className="stat-label">BMR (cal)</span>
            </div>
            <div className="stat-card" style={{ background: 'linear-gradient(135deg, #10b981 0%, #059669 100%)' }}>
              <span className="stat-value">{latestMeasurement.daily_calories}</span>
              <span className="stat-label">Daily Calories</span>
            </div>
            <div className="stat-card" style={{ background: 'linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%)' }}>
              <span className="stat-value">{totalMeasurements}</span>
              <span className="stat-label">Total Records</span>
            </div>
          </div>
        )}

        {/* Recent Measurements Card */}
        <div className="card">
          <div className="card-header">
            <h2>📋 Recent Measurements</h2>
          </div>
          {error && <div className="alert alert-error">{error}</div>}
          {loading ? (
            <div className="loading">Loading your data</div>
          ) : (
            <ul className="measurements-list">
              {rows.length === 0 ? (
                <div className="empty-state">
                  <p>No measurements yet. Add your first one above!</p>
                </div>
              ) : (
                rows.slice(0, 10).map(r => (
                  <li key={r.id} className="measurement-item">
                    <span className="measurement-date">
                      {new Date(r.measurement_date || r.created_at).toLocaleDateString('en-US', { 
                        month: 'short', 
                        day: 'numeric', 
                        year: 'numeric' 
                      })}
                    </span>
                    <div className="measurement-data">
                      <span className="measurement-badge badge-bmi">
                        BMI: <strong>{r.bmi}</strong> ({r.bmi_category})
                      </span>
                      <span className="measurement-badge badge-bmr">
                        BMR: <strong>{r.bmr}</strong> cal
                      </span>
                      <span className="measurement-badge badge-calories">
                        Daily: <strong>{r.daily_calories}</strong> cal
                      </span>
                    </div>
                  </li>
                ))
              )}
            </ul>
          )}
        </div>

        {/* Trend Chart Card */}
        <div className="card">
          <div className="card-header">
            <h2>📈 30-Day BMI Trend</h2>
          </div>
          <div className="chart-container">
            <TrendChart />
          </div>
        </div>
      </div>
    </>
  );
}
```

#### frontend/src/components/MeasurementForm.jsx
```javascript
import React, { useState } from 'react';
import api from '../api';

export default function MF({ onSaved }) {
  const getTodayDate = () => new Date().toISOString().split('T')[0];
  const [f, sf] = useState({ 
    weightKg: 70, 
    heightCm: 175, 
    age: 30, 
    sex: 'male', 
    activity: 'moderate',
    measurementDate: getTodayDate()
  });
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(false);
  const [loading, setLoading] = useState(false);
  
  const sub = async e => {
    e.preventDefault();
    setError(null);
    setSuccess(false);
    setLoading(true);
    try {
      await api.post('/measurements', f);
      setSuccess(true);
      setTimeout(() => setSuccess(false), 3000);
      onSaved && onSaved();
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to save measurement');
    } finally {
      setLoading(false);
    }
  };
  
  return (
    <form onSubmit={sub}>
      {error && <div className="alert alert-error">{error}</div>}
      {success && <div className="alert alert-success">Measurement saved successfully!</div>}
      
      <div className="form-row">
        <div className="form-group">
          <label htmlFor="measurementDate">Measurement Date</label>
          <input 
            id="measurementDate"
            type="date"
            value={f.measurementDate} 
            onChange={e => sf({ ...f, measurementDate: e.target.value })}
            required
            max={new Date().toISOString().split('T')[0]}
          />
        </div>
      </div>
      
      <div className="form-row">
        <div className="form-group">
          <label htmlFor="weight">Weight (kg)</label>
          <input 
            id="weight"
            type="number" 
            value={f.weightKg} 
            onChange={e => sf({ ...f, weightKg: +e.target.value })}
            required
            min="1"
            max="500"
            step="0.1"
            placeholder="70"
          />
        </div>
        
        <div className="form-group">
          <label htmlFor="height">Height (cm)</label>
          <input 
            id="height"
            type="number"
            value={f.heightCm} 
            onChange={e => sf({ ...f, heightCm: +e.target.value })}
            required
            min="1"
            max="300"
            step="0.1"
            placeholder="175"
          />
        </div>
        
        <div className="form-group">
          <label htmlFor="age">Age (years)</label>
          <input 
            id="age"
            type="number"
            value={f.age} 
            onChange={e => sf({ ...f, age: +e.target.value })}
            required
            min="1"
            max="150"
            placeholder="30"
          />
        </div>
      </div>
      
      <div className="form-row">
        <div className="form-group">
          <label htmlFor="sex">Biological Sex</label>
          <select 
            id="sex"
            value={f.sex} 
            onChange={e => sf({ ...f, sex: e.target.value })}
            required
          >
            <option value="male">Male</option>
            <option value="female">Female</option>
          </select>
        </div>
        
        <div className="form-group">
          <label htmlFor="activity">Activity Level</label>
          <select 
            id="activity"
            value={f.activity} 
            onChange={e => sf({ ...f, activity: e.target.value })}
            required
          >
            <option value="sedentary">Sedentary (Little/No Exercise)</option>
            <option value="light">Light (1-3 days/week)</option>
            <option value="moderate">Moderate (3-5 days/week)</option>
            <option value="active">Active (6-7 days/week)</option>
            <option value="very_active">Very Active (2x per day)</option>
          </select>
        </div>
      </div>
      
      <button type="submit" disabled={loading}>
        {loading ? '⏳ Saving...' : '✓ Save Measurement'}
      </button>
    </form>
  );
}
```

#### frontend/src/components/TrendChart.jsx
```javascript
import React, { useEffect, useState } from 'react';
import { Line } from 'react-chartjs-2';
import api from '../api';
import { Chart as C, CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend } from 'chart.js';

C.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend);

export default function TC() {
  const [d, sd] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  
  useEffect(() => {
    setLoading(true);
    api.get('/measurements/trends')
      .then(r => {
        console.log('Trend data:', r.data);
        const rows = r.data.rows;
        if (rows && rows.length > 0) {
          sd({
            labels: rows.map(x => new Date(x.day).toLocaleDateString()),
            datasets: [{
              label: 'Average BMI',
              data: rows.map(x => parseFloat(x.avg_bmi)),
              borderColor: 'rgb(75, 192, 192)',
              backgroundColor: 'rgba(75, 192, 192, 0.2)',
              tension: 0.1
            }]
          });
        } else {
          setError(null); // Clear error if no data
        }
      })
      .catch(err => {
        console.error('Failed to load trends:', err);
        console.error('Error details:', err.response?.data);
        setError('Failed to load trend data');
      })
      .finally(() => setLoading(false));
  }, []);
  
  if (loading) return <div className="loading">Loading chart</div>;
  if (error) return <div className="alert alert-error">{error}</div>;
  if (!d) return <div className="empty-state"><p>No trend data available yet. Add measurements over multiple days to see trends!</p></div>;
  
  return <Line data={d} options={{
    responsive: true,
    plugins: {
      legend: { position: 'top' },
      title: { display: true, text: '30-Day BMI Trend' }
    }
  }} />;
}
```

#### frontend/src/index.css
```css
:root {
  --primary: #4f46e5;
  --primary-dark: #4338ca;
  --primary-light: #818cf8;
  --secondary: #10b981;
  --danger: #ef4444;
  --warning: #f59e0b;
  --gray-50: #f9fafb;
  --gray-100: #f3f4f6;
  --gray-200: #e5e7eb;
  --gray-300: #d1d5db;
  --gray-600: #4b5563;
  --gray-700: #374151;
  --gray-800: #1f2937;
  --gray-900: #111827;
  --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);
  --shadow: 0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1);
  --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
  --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);
}

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
    'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
  color: var(--gray-800);
  line-height: 1.6;
}

/* Header */
.app-header {
  background: rgba(255, 255, 255, 0.95);
  backdrop-filter: blur(10px);
  padding: 1.5rem 0;
  box-shadow: var(--shadow-md);
  margin-bottom: 2rem;
  border-bottom: 3px solid var(--primary);
}

.app-header h1 {
  color: var(--primary);
  font-size: 2.5rem;
  font-weight: 700;
  text-align: center;
  margin: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.75rem;
}

.app-header h1::before {
  content: "💪";
  font-size: 2.5rem;
}

.app-subtitle {
  text-align: center;
  color: var(--gray-600);
  font-size: 1rem;
  margin-top: 0.5rem;
}

/* Container */
.container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 1.5rem 3rem;
}

/* Card */
.card {
  background: white;
  border-radius: 16px;
  padding: 2rem;
  box-shadow: var(--shadow-lg);
  margin-bottom: 2rem;
  transition: transform 0.2s, box-shadow 0.2s;
}

.card:hover {
  transform: translateY(-2px);
  box-shadow: 0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1);
}

.card-header {
  border-bottom: 2px solid var(--gray-100);
  padding-bottom: 1rem;
  margin-bottom: 1.5rem;
}

.card-header h2 {
  color: var(--gray-800);
  font-size: 1.5rem;
  font-weight: 600;
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

/* Form Styles */
form {
  display: grid;
  gap: 1.5rem;
}

.form-row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 1.5rem;
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

label {
  font-weight: 600;
  color: var(--gray-700);
  font-size: 0.875rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

input,
select {
  padding: 0.75rem 1rem;
  border: 2px solid var(--gray-200);
  border-radius: 8px;
  font-size: 1rem;
  transition: all 0.2s;
  background: var(--gray-50);
  font-family: inherit;
}

input:focus,
select:focus {
  outline: none;
  border-color: var(--primary);
  background: white;
  box-shadow: 0 0 0 3px rgba(79, 70, 229, 0.1);
}

input:hover,
select:hover {
  border-color: var(--gray-300);
}

/* Buttons */
button {
  padding: 0.875rem 2rem;
  background: linear-gradient(135deg, var(--primary) 0%, var(--primary-dark) 100%);
  color: white;
  border: none;
  border-radius: 8px;
  font-size: 1rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s;
  box-shadow: var(--shadow);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

button:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: var(--shadow-lg);
  background: linear-gradient(135deg, var(--primary-dark) 0%, var(--primary) 100%);
}

button:active:not(:disabled) {
  transform: translateY(0);
}

button:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

/* Alert Messages */
.alert {
  padding: 1rem 1.25rem;
  border-radius: 8px;
  margin-bottom: 1.5rem;
  display: flex;
  align-items: center;
  gap: 0.75rem;
  font-weight: 500;
  animation: slideIn 0.3s ease-out;
}

@keyframes slideIn {
  from {
    opacity: 0;
    transform: translateY(-10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.alert-error {
  background-color: #fef2f2;
  color: #991b1b;
  border: 1px solid #fecaca;
}

.alert-error::before {
  content: "⚠️";
  font-size: 1.25rem;
}

.alert-success {
  background-color: #f0fdf4;
  color: #166534;
  border: 1px solid #bbf7d0;
}

.alert-success::before {
  content: "✓";
  font-size: 1.25rem;
  font-weight: bold;
}

/* Loading State */
.loading {
  text-align: center;
  padding: 3rem;
  color: var(--gray-600);
}

.loading::after {
  content: "";
  display: inline-block;
  width: 2rem;
  height: 2rem;
  border: 3px solid var(--gray-200);
  border-top-color: var(--primary);
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
  margin-left: 1rem;
  vertical-align: middle;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

/* Measurements List */
.measurements-list {
  list-style: none;
  display: grid;
  gap: 1rem;
}

.measurement-item {
  background: var(--gray-50);
  padding: 1.25rem;
  border-radius: 10px;
  border-left: 4px solid var(--primary);
  display: grid;
  grid-template-columns: auto 1fr auto;
  gap: 1rem;
  align-items: center;
  transition: all 0.2s;
}

.measurement-item:hover {
  background: white;
  box-shadow: var(--shadow-md);
  transform: translateX(4px);
}

.measurement-date {
  font-weight: 600;
  color: var(--primary);
  font-size: 0.875rem;
}

.measurement-data {
  display: flex;
  gap: 1.5rem;
  flex-wrap: wrap;
  align-items: center;
}

.measurement-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  padding: 0.375rem 0.75rem;
  background: white;
  border-radius: 6px;
  font-size: 0.875rem;
  font-weight: 600;
  box-shadow: var(--shadow-sm);
}

.badge-bmi {
  color: var(--primary);
}

.badge-bmr {
  color: #f59e0b;
}

.badge-calories {
  color: var(--secondary);
}

.empty-state {
  text-align: center;
  padding: 3rem;
  color: var(--gray-600);
  background: var(--gray-50);
  border-radius: 12px;
  border: 2px dashed var(--gray-300);
}

.empty-state::before {
  content: "📊";
  display: block;
  font-size: 3rem;
  margin-bottom: 1rem;
}

/* Chart Container */
.chart-container {
  padding: 1.5rem;
  background: var(--gray-50);
  border-radius: 12px;
  min-height: 300px;
}

/* Stats Grid */
.stats-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 1rem;
  margin-bottom: 1.5rem;
}

.stat-card {
  background: linear-gradient(135deg, var(--primary-light) 0%, var(--primary) 100%);
  color: white;
  padding: 1.5rem;
  border-radius: 12px;
  text-align: center;
  box-shadow: var(--shadow);
}

.stat-value {
  font-size: 2rem;
  font-weight: 700;
  display: block;
  margin-bottom: 0.25rem;
}

.stat-label {
  font-size: 0.875rem;
  opacity: 0.9;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

/* Responsive Design */
@media (max-width: 768px) {
  .app-header h1 {
    font-size: 2rem;
  }
  
  .card {
    padding: 1.5rem;
  }
  
  .form-row {
    grid-template-columns: 1fr;
  }
  
  .measurement-item {
    grid-template-columns: 1fr;
    text-align: center;
  }
  
  .measurement-data {
    justify-content: center;
  }
}

@media (max-width: 480px) {
  .container {
    padding: 0 1rem 2rem;
  }
  
  .card {
    padding: 1rem;
    border-radius: 12px;
  }
}
```

---

### 3. Configuration Files

#### .gitignore
```gitignore
# Node modules
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Environment variables
.env
.env.local
.env.production

# Build outputs
dist/
build/
*.tsbuildinfo

# Logs
logs/
*.log

# OS files
.DS_Store
Thumbs.db
*.swp
*.swo
*~

# IDE
.vscode/
.idea/
*.sublime-*

# PM2
.pm2/

# Test coverage
coverage/

# Temporary files
tmp/
temp/
```

---

### 4. Deployment Scripts

#### deploy.sh
```bash
#!/bin/bash

# BMI Health Tracker - Deployment Script for AWS EC2 Ubuntu
# This script automates the deployment process

set -e  # Exit on any error

echo "🚀 BMI Health Tracker Deployment Script"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   echo -e "${RED}Please do not run as root${NC}"
   exit 1
fi

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Check prerequisites
print_info "Checking prerequisites..."

# Check Node.js
if ! command -v node &> /dev/null; then
    print_error "Node.js is not installed"
    exit 1
fi
print_status "Node.js $(node -v) found"

# Check npm
if ! command -v npm &> /dev/null; then
    print_error "npm is not installed"
    exit 1
fi
print_status "npm $(npm -v) found"

# Check PostgreSQL
if ! command -v psql &> /dev/null; then
    print_error "PostgreSQL is not installed"
    exit 1
fi
print_status "PostgreSQL found"

# Check PM2
if ! command -v pm2 &> /dev/null; then
    print_info "PM2 not found. Installing..."
    npm install -g pm2
fi
print_status "PM2 found"

# Backend Setup
print_info "Setting up backend..."
cd backend

if [ ! -f .env ]; then
    print_error ".env file not found in backend directory"
    print_info "Please create .env file from .env.example"
    exit 1
fi
print_status ".env file exists"

# Install backend dependencies
print_info "Installing backend dependencies..."
npm install --production
print_status "Backend dependencies installed"

# Frontend Setup
print_info "Setting up frontend..."
cd ../frontend

# Install frontend dependencies
print_info "Installing frontend dependencies..."
npm install
print_status "Frontend dependencies installed"

# Build frontend
print_info "Building frontend for production..."
npm run build
print_status "Frontend built successfully"

# Deploy frontend
print_info "Deploying frontend to /var/www/bmi-health-tracker..."
sudo mkdir -p /var/www/bmi-health-tracker
sudo cp -r dist/* /var/www/bmi-health-tracker/
sudo chown -R www-data:www-data /var/www/bmi-health-tracker
print_status "Frontend deployed"

# Start backend with PM2
cd ../backend
print_info "Starting backend with PM2..."
pm2 delete bmi-backend 2>/dev/null || true
pm2 start src/server.js --name bmi-backend
pm2 save
print_status "Backend started with PM2"

# Setup PM2 startup
print_info "Configuring PM2 startup..."
sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u $USER --hp $HOME

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}✓ Deployment Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "Backend Status:"
pm2 status
echo ""
echo "Next Steps:"
echo "1. Verify nginx configuration: sudo nginx -t"
echo "2. Reload nginx: sudo systemctl reload nginx"
echo "3. Check PM2 logs: pm2 logs bmi-backend"
echo "4. Access your application at: http://YOUR_DOMAIN_OR_IP"
echo ""
```

#### setup-database.sh
```bash
#!/bin/bash

# Quick Database Setup Script for BMI Health Tracker

set -e

echo "🗄️  Database Setup for BMI Health Tracker"
echo "========================================"

# Database credentials
DB_USER="bmi_user"
DB_NAME="bmidb"

echo ""
echo "This script will:"
echo "1. Create PostgreSQL user: $DB_USER"
echo "2. Create database: $DB_NAME"
echo "3. Run migrations"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Get password
read -sp "Enter password for database user '$DB_USER': " DB_PASS
echo ""

# Create user
echo "Creating database user..."
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>/dev/null || echo "User may already exist"

# Create database
echo "Creating database..."
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || echo "Database may already exist"

# Grant privileges
echo "Granting privileges..."
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"

# Run migrations
echo "Running migrations..."
cd "$(dirname "$0")"
export PGPASSWORD=$DB_PASS
psql -U $DB_USER -d $DB_NAME -h localhost -f backend/migrations/001_create_measurements.sql

echo ""
echo "✓ Database setup complete!"
echo ""
echo "Your DATABASE_URL should be:"
echo "postgresql://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME"
echo ""
echo "Add this to your backend/.env file"
```

---

## API Endpoints

### Health Check
- **GET** `/health`
- Returns: `{ status: 'ok', environment: 'production' }`

### Create Measurement
- **POST** `/api/measurements`
- Body: `{ weightKg, heightCm, age, sex, activity }`
- Returns: `{ measurement: {...} }`

### Get All Measurements
- **GET** `/api/measurements`
- Returns: `{ rows: [...] }`

### Get 30-Day Trends
- **GET** `/api/measurements/trends`
- Returns: `{ rows: [{ day, avg_bmi }] }`

---

## Health Calculations Formulas

### BMI (Body Mass Index)
```
BMI = weight_kg / (height_m)²
```

### BMI Categories
- Underweight: BMI < 18.5
- Normal: 18.5 ≤ BMI < 25
- Overweight: 25 ≤ BMI < 30
- Obese: BMI ≥ 30

### BMR (Basal Metabolic Rate) - Mifflin-St Jeor
```
Male:   BMR = 10 × weight + 6.25 × height - 5 × age + 5
Female: BMR = 10 × weight + 6.25 × height - 5 × age - 161
```

### Daily Calories
```
Daily Calories = BMR × Activity Multiplier

Activity Multipliers:
- Sedentary (little/no exercise): 1.2
- Light (1-3 days/week): 1.375
- Moderate (3-5 days/week): 1.55
- Active (6-7 days/week): 1.725
- Very Active (2x per day): 1.9
```

---

## Environment Variables

### Backend (.env)
```env
PORT=3000
DATABASE_URL=postgresql://bmi_user:YOUR_PASSWORD@localhost:5432/bmidb
NODE_ENV=production
FRONTEND_URL=http://localhost
```

---

## Development Setup

```bash
# Backend
cd backend
npm install
cp .env.example .env
# Edit .env with database credentials
npm run dev  # Runs on port 3000

# Frontend (in new terminal)
cd frontend
npm install
npm run dev  # Runs on port 5173
```

---

## Production Deployment

1. **Setup Database**
   ```bash
   chmod +x setup-database.sh
   ./setup-database.sh
   ```

2. **Configure Environment**
   ```bash
   cd backend
   cp .env.example .env
   nano .env  # Add your database password
   ```

3. **Deploy Application**
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

4. **Configure Nginx**
   - Follow Part 6 in BMI_Health_Tracker_Deployment_Readme.md

---

## Nginx Configuration Example

```nginx
server {
    listen 80;
    server_name YOUR_DOMAIN_OR_IP;

    root /var/www/bmi-health-tracker;
    index index.html;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

---

## Project Recreation Instructions

If you only have this AGENT.md file:

1. **Create Directory Structure**
   ```bash
   mkdir -p bmi-health-tracker/{backend/{src,migrations},frontend/src/components}
   cd bmi-health-tracker
   ```

2. **Copy All File Contents**
   - Copy each file's content from sections above
   - Create files with exact names and paths
   - Pay attention to file extensions (.js, .jsx, .json, .sql, .sh)

3. **Make Scripts Executable**
   ```bash
   chmod +x deploy.sh setup-database.sh
   ```

4. **Install Dependencies**
   ```bash
   cd backend && npm install
   cd ../frontend && npm install
   ```

5. **Setup Database**
   ```bash
   ./setup-database.sh
   ```

6. **Configure Environment**
   ```bash
   cd backend
   cp .env.example .env
   # Edit .env with your database credentials
   ```

7. **Test Locally**
   ```bash
   # Terminal 1
   cd backend && npm run dev
   
   # Terminal 2
   cd frontend && npm run dev
   ```

8. **Deploy to Production**
   - Follow BMI_Health_Tracker_Deployment_Readme.md

---

## Verification Tests

```bash
# Backend health
curl http://localhost:3000/health

# Get measurements
curl http://localhost:3000/api/measurements

# PM2 status
pm2 status

# Database connection
psql -U bmi_user -d bmidb -h localhost -c "SELECT COUNT(*) FROM measurements;"
```

---

## Security Features

- ✅ SQL Injection Protection (parameterized queries)
- ✅ Environment-based CORS
- ✅ Input validation (frontend, backend, database)
- ✅ Request timeouts (10s)
- ✅ Connection pool limits (max 20)
- ✅ Error sanitization
- ✅ Credentials in .env (not hardcoded)

---

## Documentation References

- **README.md** - Quick start guide
- **CONNECTIVITY.md** - 3-tier architecture details
- **BMI_Health_Tracker_Deployment_Readme.md** - Complete AWS deployment (13 parts)
- **DEPLOYMENT_CHECKLIST.md** - Pre-deployment checklist
- **DEPLOYMENT_READY.md** - Quick deployment summary
- **FINAL_AUDIT.md** - Comprehensive audit report

---

## Quick Commands Reference

```bash
# Backend Development
npm run dev          # Start with nodemon (auto-reload)
npm start            # Start production server

# Frontend Development
npm run dev          # Vite dev server
npm run build        # Production build
npm run preview      # Preview production build

# PM2 Management
pm2 start ecosystem.config.js
pm2 status
pm2 logs bmi-backend
pm2 restart bmi-backend
pm2 stop bmi-backend
pm2 delete bmi-backend

# Database
psql -U bmi_user -d bmidb -h localhost
\dt                  # List tables
\d measurements      # Describe table
SELECT * FROM measurements;
\q                   # Quit

# Nginx
sudo nginx -t                    # Test config
sudo systemctl reload nginx      # Reload
sudo systemctl restart nginx     # Restart
sudo tail -f /var/log/nginx/bmi-error.log
```

---

## Troubleshooting

### Backend Won't Start
```bash
pm2 logs bmi-backend
# Check .env file exists and has correct DATABASE_URL
# Ensure PostgreSQL is running: sudo systemctl status postgresql
```

### Database Connection Failed
```bash
# Test connection manually
psql -U bmi_user -d bmidb -h localhost
# Check DATABASE_URL format: postgresql://user:pass@host:port/database
```

### Frontend Build Fails
```bash
# Clear node_modules and reinstall
rm -rf node_modules package-lock.json
npm install
npm run build
```

### Nginx 502 Error
```bash
# Ensure backend is running
curl http://localhost:3000/health
pm2 status
# Check Nginx logs
sudo tail -f /var/log/nginx/bmi-error.log
```

---

**Last Updated:** December 15, 2025  
**Version:** 4.0 - Complete with Measurement Date Feature  
**Status:** ✅ Production Ready - Can recreate entire project from this file

---

## Database Schema

### measurements table
```sql
id              SERIAL PRIMARY KEY
weight_kg       NUMERIC NOT NULL
height_cm       NUMERIC NOT NULL
age             INTEGER NOT NULL
sex             VARCHAR(10) NOT NULL
activity_level  VARCHAR(30)
bmi             NUMERIC NOT NULL
bmi_category    VARCHAR(30)
bmr             INTEGER
daily_calories  INTEGER
measurement_date DATE NOT NULL DEFAULT CURRENT_DATE
created_at      TIMESTAMPTZ DEFAULT now()
```

---

## API Endpoints

### POST `/api/measurements`
Create a new measurement
- **Body**: `{ weightKg, heightCm, age, sex, activity, measurementDate? }`
  - `measurementDate` is optional, defaults to current date
- **Response**: `{ measurement: {...} }`

### GET `/api/measurements`
Get all measurements (ordered by measurement_date DESC, then created_at DESC)
- **Response**: `{ rows: [...] }`

### GET `/api/measurements/trends`
Get 30-day average BMI by day (based on measurement_date)
- **Response**: `{ rows: [{ day, avg_bmi }] }`

---

## Development Setup

### Prerequisites
- Node.js (LTS version via NVM)
- PostgreSQL
- Git

### Backend Setup
```bash
cd backend
npm install
cp .env.example .env
# Edit .env with your DATABASE_URL
psql -U postgres -f migrations/001_create_measurements.sql
psql -U postgres -f migrations/002_add_measurement_date.sql
npm run dev  # Runs on port 3000
```

### Frontend Setup
```bash
cd frontend
npm install
npm run dev  # Runs on port 5173
```

### Environment Variables (.env)
```
PORT=3000
DATABASE_URL=postgresql://bmi_user:password@localhost:5432/bmidb
NODE_ENV=production
```

---

## Key Implementation Details

### Vite Proxy Configuration
The frontend proxies API requests to avoid CORS issues during development:
```javascript
proxy: { '/api': { target: 'http://localhost:3000' } }
```

### Error Handling
- Backend: try-catch with 500 error responses
- Frontend: try-catch with user-friendly error messages
- Loading states on async operations

### Form Validation
- All fields required
- Number inputs with min/max constraints
- Dropdown validation for sex and activity level

### Data Flow
1. User submits form → POST `/api/measurements`
2. Backend calculates BMI/BMR/calories → saves to DB
3. Frontend refreshes measurement list
4. TrendChart fetches 30-day data independently

---

## Deployment

Refer to [BMI_Health_Tracker_Deployment_Readme.md](BMI_Health_Tracker_Deployment_Readme.md) for complete Ubuntu EC2 deployment instructions including:
- Nginx reverse proxy setup
- PostgreSQL configuration
- PM2 process management
- Static file serving
- Firewall configuration

---

## Future Enhancements
- User authentication & multi-user support
- Goal setting and progress tracking
- Export data to CSV/PDF
- Mobile responsive design improvements
- Weight/BMI goals with notifications
- Meal planning integration

---

## License
MIT

---

**Last Updated**: December 15, 2025

---
## 🧑‍💻 Author
**Md. Sarowar Alam**  
Lead DevOps Engineer, Hogarth Worldwide  
📧 Email: sarowar@hotmail.com  
🔗 LinkedIn: [linkedin.com/in/sarowar](https://www.linkedin.com/in/sarowar/)  
--- 