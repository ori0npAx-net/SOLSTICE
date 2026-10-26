-- 4_app_user.sql
-- Creates a limited database user for the Java backend (instead of using root).
-- This user can READ everything and ADD new rows, but cannot delete data,
-- change table structure, or touch any other database.
-- Safe to re-run.

CREATE USER IF NOT EXISTS 'solar_app'@'localhost' IDENTIFIED BY 'SolarApp#2026';

GRANT SELECT, INSERT ON solar_tracker_db.* TO 'solar_app'@'localhost';

FLUSH PRIVILEGES;
