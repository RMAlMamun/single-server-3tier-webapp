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
