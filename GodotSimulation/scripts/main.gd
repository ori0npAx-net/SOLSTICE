extends Node3D

const Model = preload("res://scripts/solar_model.gd")
const API_DEFAULT := "http://127.0.0.1:8080"
const GREEN := Color("c5ee93")
const MUTED := Color("9baead")
var hour := 8.0
var day_seconds := 180.0
var clouds := 0.0
var running := true
var tracking := true
var sending := true
var azimuth := 90.0
var elevation := 10.0
var tracked_wh := 0.0
var fixed_wh := 0.0
var panel_id := 0
var capacity := 300.0
var panels: Array = []
var api_url := API_DEFAULT
var request_kind := ""
var busy := false
var elapsed_send := 0.0
var saved := 0
var integration := false
var integration_elapsed := 0.0
var sample: Dictionary = {}
var fixed_sample: Dictionary = {}
var camera: Camera3D
var camera_yaw := 0.55
var camera_pitch := 0.48
var camera_distance := 23.0
var yaw_mount: Node3D
var tilt_mount: Node3D
var sun_ball: MeshInstance3D
var sunlight: DirectionalLight3D
var http: HTTPRequest
var labels: Dictionary = {}
var panel_picker: OptionButton
var clock_slider: HSlider
var pause_button: Button
var plot: Control
var history: Array[Vector2] = []
var history_tick := 0.0
var field_visuals: Array = []
var field_panels: Array = []
var sweep_queue: Array = []
var sweep_total := 0
var sweep_saved := 0
var sweep_failed := 0
var request_panel_id := 0
var send_cooldown := 0.0
var field_power := 0.0
var field_fixed_power := 0.0
var field_mode := false
var field_test := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--api="):
			api_url = arg.trim_prefix("--api=").trim_suffix("/")
		if arg == "--integration-test":
			integration = true
		if arg == "--field-test":
			integration = true
			field_test = true
	_build_world()
	_build_ui()
	http = HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	http.request_completed.connect(_request_completed)
	_fetch_panels()
	if "--capture" in OS.get_cmdline_user_args():
		_capture_preview()

func _capture_preview() -> void:
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.runtime/preview.png")
	get_tree().quit()

func _material(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.62
	return mat

func _box(parent: Node3D, size: Vector3, position_: Vector3, color: Color, metal: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = _material(color, metal)
	parent.add_child(instance)
	instance.position = position_
	return instance

func _text3d(text: String, position_: Vector3, color: Color = GREEN) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 40
	label.pixel_size = 0.008
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
	label.position = position_

func _field_panel(row: int, col: int) -> void:
	var base := Node3D.new()
	add_child(base)
	base.position = Vector3((col - 7.5) * 2.8, 0, (row - 7.5) * 2.8)
	_box(base, Vector3(0.75, 0.12, 0.75), Vector3(0, 0.06, 0), Color("505d54"))
	_box(base, Vector3(0.13, 1.5, 0.13), Vector3(0, 0.8, 0), Color("afbab5"), 0.7)
	var yaw := Node3D.new()
	base.add_child(yaw)
	yaw.position.y = 1.65
	var tilt := Node3D.new()
	yaw.add_child(tilt)
	_box(tilt, Vector3(1.5, 0.09, 1.9), Vector3.ZERO, Color("bbc6c6"), 0.7)
	var surface := _box(tilt, Vector3(1.40, 0.02, 1.80), Vector3(0, 0.06, 0), Color("133d59"), 0.35)
	for cell in range(1, 4):
		_box(tilt, Vector3(0.012, 0.01, 1.8), Vector3(-0.7 + cell * 0.35, 0.078, 0), Color("54879b"))
	for cell in range(1, 5):
		_box(tilt, Vector3(1.4, 0.01, 0.012), Vector3(0, 0.078, -0.9 + cell * 0.36), Color("54879b"))
	field_visuals.append({"yaw": yaw, "tilt": tilt, "surface": surface, "active": true})
	if row == 0 and col == 0:
		yaw_mount = yaw
		tilt_mount = tilt

func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("aebbb5")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c6d5d6")
	settings.ambient_light_energy = 0.4
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	_box(self, Vector3(160, 0.2, 160), Vector3(0, -0.15, 0), Color("34473c"))
	_box(self, Vector3(46, 0.04, 46), Vector3(0, -0.04, 0), Color("52624f"))
	for row in range(16):
		for col in range(16):
			_field_panel(row, col)
	_text3d("N / 16 x 16 SOLAR FIELD", Vector3(0, 1, -25))
	_text3d("BLUE / ACTIVE     RED / OFFLINE", Vector3(0, 1, 25))
	camera_distance = 82.0
	camera_pitch = 0.85
	sun_ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
	sun_ball.mesh = sphere
	var sun_material := _material(Color("ffe5a3"))
	sun_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sun_ball.material_override = sun_material
	add_child(sun_ball)
	# Dotted path follows the same direction function as the power model.
	for i in range(25):
		var sun := Model.sun_at(6.0 + i * 0.5)
		var dot := MeshInstance3D.new()
		var dot_mesh := SphereMesh.new()
		dot_mesh.radius = 0.055
		dot_mesh.height = 0.11
		dot.mesh = dot_mesh
		dot.material_override = _material(Color("d9d9b8"))
		add_child(dot)
		dot.position = Model.direction(sun.azimuth, sun.elevation) * 34.0
	sunlight = DirectionalLight3D.new()
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_max_distance = 160.0
	add_child(sunlight)
	camera = Camera3D.new()
	camera.fov = 52.0
	camera.current = true
	add_child(camera)
	_update_camera()

func _update_camera() -> void:
	# Offset framing leaves space for the control panel on the left.
	var target := Vector3(-10, 1.0, 0)
	camera.position = target + Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	camera.look_at(target)

func _style(bg: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.corner_radius_top_left = 14
	box.corner_radius_top_right = 14
	box.corner_radius_bottom_left = 14
	box.corner_radius_bottom_right = 14
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	return box

func _label(parent: Node, text: String, size: int = 16, color: Color = Color("edf1e8")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _slider(parent: Node, minimum: float, maximum: float, value_: float, step_: float, callback: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_
	slider.value = value_
	slider.custom_minimum_size.y = 24
	parent.add_child(slider)
	slider.value_changed.connect(callback)
	return slider

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.size = Vector2(340, 0)
	panel.custom_minimum_size.x = 340
	panel.add_theme_stylebox_override("panel", _style(Color(0.045, 0.085, 0.085, 0.97)))
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	_label(column, "SOLSTICE / SIMULATION LAB", 13, GREEN)
	_label(column, "Follow the sun.", 32)
	labels.field = _label(column, "16 × 16 field · 256 individual panels", 14, MUTED)
	column.add_child(HSeparator.new())
	labels.clock = _label(column, "08:00  /  SIMULATED TIME", 22, GREEN)
	clock_slider = _slider(column, 6, 18, hour, 0.02, func(value: float): hour = value)
	labels.speed = _label(column, "Day duration · 180 seconds", 14, MUTED)
	_slider(column, 30, 600, day_seconds, 10, func(value: float): day_seconds = value; labels.speed.text = "Day duration · %d seconds" % value)
	labels.cloud = _label(column, "Cloud cover · 0%", 14, MUTED)
	_slider(column, 0, 1, 0, 0.01, func(value: float): clouds = value; labels.cloud.text = "Cloud cover · %d%%" % (value * 100))
	var auto := CheckButton.new()
	auto.text = "Automatic dual-axis tracking"
	auto.button_pressed = true
	auto.toggled.connect(func(value: bool): tracking = value)
	column.add_child(auto)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.custom_minimum_size = Vector2(140, 34)
	pause_button.pressed.connect(func(): running = not running; pause_button.text = "Pause" if running else "Resume")
	actions.add_child(pause_button)
	var reset := Button.new()
	reset.text = "New day"
	reset.custom_minimum_size = Vector2(140, 34)
	reset.pressed.connect(_new_day)
	actions.add_child(reset)
	column.add_child(HSeparator.new())
	labels.power = _label(column, "0.0 W", 38, GREEN)
	labels.electrical = _label(column, "0.00 V  /  0.00 A", 16, MUTED)
	labels.fixed = _label(column, "Fixed reference: 0.0 W", 16)
	labels.energy = _label(column, "Session: 0.0 / 0.0 Wh", 14, MUTED)
	labels.angles = _label(column, "", 14, MUTED)
	labels.sun = _label(column, "", 14, MUTED)
	labels.alignment = _label(column, "", 14, MUTED)
	column.add_child(HSeparator.new())
	_label(column, "DATABASE CONNECTION", 12, GREEN)
	panel_picker = OptionButton.new()
	panel_picker.custom_minimum_size = Vector2(300, 32)
	panel_picker.clip_text = true
	panel_picker.add_item("Connecting to Java backend…")
	panel_picker.item_selected.connect(_select_panel)
	column.add_child(panel_picker)
	var send_toggle := CheckButton.new()
	send_toggle.text = "Save readings for the whole field"
	send_toggle.button_pressed = true
	send_toggle.toggled.connect(func(value: bool): sending = value)
	column.add_child(send_toggle)
	labels.connection = _label(column, "Connecting…", 13, MUTED)
	labels.connection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels.connection.custom_minimum_size.x = 300
	_label(column, "Synthetic data • saved with real timestamps", 12, MUTED)
	var footer := PanelContainer.new()
	root.add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.offset_left = -550
	footer.offset_top = -190
	footer.offset_right = -24
	footer.offset_bottom = -24
	footer.add_theme_stylebox_override("panel", _style(Color(0.045, 0.085, 0.085, 0.95)))
	var foot_column := VBoxContainer.new()
	footer.add_child(foot_column)
	labels.total = _label(foot_column, "FIELD OUTPUT / TRACKED vs FIXED", 13, GREEN)
	plot = Control.new()
	plot.custom_minimum_size = Vector2(470, 70)
	plot.draw.connect(_draw_plot)
	foot_column.add_child(plot)
	_label(foot_column, "Green: tracking   ·   Sand: fixed   |   Drag scene to orbit, scroll to zoom", 12, MUTED)
	var heading := Label.new()
	heading.position = Vector2(402, 28)
	heading.text = "A VIRTUAL PROTOTYPE OF YOUR SOLAR ARRAY"
	heading.add_theme_color_override("font_color", Color("243c35"))
	heading.add_theme_font_size_override("font_size", 15)
	root.add_child(heading)

func _new_day() -> void:
	hour = 6.0
	tracked_wh = 0.0
	fixed_wh = 0.0
	history.clear()
	# Does not delete saved database history or reset acknowledgement count.

func _process(delta: float) -> void:
	if running:
		hour += delta * 12.0 / day_seconds
		if hour > 18.0:
			hour = 6.0 + fmod(hour - 6.0, 12.0)
	var sun := Model.sun_at(hour)
	if tracking and running:
		azimuth = move_toward(azimuth, float(sun.azimuth), delta * 25.0)
		elevation = move_toward(elevation, float(sun.elevation), delta * 20.0)
	for visual in field_visuals:
		if visual.active:
			visual.yaw.rotation.y = -deg_to_rad(azimuth)
			visual.tilt.rotation.x = deg_to_rad(elevation - 90.0)
	var sun_dir := Model.direction(sun.azimuth, sun.elevation)
	sun_ball.position = sun_dir * 34.0
	sunlight.position = sun_dir * 20.0
	sunlight.look_at(Vector3.ZERO)
	sunlight.light_energy = maxf(0.05, sin(deg_to_rad(sun.elevation))) * (1.0 - clouds * 0.8) * 1.5
	sample = Model.sample(hour, azimuth, elevation, clouds, capacity)
	fixed_sample = Model.sample(hour, 180.0, 55.0, clouds, capacity)
	var selected_offline: bool = not panels.is_empty() and panels[panel_picker.selected].get("status", "Active") != "Active"
	if selected_offline:
		sample.power = 0.0
		sample.voltage = 0.0
		sample.current = 0.0
		fixed_sample.power = 0.0
	var active_capacity := 0.0
	for panel in field_panels:
		if panel.status == "Active":
			active_capacity += float(panel.capacity_watts)
	field_power = Model.sample(hour, azimuth, elevation, clouds, 300).power / 300.0 * active_capacity
	field_fixed_power = Model.sample(hour, 180, 55, clouds, 300).power / 300.0 * active_capacity
	if running:
		# Simulated energy uses accelerated simulation time, not wall-clock time.
		var simulated_hours := delta * 12.0 / day_seconds
		tracked_wh += sample.power * simulated_hours
		fixed_wh += fixed_sample.power * simulated_hours
		history_tick += delta
		if history_tick >= 0.3:
			history_tick = 0
			history.append(Vector2(field_power, field_fixed_power) if field_mode else Vector2(sample.power, fixed_sample.power))
			if history.size() > 160:
				history.pop_front()
			plot.queue_redraw()
	_update_labels()
	elapsed_send += delta
	send_cooldown -= delta
	if not busy and not sweep_queue.is_empty() and sending and running and send_cooldown <= 0:
		_send_next()
	elif elapsed_send >= 10.0 and not busy and sweep_queue.is_empty():
		elapsed_send = 0
		if panel_id == 0:
			_fetch_panels()
		elif sending and running:
			_begin_sweep()
	if integration:
		integration_elapsed += delta
		if saved >= (256 if field_test else 3):
			print("INTEGRATION PASS: Godot saved %d readings through the unchanged API for panel %d" % [saved, panel_id])
			get_tree().quit(0)
		elif integration_elapsed > (120.0 if field_test else 45.0):
			push_error("INTEGRATION FAIL: three database acknowledgements not received")
			get_tree().quit(1)

func _update_labels() -> void:
	var minutes := int(hour * 60.0)
	labels.clock.text = "%02d:%02d  /  SIMULATED TIME" % [minutes / 60, minutes % 60]
	clock_slider.set_value_no_signal(hour)
	labels.power.text = "%.1f W" % sample.power
	labels.electrical.text = "%.2f V  /  %.2f A" % [sample.voltage, sample.current]
	labels.fixed.text = "Fixed reference: %.1f W" % fixed_sample.power
	labels.energy.text = "Session: %.1f tracked / %.1f fixed Wh" % [tracked_wh, fixed_wh]
	labels.angles.text = "Motors: %.1f° azimuth / %.1f° elevation" % [azimuth, elevation]
	labels.sun.text = "Sun: %.1f° / %.1f°  ·  %.0f W/m²" % [sample.sun.azimuth, sample.sun.elevation, sample.irradiance]
	labels.alignment.text = "Alignment: %.1f%%  ·  %s" % [sample.alignment * 100, "TRACKING" if tracking else "MOTORS HELD"]
	if not panels.is_empty() and panels[panel_picker.selected].get("status", "Active") != "Active":
		labels.angles.text = "Motors parked · panel Offline"
		labels.alignment.text = "OFFLINE · output held at zero"
	if field_mode:
		labels.total.text = "FIELD %.2f kW TRACKED / %.2f kW FIXED" % [field_power / 1000, field_fixed_power / 1000]

func _draw_plot() -> void:
	var width := plot.size.x
	var height := plot.size.y
	plot.draw_line(Vector2(0, height - 1), Vector2(width, height - 1), Color("43544c"))
	if history.size() < 2:
		return
	var max_power := maxf(1.0, capacity)
	if field_mode:
		max_power = 0.0
		for panel in field_panels:
			if panel.status == "Active":
				max_power += float(panel.capacity_watts)
		max_power = maxf(1.0, max_power)
	for series in range(2):
		var points := PackedVector2Array()
		for i in range(history.size()):
			points.append(Vector2(float(i) / (history.size() - 1) * width, height - history[i][series] / max_power * (height - 3)))
		plot.draw_polyline(points, GREEN if series == 0 else Color("d9c6a1"), 2.0, true)

func _fetch_panels() -> void:
	if busy:
		return
	request_kind = "panels"
	busy = true
	var error := http.request(api_url + "/api/panels")
	if error != OK:
		busy = false
		labels.connection.text = "Backend unavailable. Retrying automatically."

func _select_panel(index: int) -> void:
	if index < 0 or index >= panels.size():
		return
	panel_id = int(panels[index].panel_id)
	capacity = float(panels[index].capacity_watts)
	tracked_wh = 0
	fixed_wh = 0
	history.clear()
	labels.connection.text = "Ready · panel %d · %d W total array rating" % [panel_id, capacity]

func _post_reading() -> void:
	sweep_queue = [{"panel_id": panel_id, "voltage": sample.voltage, "current": sample.current}]
	_send_next()

func _begin_sweep() -> void:
	if not field_mode:
		_post_reading()
		return
	sweep_queue.clear()
	for panel in field_panels:
		var reading := Model.sample(hour, azimuth, elevation, clouds, float(panel.capacity_watts))
		var active: bool = panel.status == "Active"
		sweep_queue.append({"panel_id": int(panel.panel_id), "voltage": reading.voltage if active else 0.0, "current": reading.current if active else 0.0})
	sweep_total = sweep_queue.size()
	sweep_saved = 0
	sweep_failed = 0
	_send_next()

func _send_next() -> void:
	var reading: Dictionary = sweep_queue.pop_front()
	request_panel_id = int(reading.panel_id)
	request_kind = "reading"
	busy = true
	send_cooldown = 0.04
	var body := "panel=%d&voltage=%.2f&current=%.2f" % [request_panel_id, reading.voltage, reading.current]
	var error := http.request(api_url + "/api/readings", ["Content-Type: application/x-www-form-urlencoded"], HTTPClient.METHOD_POST, body)
	if error != OK:
		busy = false
		labels.connection.text = "Offline · current sample not saved; retrying next sample."

func _request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		if request_kind == "reading":
			sweep_failed += 1
			sweep_queue.clear()
			elapsed_send = 0
		labels.connection.text = "Offline / HTTP %d · current sample not saved. Retrying." % code
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if request_kind == "panels":
		if not data is Array:
			labels.connection.text = "Unexpected panel response. Retrying."
			return
		field_panels = data.filter(func(p): return p is Dictionary and str(p.get("model_name", "")).begins_with("Godot Field R"))
		field_panels.sort_custom(func(a, b): return a.model_name < b.model_name)
		field_mode = field_panels.size() == 256
		panels = field_panels if field_mode else data.filter(func(p): return p is Dictionary and p.get("status") == "Active" and float(p.get("capacity_watts", 0)) > 0 and float(p.get("capacity_watts", 0)) <= 600)
		panel_picker.clear()
		if panels.is_empty():
			panel_picker.add_item("No active panels (1–600 W)")
			labels.connection.text = "No compatible active panel in database."
			return
		for panel in panels:
			panel_picker.add_item("%s · %s" % [panel.model_name, panel.status])
		if field_mode:
			var active_count := 0
			for i in range(256):
				var active: bool = panels[i].status == "Active"
				field_visuals[i].active = active
				field_visuals[i].surface.material_override = _material(Color("133d59") if active else Color("a83e35"), 0.25)
				if active:
					active_count += 1
				else:
					field_visuals[i].yaw.rotation.y = -PI
					field_visuals[i].tilt.rotation.x = deg_to_rad(-35)
			labels.field.text = "256 panels · %d Active / %d Offline" % [active_count, 256 - active_count]
		panel_picker.select(0)
		_select_panel(0)
		elapsed_send = 10.0
	elif data is Dictionary and data.get("saved") == true:
		saved += 1
		sweep_saved += 1
		if sweep_queue.is_empty():
			elapsed_send = 0
		labels.connection.text = "Connected · sweep %d/%d saved\n%d total acknowledgements" % [sweep_saved, sweep_total, saved]
	else:
		labels.connection.text = "Backend did not confirm saving this sample."

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		camera_yaw -= event.relative.x * 0.006
		camera_pitch = clampf(camera_pitch + event.relative.y * 0.004, 0.16, 1.25)
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(18, camera_distance - 3)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(140, camera_distance + 3)
		_update_camera()
