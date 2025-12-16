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
            <h2>Add New Measurement</h2>
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
            <h2>Recent Measurements</h2>
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
            <h2>30-Day BMI Trend</h2>
          </div>
          <div className="chart-container">
            <TrendChart />
          </div>
        </div>
      </div>
    </>
  );
}