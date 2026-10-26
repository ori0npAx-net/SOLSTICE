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
2. In phpMyAdmin, run the SQL files in order: `0_reset`, `1_schema`, `2_sample_data`, `3_queries`, `4_app_user`.
3. In a terminal opened in this folder, start the server:
   `java -cp "Backend/lib/*" Backend/Server.java`
4. Open **http://localhost:8080** in Chrome.
5. To send fake sensor readings, open a second terminal in this folder and run:
   `java -cp "Backend/lib/*" Backend/Simulator.java`
   (the dashboard updates by itself every 5 seconds)

## API (what the frontend can ask for)

| Address | Method | Returns / does |
|---|---|---|
| `/api/panels` | GET | All panels |
| `/api/summary` | GET | Peak and average power per panel |
| `/api/readings?panel=1` | GET | Readings of one panel |
| `/api/readings` | POST | Saves a reading. Body: `panel=1&voltage=18.5&current=3.2` |

## For the frontend

Put the frontend files in `Backend/web/` (the main page must be called `index.html`).
Fetch data using addresses like `/api/panels` (no domain in front).

## Security notes

- Server listens on `127.0.0.1` only (this computer).
- The backend logs in as `solar_app`, which can only SELECT and INSERT (no DELETE, DROP, ALTER).
- All SQL uses `?` placeholders (prepared statements) against SQL injection.
- Inputs are validated (numbers and ranges) before saving.
- Database text is shown with `textContent`, never `innerHTML`.
