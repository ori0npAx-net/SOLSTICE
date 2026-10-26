# Dual-Axis Solar Tracker: DBMS Project

A database-backed monitoring system for a dual-axis solar tracker.
**Database** (MariaDB / XAMPP) + **Backend** (Java) + **Frontend** (web page).

## How the parts connect

```
Sensor / Simulator --POST--> Java backend (Server.java) --SQL--> Database (solar_tracker_db)
                                   ^                                      |
Web page (browser) ----GET---------+<-------------------------------------+
```

## Folder contents

| File / folder | What it is |
|---|---|
| `0_reset.sql` | Deletes the database (clean start) |
| `1_schema.sql` | Creates the 5 tables and indexes |
| `2_sample_data.sql` | One day of sample data |
| `3_queries.sql` | 15 queries + the `panel_performance` view |
| `4_app_user.sql` | Limited user `solar_app` (SELECT + INSERT only) |
| `Backend/Connect.java` | Connection test |
| `Backend/Server.java` | Web server + API |
| `Backend/Simulator.java` | Pretend sensor that sends readings |
| `Backend/web/` | The website (frontend files go here) |
| `Backend/lib/` | MariaDB JDBC driver (.jar) |

## How to run

1. Start **XAMPP** (Apache and MySQL).
2. In phpMyAdmin, run `1_schema`, `2_sample_data`, `3_queries`, and `4_app_user` in order. Run `0_reset` only if you intentionally want to delete and recreate the database.
3. In a terminal opened in this folder, start the server:
   `java -cp "Backend/lib/*" Backend/Server.java`
4. Open **http://localhost:8080** in Chrome.
5. To send fake sensor readings, open a second terminal in this folder and run:
   `java -cp "Backend/lib/*" Backend/Simulator.java`
   (the dashboard updates by itself every 5 seconds)

## API (what the frontend can ask for)

| Address | Method | Returns / does |
|---|---|---|
| `/api/health` | GET | Database connection plus sensor and movement row counts |
| `/api/panels` | GET | Panels with capacity, status, latest power and latest reading time |
| `/api/summary` | GET | Peak and average power per panel |
| `/api/readings?panel=1` | GET | Readings of one panel |
| `/api/readings` | POST | Saves a reading. Body: `panel=1&voltage=18.5&current=3.2` |

## For the frontend

The dashboard is `Backend/web/index.html`; the Java server serves it at `http://localhost:8080`. Color controls live at `http://localhost:8080/settings`.
It fetches `/api/panels`, `/api/summary`, `/api/readings?panel=1`, and `/api/health` from the same Java server and refreshes every five seconds. The dashboard uses the existing MariaDB tables and `panel_performance` view; no separate Node service or database is needed.
The Settings page previews nine solid color steps between two chosen colors. Saving applies that palette to the dashboard in this browser.

## Verified local setup

The project schema, one-time sample rows, performance view, and `solar_app` account were installed in XAMPP MariaDB. `Backend/Connect.java` connected successfully, and the Java API returned the panel list, performance summary, health counts, and saved readings. The sample readings are dated October 1, 2026, so these are historical sample values rather than current live sensor measurements.

## Security notes

- Server listens on `127.0.0.1` only (this computer).
- The backend logs in as `solar_app`, which can only SELECT and INSERT (no DELETE, DROP, ALTER).
- All SQL uses `?` placeholders (prepared statements) against SQL injection.
- Inputs are validated (numbers and ranges) before saving.
- Database-provided panel labels are inserted as text rather than interpreted as HTML.
