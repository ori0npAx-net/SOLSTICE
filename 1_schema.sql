-- 1_schema.sql
-- Builds the database and the 5 tables. Run AFTER 0_reset.sql.

CREATE DATABASE IF NOT EXISTS solar_tracker_db;
USE solar_tracker_db;

-- 1. SOLAR_PANEL: the physical panel
CREATE TABLE SOLAR_PANEL (
    panel_id        INT AUTO_INCREMENT PRIMARY KEY,
    model_name      VARCHAR(100) NOT NULL,
    capacity_watts  DECIMAL(6,2) NOT NULL CHECK (capacity_watts > 0),
    status          ENUM('Active', 'Maintenance', 'Offline') NOT NULL DEFAULT 'Active',
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. SUN_SENSOR: light sensor readings for a panel
CREATE TABLE SUN_SENSOR (
    sensor_id           INT AUTO_INCREMENT PRIMARY KEY,
    panel_id            INT NOT NULL,
    light_intensity_lux DECIMAL(8,2) NOT NULL,
    sun_azimuth_angle   DECIMAL(5,2),
    sun_elevation_angle DECIMAL(5,2),
    recorded_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (panel_id) REFERENCES SOLAR_PANEL(panel_id) ON DELETE CASCADE
);

-- 3. ACTUATOR_MOTOR: motors that rotate the panel
CREATE TABLE ACTUATOR_MOTOR (
    motor_id            INT AUTO_INCREMENT PRIMARY KEY,
    panel_id            INT NOT NULL,
    motor_type          ENUM('Horizontal', 'Vertical') NOT NULL,
    current_tilt_angle  DECIMAL(5,2) NOT NULL DEFAULT 0,
    FOREIGN KEY (panel_id) REFERENCES SOLAR_PANEL(panel_id) ON DELETE CASCADE
);

-- 4. MOVEMENT_LOG: every rotation, linked to the motor and the sensor reading that caused it
CREATE TABLE MOVEMENT_LOG (
    log_id              INT AUTO_INCREMENT PRIMARY KEY,
    motor_id            INT NOT NULL,
    sensor_id           INT NOT NULL,
    target_angle        DECIMAL(5,2) NOT NULL,
    power_consumed_wh   DECIMAL(6,3) DEFAULT 0,
    executed_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (motor_id) REFERENCES ACTUATOR_MOTOR(motor_id) ON DELETE CASCADE,
    FOREIGN KEY (sensor_id) REFERENCES SUN_SENSOR(sensor_id) ON DELETE CASCADE
);

-- 5. ENERGY_READING: power output over time (power_output_w is auto-calculated)
CREATE TABLE ENERGY_READING (
    reading_id      INT AUTO_INCREMENT PRIMARY KEY,
    panel_id        INT NOT NULL,
    voltage_v       DECIMAL(6,2) NOT NULL,
    current_a       DECIMAL(6,2) NOT NULL,
    power_output_w  DECIMAL(8,2) GENERATED ALWAYS AS (voltage_v * current_a) STORED,
    recorded_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (panel_id) REFERENCES SOLAR_PANEL(panel_id) ON DELETE CASCADE
);

-- Indexes for fast lookups by panel and time
CREATE INDEX idx_energy_panel_time ON ENERGY_READING(panel_id, recorded_at);
CREATE INDEX idx_sensor_panel_time ON SUN_SENSOR(panel_id, recorded_at);
CREATE INDEX idx_movement_time ON MOVEMENT_LOG(executed_at);
