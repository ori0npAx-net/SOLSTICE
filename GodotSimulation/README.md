# Solstice — 16 x 16 Godot solar field

A separate Godot 4 simulation with **256 individual 300 W panels**. The original frontend, Java backend, database schema, and SQL files are unchanged.

## Start

Double-click **Launch.cmd** to start the local database, original Java backend, and Godot window. The existing dashboard is at http://localhost:8080.

**On another PC:** copy/download the complete repository, including `Backend/`, the original SQL files, and this folder. Install Godot 4.4+ first. Double-click `GodotSimulation/Launch.cmd`; missing Java/MariaDB runtimes download automatically on first launch, and a newly created local database automatically receives the 256-panel field. Keep internet access available during this first setup. You do not need to upload `.runtime/`, `.godot/`, or `logs/`.

To edit, import `project.godot` in Godot and press F5. Java 21 and MariaDB 11.4.5 are installed locally in `.runtime/`; Godot 4.7.2 is in Downloads. No system PATH changes were needed.

## The field

- Exactly 16 rows by 16 columns, one database panel per visible panel.
- Each panel is 300 W: 76.8 kW total installed capacity.
- Blue panels are Active and track the moving sun on two axes.
- Red panels are Offline, remain parked, and save zero voltage/current/power.
- The current random selection contains **192 Active and 64 Offline panels**.
- Names identify position, such as `Godot Field R01 C01`.
- The original two sample panels and their history are preserved separately.
- Offline selection persists in the database; restarting does not reshuffle it.
- The fixed-panel comparison is calculated locally, without adding another 256 panels.

## Controls

| Control | Behavior |
| --- | --- |
| Time | Scrub the illustrative 06:00–18:00 sun path |
| Day duration | Real seconds required for 12 simulated daylight hours |
| Clouds | Attenuate sunlight and power |
| Tracking | Disable to hold the active motors while the sun continues moving |
| Pause | Stop time, motor movement, energy integration, and new sends |
| New day | Reset local time/energy/chart; preserve database history and statuses |
| Panel menu | Inspect any individual field panel, including Offline panels |
| Save whole field | Enable/disable database submissions |
| Drag / scroll | Orbit / zoom |

The large watt/voltage/current readout and session energy refer to the selected panel. The chart and kW heading show the combined Active field output versus the equivalent fixed field. Offline panels contribute zero to both.

## Saving through the existing API

Godot fetches panel IDs/statuses from `GET /api/panels`. It sends one snapshot for all 256 field panels using individual `POST /api/readings` requests, including zero samples for Offline panels. Requests run sequentially, at most 25 per second; the next sweep begins 10 seconds after the previous one finishes. The connection label shows confirmed progress.

No batch endpoint or backend changes are required. Database power remains its existing generated value, voltage × current. Rounding to two decimals can slightly change saved power. Field panel names are unique so the existing performance view keeps each panel separate.

Samples are synthetic and use real recording timestamps. Simulated time/Wh, angles, irradiance, and motor state stay inside Godot; the existing API cannot save those fields. Failed requests are not reported as saved. A failed sweep is abandoned and retried with a fresh snapshot after 10 seconds. Pausing or disabling saving holds unsent samples; an in-flight request may still finish. Statuses are loaded at startup; restart Godot after changing database statuses.

## Portable setup and seeding

On another Windows machine:

1. Install Godot 4.4+; set `GODOT_EXE` if it is outside Downloads/PATH.
2. Keep this folder inside the complete repository, alongside the original `Backend/` and SQL files.
3. Run `Launch.cmd`. It downloads missing portable Java/MariaDB, initializes a local database if absent, and seeds the field when creating that database.
4. If reusing an already configured database without the field, use `Create-Field.ps1` with the project-local database, or have its administrator import the panel records. Existing external databases are not automatically modified.

`Create-Field.ps1` chooses a random count between 16 and 64 Offline panels and random positions. It inserts missing field panels only; rerunning it does not duplicate panels, overwrite existing statuses, or alter original panels. The script uses the local setup account; Godot itself only uses HTTP. No database schema or permissions are changed.

The launcher reuses services already on ports 3306/8080 and never runs the reset script. Close Godot, then run `Stop-Services.ps1` to stop only services started by this project's launcher.

## Model

This is an educational model with a repeatable sun path peaking at 65° elevation, not location/date-specific astronomy. Power depends on rated capacity, direct sunlight, cloud attenuation, and the angle between the panel normal and sun direction. There is no inter-panel shading, temperature, diffuse-light, inverter, or circuit model. Visible normals use the same directions as the power calculation.

The reference faces south with 35° tilt from horizontal. Motor speeds are 25°/second azimuth and 20°/second elevation in real time. Wh integrates simulated time; scrubbing does not add energy for skipped hours.

## Verification

Using your Godot console executable from this folder:

```powershell
godot --headless --path . --script res://tests/model_test.gd
godot --headless --path . --script res://tests/scene_test.gd
godot --headless --path . -- --field-test
```

The first two make no database writes. The field integration check intentionally saves a full 256-panel sweep, then exits. It fails if 256 confirmations are not received within 120 seconds. API checks also confirmed all 64 Offline panels have zero latest output and all 192 Active panels have positive daylight output.

References: [Godot HTTPRequest](https://docs.godotengine.org/en/stable/classes/class_httprequest.html), [MariaDB portable installation](https://mariadb.com/docs/server/server-management/install-and-upgrade-mariadb/installing-mariadb/binary-packages/installing-mariadb-windows-zip-packages).
