extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://Main.tscn").instantiate()
	scene.persistence_enabled = false
	scene.api_url = "http://127.0.0.1:18089"
	scene.sending = false
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	scene.timeline.unix = float(Time.get_unix_time_from_datetime_string("2026-10-26T23:59:59"))
	scene.field_visuals[0].dust = 0.6
	scene.field_visuals[0].birds = 0.3
	scene.field_visuals[0].energy_wh = 123.0
	scene.field_visuals[0].fixed_wh = 97.0
	scene.history.append(Vector2(120, 100))
	scene.day_seconds = 300
	var state: Dictionary = scene._snapshot()
	scene.timeline.advance(3, 86400)
	scene.field_visuals[0].dust = 0
	scene.field_visuals[0].energy_wh = 0
	assert(scene._restore_snapshot(state), "Valid checkpoint must restore")
	assert(scene.timeline.timestamp() == "2026-10-26 23:59:59", "Clock resumes exactly")
	assert(scene.field_visuals[0].dust == 0.6 and scene.field_visuals[0].energy_wh == 123, "Soil and energy survive restore")
	assert(scene.history.size() == 1 and scene.day_seconds == 300, "Chart and speed survive restore")
	scene._new_day()
	assert(scene.timeline.timestamp() == "2026-10-27 06:00:00", "Next day advances date")
	assert(scene.field_visuals[0].energy_wh == 123 and scene.history.size() == 1 and scene.field_visuals[0].dust == 0.6, "Next day preserves prior totals/chart/dirt")
	scene.persistence_path = "user://persistence-regression.json"
	scene.persistence_enabled = true
	scene._save_local()
	scene.field_visuals[0].energy_wh = 0
	assert(scene._load_local() and scene.field_visuals[0].energy_wh == 123, "Disk state survives reload")
	scene.persistence_enabled = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scene.persistence_path))
	assert(not scene._restore_snapshot({"version": 1, "simulated_unix": 0}), "Invalid checkpoint rejected")
	scene.http.cancel_request()
	scene.state_http.cancel_request()
	scene.queue_free()
	await process_frame
	print("PERSISTENCE PASS: clock, soil, energy, chart, speed, next-day continuity and disk reload")
	quit(0)
