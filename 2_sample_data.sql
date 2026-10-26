-- 2_sample_data.sql
-- Fake test data for one day (Oct 1). Run ONCE, on empty tables only.
-- Running it twice doubles every row.
USE solar_tracker_db;

INSERT INTO SOLAR_PANEL (model_name, capacity_watts, status) VALUES
('SunMax 300W', 300.00, 'Active'),
('SunMax 250W', 250.00, 'Maintenance');

INSERT INTO SUN_SENSOR (panel_id, light_intensity_lux, sun_azimuth_angle, sun_elevation_angle, recorded_at) VALUES
(1, 1200.50, 95.20, 20.10, '2026-10-01 07:00:00'),
(1, 4500.75, 110.40, 45.30, '2026-10-01 10:00:00'),
(1, 8200.00, 180.00, 68.90, '2026-10-01 13:00:00'),
(1, 5300.25, 230.60, 42.10, '2026-10-01 16:00:00'),
(1, 900.00,  260.80, 12.50, '2026-10-01 18:30:00'),
(2, 1100.00, 93.00, 19.50, '2026-10-01 07:00:00'),
(2, 4100.30, 112.00, 44.00, '2026-10-01 10:00:00');

INSERT INTO ACTUATOR_MOTOR (panel_id, motor_type, current_tilt_angle) VALUES
(1, 'Horizontal', 180.00),
(1, 'Vertical', 68.90),
(2, 'Horizontal', 112.00);

INSERT INTO MOVEMENT_LOG (motor_id, sensor_id, target_angle, power_consumed_wh, executed_at) VALUES
(1, 2, 110.40, 0.045, '2026-10-01 10:00:05'),
(2, 2, 45.30,  0.038, '2026-10-01 10:00:07'),
(1, 3, 180.00, 0.050, '2026-10-01 13:00:05'),
(2, 3, 68.90,  0.041, '2026-10-01 13:00:08'),
(1, 4, 230.60, 0.047, '2026-10-01 16:00:04'),
(3, 6, 93.00,  0.039, '2026-10-01 07:00:06');

INSERT INTO ENERGY_READING (panel_id, voltage_v, current_a, recorded_at) VALUES
(1, 18.20, 1.10, '2026-10-01 07:00:00'),
(1, 19.80, 3.40, '2026-10-01 10:00:00'),
(1, 20.50, 5.20, '2026-10-01 13:00:00'),
(1, 19.90, 3.80, '2026-10-01 16:00:00'),
(1, 17.50, 0.90, '2026-10-01 18:30:00'),
(2, 17.90, 1.05, '2026-10-01 07:00:00'),
(2, 19.20, 3.10, '2026-10-01 10:00:00');
