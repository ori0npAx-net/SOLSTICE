-- 3_queries.sql
-- 15 questions we ask the solar tracker database, plus 1 saved view.
-- Paste ONE query at a time into phpMyAdmin's SQL tab, then click Go.
-- SELECT queries only look at data, so they are safe to run any number of times.
USE solar_tracker_db;

-- ============================================================
-- PART A: BASIC LOOKUPS  (WHERE, ORDER BY, LIMIT, BETWEEN)
-- ============================================================

-- Q1: Which panels are currently Active?
SELECT panel_id, model_name, capacity_watts, status
FROM SOLAR_PANEL
WHERE status = 'Active';

-- Q2: What are the 3 brightest light readings ever recorded?
SELECT sensor_id, panel_id, light_intensity_lux, recorded_at
FROM SUN_SENSOR
ORDER BY light_intensity_lux DESC
LIMIT 3;

-- Q3: What was the power output during the middle of the day (10:00 to 16:00)?
SELECT reading_id, panel_id, power_output_w, recorded_at
FROM ENERGY_READING
WHERE recorded_at BETWEEN '2026-10-01 10:00:00' AND '2026-10-01 16:00:00'
ORDER BY recorded_at;

-- ============================================================
-- PART B: AGGREGATION  (COUNT, MAX, AVG, GROUP BY, HAVING)
-- ============================================================

-- Q4: How many power readings does each panel have?
SELECT panel_id, COUNT(*) AS number_of_readings
FROM ENERGY_READING
GROUP BY panel_id;

-- Q5: For each panel, what was the peak and average power?
SELECT panel_id,
       MAX(power_output_w) AS peak_power_w,
       ROUND(AVG(power_output_w), 2) AS average_power_w
FROM ENERGY_READING
GROUP BY panel_id;

-- Q6: What was each panel's average power on each day?
SELECT panel_id,
       DATE(recorded_at) AS day,
       ROUND(AVG(power_output_w), 2) AS average_power_w
FROM ENERGY_READING
GROUP BY panel_id, DATE(recorded_at);

-- Q7: Which panels average more than 50 W? (HAVING filters the groups)
SELECT panel_id, ROUND(AVG(power_output_w), 2) AS average_power_w
FROM ENERGY_READING
GROUP BY panel_id
HAVING AVG(power_output_w) > 50;

-- ============================================================
-- PART C: JOINS  (combining 2, 3 and 4 tables)
-- ============================================================

-- Q8: Panel performance with the panel's name and status
SELECT p.model_name,
       p.status,
       MAX(e.power_output_w) AS peak_power_w,
       ROUND(AVG(e.power_output_w), 2) AS average_power_w
FROM SOLAR_PANEL p
JOIN ENERGY_READING e ON e.panel_id = p.panel_id
GROUP BY p.model_name, p.status;

-- Q9: How many motors does each panel have? (LEFT JOIN keeps panels with 0 motors)
SELECT p.model_name, COUNT(m.motor_id) AS number_of_motors
FROM SOLAR_PANEL p
LEFT JOIN ACTUATOR_MOTOR m ON m.panel_id = p.panel_id
GROUP BY p.panel_id, p.model_name;

-- Q10: Which sensor reading triggered each panel movement?  (4 tables)
SELECT mv.executed_at       AS moved_at,
       p.model_name,
       am.motor_type,
       s.recorded_at        AS sensor_time,
       s.light_intensity_lux,
       mv.target_angle,
       mv.power_consumed_wh
FROM MOVEMENT_LOG mv
JOIN ACTUATOR_MOTOR am ON mv.motor_id  = am.motor_id
JOIN SUN_SENSOR s      ON mv.sensor_id = s.sensor_id
JOIN SOLAR_PANEL p     ON am.panel_id  = p.panel_id
ORDER BY mv.executed_at;

-- Q11: How much power did the motors use per panel, and how many moves was that?
SELECT p.model_name,
       COUNT(mv.log_id)               AS number_of_moves,
       ROUND(SUM(mv.power_consumed_wh), 3) AS total_motor_power_wh
FROM MOVEMENT_LOG mv
JOIN ACTUATOR_MOTOR am ON mv.motor_id = am.motor_id
JOIN SOLAR_PANEL p     ON am.panel_id = p.panel_id
GROUP BY p.panel_id, p.model_name;

-- Q12: Does more light mean more power? (light and power at the same moment)
SELECT s.panel_id,
       s.recorded_at,
       s.light_intensity_lux,
       e.power_output_w
FROM SUN_SENSOR s
JOIN ENERGY_READING e
  ON e.panel_id = s.panel_id AND e.recorded_at = s.recorded_at
ORDER BY s.panel_id, s.light_intensity_lux DESC;

-- ============================================================
-- PART D: ADVANCED  (subquery, CASE, finding "missing" rows)
-- ============================================================

-- Q13: When and where was the single highest power reading? (subquery)
SELECT e.panel_id, p.model_name, e.power_output_w, e.recorded_at
FROM ENERGY_READING e
JOIN SOLAR_PANEL p ON p.panel_id = e.panel_id
WHERE e.power_output_w = (SELECT MAX(power_output_w) FROM ENERGY_READING);

-- Q14: Label every reading as Low, Medium or High output (CASE)
SELECT reading_id, panel_id, power_output_w,
       CASE
         WHEN power_output_w < 25 THEN 'Low'
         WHEN power_output_w < 70 THEN 'Medium'
         ELSE 'High'
       END AS output_level
FROM ENERGY_READING
ORDER BY recorded_at;

-- Q15: Which sensor readings did NOT cause any movement? (LEFT JOIN ... IS NULL)
SELECT s.sensor_id, s.panel_id, s.light_intensity_lux, s.recorded_at
FROM SUN_SENSOR s
LEFT JOIN MOVEMENT_LOG mv ON mv.sensor_id = s.sensor_id
WHERE mv.log_id IS NULL;

-- ============================================================
-- SAVED VIEW: panel performance, openable like a table (safe to re-run)
-- ============================================================
CREATE OR REPLACE VIEW panel_performance AS
SELECT p.model_name,
       p.status,
       MAX(e.power_output_w) AS peak_power_w,
       ROUND(AVG(e.power_output_w), 2) AS average_power_w
FROM SOLAR_PANEL p
JOIN ENERGY_READING e ON e.panel_id = p.panel_id
GROUP BY p.model_name, p.status;
