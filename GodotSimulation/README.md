# Solstice — 4 x 4 Godot solar field

A separate Godot 4 simulation with **16 individual 300 W panels** (4.8 kW installed capacity), weather and surface contamination. The dashboard and Java backend now support dated history and persistent simulation state through the additive `6_simulation_history.sql` migration.

## Start or transfer to another PC

Keep `GodotSimulation` inside the **complete repository**, alongside `Backend/` and the original SQL scripts. Install Godot 4.4+ and double-click **Launch.cmd**. Missing Java/MariaDB runtimes download and verify automatically on first launch, which requires internet. Set `GODOT_EXE` if Godot is not in Downloads or PATH.

Do not upload `.runtime/`, `.godot/`, or `logs/`. Launch recreates portable runtime files. The dashboard stays at http://localhost:8080. To edit the simulation, import `project.godot` and press F5.

On this computer the field has **13 Active and 3 Offline** panels, preserving the statuses of the retained positions. New installations choose 2–5 random Offline positions. Blue panels track the sun; red panels remain parked and report zero output.

## Weather and natural effects

The right-hand panel offers **Automatic, Clear, Cloudy, Rain, Dust storm, and Custom** modes. Automatic mode smoothly changes conditions every 25–45 real seconds while running. Cloud and rain sliders select Custom mode.

- **Clouds:** moving 3D clouds, a darker sky and less sunlight. Heavy clouds hide the visible sun/path.
- **Rain:** falling streaks, a darker/wetter ground and panel appearance, reduced output, and gradual washing of dust and a smaller amount of droppings.
- **Dust:** an uneven tan coating per panel. It accumulates with simulated time, faster during dust storms, and reduces output.
- **Bird droppings:** irregular white patches per panel; occasional simulated bird strikes add contamination. Birds fly around the field.
- **Cleaning:** clean the selected panel or all panels. Coatings disappear and electrical output improves under the same sunlight. Cleaning does not reactivate Offline panels.
- **Demonstration controls:** Add dust gust affects all panels; Bird dropping targets the selected panel. These make before/after comparisons easy without waiting.

Dust and droppings are randomized only on the first launch. Subsequent launches recover them from local/database state. Next day advances the calendar without clearing dirt, energy totals, or prior readings.

## Main controls and readouts

| Control | Behavior |
| --- | --- |
| Date/time | Continuous PKT calendar with midnight rollover; night output is zero |
| Day duration | Real seconds required for a full 24 simulated hours |
| Tracking | Hold active motors while the sun keeps moving |
| Pause | Hold time/weather/motors/soil, energy integration and new sends |
| Next day | Advance to tomorrow at 06:00, preserving all totals/history/dirt |
| Panel menu | Inspect one of the 16 panels, including Offline panels |
| Save whole field | Enable/disable database submissions |
| Drag / scroll | Orbit / zoom |

The left watt/voltage/current readout and Wh refer to the selected panel. The bottom chart and kW heading show the combined Active field versus the equivalent fixed field. Both comparisons use each panel's same contamination and weather conditions. Offline panels contribute zero to both.

## Existing API and database

Godot reads the panel IDs/statuses from `GET /api/panels` and saves one snapshot per field panel through individual `POST /api/readings` calls. A sweep includes all 16 panels and zero voltage/current for Offline panels. Requests run sequentially, at most 25/second; the next sweep starts 2 seconds after the last one completes. The connection label counts confirmed saves.

The backend receives the **final voltage/current after weather and contamination losses**. MariaDB calculates power with its existing generated column, so these effects appear in the existing dashboard. Small differences from on-screen power come from rounding to two decimals.

Readings store simulated_at separately from real recorded_at, plus cloud/rain/dust/bird levels. Append-only SIMULATION_STATE checkpoints store the clock, weather, contamination, per-panel lifetime Wh, motor orientation and rolling chart. Local state autosaves every two seconds; database checkpoints follow completed sweeps. Sensor/movement tables remain separate and are not written.

Failures are not counted as saved. A failed sweep is abandoned and retried with a fresh snapshot after 2 seconds. Pausing or disabling saving holds unsent samples, although an in-flight request may finish. Restart Godot after editing database statuses.

## Reducing the previous 16 x 16 field

`Create-Field.ps1` now maintains positions R01–R04 / C01–C04. Before removing the 240 extra old field positions and their dependent history, it creates a full SQL backup under `.runtime/backups/before-4x4-*.sql`. It aborts removal if the backup fails. The retained 16 panel IDs, statuses and history are kept, as are the original two sample panels. The additive history migration adds columns and a checkpoint table without changing account permissions.

Launch runs this maintenance only for its own project-local MariaDB process; it does not automatically modify external databases. For an external database, its administrator must perform the equivalent backed-up migration. Repeated launches do not duplicate panels or reshuffle statuses.

The backup contains the old data and is intentionally excluded from uploads. Keep a separate copy if you want to transfer that historical data. The two original sample panels are retained as legacy records in the database. The dashboard and its API count **only the 16 simulation panels**, using the is_simulation flag.

## Model assumptions

This is an educational approximation, not a location/date-specific solar forecast. The sun peaks at 65 degrees. Cloud cover reduces direct irradiance by up to 85%; dust, droppings and rain apply further bounded multiplicative losses. Current changes consistently with power, preserving P = V x I. Coefficients are demonstration settings rather than calibrated engineering data. Droppings represent a lumped coverage/blockage index, not a photovoltaic bypass-diode circuit model.

There is no inter-panel shading, detailed cloud-shadow map, diffuse-light, temperature, inverter or electrical circuit model. The fixed reference faces south at 35 degrees tilt from horizontal. Motor rates are 25 degrees/second azimuth and 20 degrees/second elevation in real time. Lifetime Wh integrates accelerated simulated time. Next day does not invent energy for skipped hours. The simulation pauses while closed and resumes its saved calendar rather than starting over.

## Verification and stopping

Run with your Godot console executable from this folder:

```powershell
godot --headless --path . --script res://tests/model_test.gd
godot --headless --path . --script res://tests/environment_test.gd
godot --headless --path . --script res://tests/scene_test.gd
godot --headless --path . --script res://tests/timeline_test.gd
godot --headless --path . --script res://tests/persistence_test.gd
godot --headless --path . --script res://tests/database_restore_test.gd
godot --headless --path . -- --field-test
```

The script tests make no database writes; database_restore_test requires an existing checkpoint. The field test intentionally saves a full **16-panel sweep**, requires 16 acknowledgements, then exits; it fails after 120 seconds. Tests cover output loss, cleaning, rain washing, dust storms, electrical consistency, paused motion, Offline output, 16 visible panels and visible/model orientation agreement.

Close Godot and run `Stop-Services.ps1` to stop only Java/database processes started by the launcher. Closing Godot alone stops submissions and leaves the original dashboard available.

References: [Godot CPUParticles3D](https://docs.godotengine.org/en/stable/classes/class_cpuparticles3d.html), [Godot HTTPRequest](https://docs.godotengine.org/en/stable/classes/class_httprequest.html).

For date filtering, legacy history, CSV export, migration, and timestamp conventions, see the repository README. Upload the updated Backend folder, GodotSimulation folder, and 6_simulation_history.sql together.
