# Solstice — date-based solar tracking simulation

A Java/MariaDB dashboard connected to a Godot 4 simulation of a **4 x 4 field of sixteen 300 W panels**. The simulation includes dual-axis tracking, clouds, rain, dust, bird droppings, cleaning, Offline panels, and a continuous calendar.

## Start on Windows

1. Copy/download the **complete repository**, including `Backend/`, `GodotSimulation/`, the JDBC driver and all SQL files.
2. Install Godot 4.4+ (set `GODOT_EXE` if it is outside Downloads or PATH).
3. Double-click `GodotSimulation/Launch.cmd`.
4. Open http://localhost:8080 for the dashboard.

The first launch downloads and verifies missing portable Java 21 and MariaDB runtimes. Internet access is needed for that setup. Runtime binaries, database files, and logs stay under `GodotSimulation/.runtime/` and `logs/`, excluded from Git. No administrator privileges or system PATH changes are required.

The launcher initializes a fresh local database, seeds the field, applies the additive `6_simulation_history.sql` migration, and restarts its own Java process if the server source changed. An external database/server already on the configured ports must be migrated/restarted by its administrator; the launcher only maintains services it owns.

For an existing external MariaDB database, run `6_simulation_history.sql` before starting the updated Java server. For a fresh manual setup, run `1_schema.sql`, `2_sample_data.sql`, `3_queries.sql`, `4_app_user.sql`, and `6_simulation_history.sql`; then seed field panels using `GodotSimulation/Create-Field.ps1` with the project-local setup, or have the database administrator add the sixteen field rows and mark `is_simulation=TRUE`. Never run `0_reset.sql` unless intentionally deleting the entire database.

## Continuous dates and saved history

The simulation starts on the current PKT date at 08:00 once, then resumes saved state on subsequent launches. A day duration of 180 real seconds represents a full 24 simulated hours, including zero output at night. Midnight advances the calendar; **Next day** moves to the following date at 06:00 without clearing prior readings, dirt, energy totals, or the recent chart.

The simulator pauses while closed; it does not fabricate power readings for elapsed real-world time while it was not running. Local state autosaves every two seconds. After each completed field sweep, an append-only database checkpoint preserves the clock, weather, dirt, per-panel lifetime energy, motor orientation, and rolling chart. A fresh client can recover that checkpoint; a newer local save takes precedence.

Each reading keeps two distinct timestamps:

- `simulated_at`: the simulation's civil date/time in PKT, including accelerated future dates.
- `recorded_at`: the real time the database received the sample.

Cloud cover, rain intensity, dust and bird contamination are stored alongside the electrical values. The database still calculates power as voltage x current. Older readings retain their original timestamps and have a NULL `simulated_at`; their past simulation date cannot be reconstructed accurately.

## Dashboard

The dashboard counts only the **sixteen simulation panels**, not the two original SunMax sample panels. Those sample rows/history remain in the database with `is_simulation=FALSE` and are excluded from the simulation register and statistics.

Use the clock selector for **Simulation history**, **Earlier legacy history**, or **Both clocks**. Use the date selector for a recorded date, latest day, or all dates. The chart is spaced by elapsed time. The saved-reading table shows timestamps and weather/contamination, and **Download CSV** exports all readings in the selected panel/date/clock range. Per-panel performance statistics use that same date/clock range. The panel register always shows the latest received sample.

The layout refreshes every five seconds and retains a manually selected historical date during refresh. The timeline card shows the latest stored simulation checkpoint and its real reception time.

## Data model and APIs

The original five tables remain. The migration adds an `is_simulation` panel flag, nullable simulation/environment columns on `ENERGY_READING`, an index, and an append-only `SIMULATION_STATE` checkpoint table. Existing data is retained. The backend's account continues to use SELECT/INSERT only.

| API | Purpose |
| --- | --- |
| `GET /api/panels` | Sixteen field panels and latest received output |
| `GET /api/health` | Database connection and existing sensor/movement counts |
| `GET /api/days?clock=simulation` | Available recorded dates and counts |
| `GET /api/readings?panel=3&date=2026-10-26&clock=simulation` | One panel's filtered history |
| `GET /api/summary?date=2026-10-26&clock=simulation` | Per-panel peak/mean/count in that range |
| `POST /api/readings` | Append voltage/current, simulated_at, cloud_cover, rain_intensity, dust_level, bird_level |
| `GET /api/simulation-state` | Latest checkpoint |
| `POST /api/simulation-state` | Append a form-encoded simulated_at and JSON state |

`date` is optional; without it all dates are returned. `clock` accepts `simulation`, `legacy`, or omission for both. Existing voltage/current-only simulator requests still work and are recorded as legacy-clock values. Timestamps and weather ranges are validated; prepared statements bind submitted values.

## Verification

Godot tests are in `GodotSimulation/tests/`: solar calculations, environmental losses, scene behavior, calendar/leap-day rollover, local persistence, and database recovery. `--field-test` intentionally saves one sixteen-panel sweep and verifies acknowledgements.

`Backend/tests/history_api_test.cjs` verifies date separation across midnight, timestamp/weather storage, history queries, field scope and validation. It removes only its own test readings using the local database setup account. `Backend/tests/dashboard_test.cjs` uses Playwright/Chrome to verify history filters, CSV, sixteen registered panels and desktop/mobile layout.

See `GodotSimulation/README.md` for weather controls and model assumptions. Close Godot and run `GodotSimulation/Stop-Services.ps1` to stop only the services started by the launcher.
