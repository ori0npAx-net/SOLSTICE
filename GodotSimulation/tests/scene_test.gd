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
	scene.hour = 10.0
	scene.timeline.unix = float(Time.get_unix_time_from_datetime_string("2026-10-26T10:00:00"))
	scene.day_seconds = 180.0
	scene.running = true
	scene._process(0.1)
	assert(scene.hour > 10.0, "Running advances time")
	assert(scene.field_visuals.size() == 16, "Field must contain exactly 4 x 4 panels")
	var first_normal: Vector3 = scene.field_visuals[0].tilt.global_basis.y
	assert(first_normal.distance_to(scene.Model.direction(scene.azimuth, scene.elevation)) < 0.001, "Field panel visible orientation matches model")
	var held_hour = scene.hour
	var held_azimuth = scene.azimuth
	var held_energy = scene.tracked_wh
	scene.running = false
	scene._process(0.1)
	assert(scene.hour == held_hour and scene.azimuth == held_azimuth, "Pause holds clock and motors")
	assert(scene.tracked_wh == held_energy, "Pause holds energy")
	scene.running = true
	scene.tracking = false
	scene._process(0.1)
	assert(scene.hour > held_hour and scene.azimuth == held_azimuth, "Disabled tracking holds motors while sun moves")
	scene.saved = 5
	scene._new_day()
	assert(scene.hour == 6 and scene.timeline.timestamp().begins_with("2026-10-27"), "Next day advances calendar")
	assert(scene.saved == 5, "New day preserves saved acknowledgements")
	scene.panels = [{"panel_id": 42, "capacity_watts": 250.0}]
	scene._select_panel(0)
	assert(scene.panel_id == 42 and scene.capacity == 250.0, "Selected register sets array rating")
	# Exercise offline completion: no fake success count, simulation remains usable.
	scene._request_completed(2, 0, PackedStringArray(), PackedByteArray())
	assert(scene.saved == 5 and not scene.busy, "Offline request must not be counted as saved")
	assert("Offline" in scene.labels.connection.text, "Offline state is visible")
	scene.panels = [{"panel_id": 42, "capacity_watts": 300.0, "status": "Offline"}]
	scene.field_visuals[0].active = false
	var parked_basis: Basis = scene.field_visuals[0].tilt.global_basis
	scene._process(0.1)
	assert(scene.sample.power == 0 and scene.sample.voltage == 0 and scene.sample.current == 0, "Offline panel has zero electrical output")
	assert(scene.field_visuals[0].tilt.global_basis.is_equal_approx(parked_basis), "Offline motors stay parked")
	scene.panels[0].status = "Active"
	scene.running = false
	scene.hour = 12
	scene.azimuth = 180
	scene.elevation = 65
	scene.field_visuals[0].dust = 0.8
	scene.field_visuals[0].birds = 0.5
	scene._process(0)
	var dirty_power: float = scene.sample.power
	scene._clean(false)
	scene._process(0)
	assert(scene.sample.power > dirty_power, "Cleaning increases selected panel output")
	assert(scene.field_visuals[0].dust == 0 and scene.field_visuals[0].birds == 0, "Cleaning removes local contamination")
	scene.field_visuals[1].dust = 0.8
	scene._clean(true)
	assert(scene.field_visuals[1].dust == 0, "Clean all reaches other panels")
	scene.http.cancel_request()
	scene.queue_free()
	await process_frame
	print("SCENE PASS: clock, pause, held motors, local reset, panel selection, offline reporting")
	quit(0)
