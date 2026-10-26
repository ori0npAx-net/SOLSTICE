extends Node3D

const Model = preload("res://scripts/solar_model.gd")
const Weather = preload("res://scripts/environment_model.gd")
const Timeline = preload("res://scripts/timeline.gd")
const FIELD_SIZE := 4
const FIELD_COUNT := FIELD_SIZE * FIELD_SIZE
const API_DEFAULT := "http://127.0.0.1:8080"
const GREEN := Color("c5ee93")
const MUTED := Color("9baead")
var hour := 8.0
var day_seconds := 180.0
var clouds := 0.35
var rain := 0.0
var weather_mode := 0
var weather_phase := 2
var weather_clock := 0.0
var weather_next := 30.0
var weather_names := ["Automatic", "Clear", "Cloudy", "Rain", "Dust storm", "Custom"]
var rng := RandomNumberGenerator.new()
var cloud_nodes: Array = []
var rain_particles: CPUParticles3D
var world_settings: Environment
var ground: MeshInstance3D
var soil_time := 0.0
var environment_panel: PanelContainer
var weather_picker: OptionButton
var cloud_slider: HSlider
var rain_slider: HSlider
var bird_nodes: Array = []
var weather_elapsed := 0.0
var sun_path: Array = []
var timeline := Timeline.new()
var persistence_enabled := true
var persistence_path := "user://simulation-state.json"
var persist_elapsed := 0.0
var state_http: HTTPRequest
var state_busy := false
var restoring := false
var state_status := ""
var has_local_state := false
var speed_slider: HSlider
var tracking_toggle: CheckButton
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
		if arg == "--no-persistence":
			persistence_enabled = false
	if integration:
		persistence_enabled = false
	rng.randomize()
	_build_world()
	_build_ui()
	get_tree().auto_accept_quit = false
	if persistence_enabled:
		has_local_state = _load_local()
	hour = timeline.hour()
	state_http = HTTPRequest.new()
	state_http.timeout = 5.0
	add_child(state_http)
	state_http.request_completed.connect(_state_completed)
	if persistence_enabled:
		restoring = true
		state_busy = true
		if state_http.request(api_url + "/api/simulation-state") != OK:
			restoring = false
			state_busy = false
	http = HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	http.request_completed.connect(_request_completed)
	_fetch_panels()
	if "--capture" in OS.get_cmdline_user_args():
		_capture_preview()
	if "--capture-rain" in OS.get_cmdline_user_args():
		weather_mode = 3
		weather_picker.select(3)
		rain = 0.85
		clouds = 0.95
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
	base.position = Vector3((col - 1.5) * 2.8, 0, (row - 1.5) * 2.8)
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
	var dust_cover := _box(tilt, Vector3(1.39, 0.003, 1.79), Vector3(0, 0.088, 0), Color("b69c67"))
	var dust_mat := _material(Color(0.65, 0.49, 0.25, 0.2))
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dust_cover.material_override = dust_mat
	dust_cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spots: Array = []
	for i in range(8):
		var spot := MeshInstance3D.new()
		var splat := SphereMesh.new()
		splat.radius = rng.randf_range(0.045, 0.09)
		splat.height = splat.radius * 2
		spot.mesh = splat
		spot.material_override = _material(Color("e8e4ce"))
		tilt.add_child(spot)
		spot.position = Vector3(rng.randf_range(-0.58, 0.58), 0.099, rng.randf_range(-0.78, 0.78))
		spot.scale = Vector3(1, 0.12, rng.randf_range(0.6, 1.5))
		spots.append(spot)
	field_visuals.append({"yaw": yaw, "tilt": tilt, "surface": surface, "active": true,
		"energy_wh": 0.0, "fixed_wh": 0.0,
		"dust": rng.randf_range(0.12, 0.42), "birds": rng.randf_range(0.04, 0.18) if rng.randf() < 0.65 else 0.0,
		"dust_cover": dust_cover, "spots": spots})
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
	world_settings = settings
	add_child(environment)
	ground = _box(self, Vector3(100, 0.2, 100), Vector3(0, -0.15, 0), Color("34473c"))
	_box(self, Vector3(12, 0.04, 12), Vector3(0, -0.04, 0), Color("52624f"))
	for row in range(FIELD_SIZE):
		for col in range(FIELD_SIZE):
			_field_panel(row, col)
	_text3d("N / 4 x 4 SOLAR FIELD", Vector3(0, 0.4, -6.5))
	_text3d("BLUE / ACTIVE     RED / OFFLINE", Vector3(0, 0.4, 6.5))
	camera_distance = 27.0
	camera_pitch = 0.65
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
		dot.position = Model.direction(sun.azimuth, sun.elevation) * 13.5
		sun_path.append(dot)
	sunlight = DirectionalLight3D.new()
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_max_distance = 160.0
	add_child(sunlight)
	camera = Camera3D.new()
	camera.fov = 52.0
	camera.current = true
	add_child(camera)
	_update_camera()
	_build_weather()

func _update_camera() -> void:
	# Offset framing leaves space for the control panel on the left.
	var target := Vector3(-2.6, 1.0, 0)
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
	labels.field = _label(column, "4 × 4 field · 16 individual panels", 14, MUTED)
	column.add_child(HSeparator.new())
	labels.clock = _label(column, "08:00  /  SIMULATED TIME", 22, GREEN)
	labels.date = _label(column, "", 13, MUTED)
	labels.speed = _label(column, "Day duration · 180 seconds", 14, MUTED)
	speed_slider = _slider(column, 30, 600, day_seconds, 10, func(value: float): day_seconds = value; labels.speed.text = "Day duration · %d seconds" % value)
	var auto := CheckButton.new()
	tracking_toggle = auto
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
	reset.text = "Next day"
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
	labels.persistence = _label(column, "Continuous calendar · autosaved", 12, MUTED)
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
	heading.add_theme_color_override("font_color", GREEN)
	heading.add_theme_font_size_override("font_size", 15)
	root.add_child(heading)
	_build_environment_ui(root)

func _build_weather() -> void:
	for i in range(7):
		var cloud := Node3D.new()
		add_child(cloud)
		cloud.position = Vector3((i - 3) * 3.5, 7.0 + (i % 2) * 0.9, -7.0 - (i % 3) * 2.0)
		for j in range(4):
			var puff := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 1.0 + j * 0.15
			sphere.height = sphere.radius * 2
			puff.mesh = sphere
			cloud.add_child(puff)
			puff.position = Vector3(j * 0.9, sin(j * 1.7) * 0.3, 0)
			puff.scale = Vector3(1.3, 0.45, 0.8)
			var mat := _material(Color(0.8, 0.83, 0.84, 0.5))
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			puff.material_override = mat
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud_nodes.append(cloud)
	rain_particles = CPUParticles3D.new()
	rain_particles.amount = 1100
	rain_particles.lifetime = 1.4
	rain_particles.preprocess = 1.0
	rain_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain_particles.emission_box_extents = Vector3(9, 2, 9)
	rain_particles.direction = Vector3(0.12, -1, 0)
	rain_particles.spread = 4
	rain_particles.initial_velocity_min = 10
	rain_particles.initial_velocity_max = 16
	rain_particles.gravity = Vector3(0, -9, 0)
	var streak := BoxMesh.new()
	streak.size = Vector3(0.014, 0.30, 0.014)
	var rain_mat := _material(Color(0.65, 0.82, 0.94, 0.65))
	rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = rain_mat
	rain_particles.mesh = streak
	rain_particles.emitting = false
	add_child(rain_particles)
	rain_particles.position = Vector3(0, 10, 0)
	for i in range(2):
		var bird := Node3D.new()
		add_child(bird)
		_box(bird, Vector3(0.16, 0.13, 0.4), Vector3.ZERO, Color("242c2c"))
		var left := _box(bird, Vector3(0.65, 0.04, 0.16), Vector3(-0.35, 0, 0), Color("242c2c"))
		var right := _box(bird, Vector3(0.65, 0.04, 0.16), Vector3(0.35, 0, 0), Color("242c2c"))
		bird_nodes.append({"node": bird, "left": left, "right": right})
	# Small vegetation at the site edge provides a scale reference.
	for i in range(9):
		_box(self, Vector3(0.14, 0.8, 0.14), Vector3(-9 + i * 2.2, 0.4, -9), Color("554d37"))
		var shrub := MeshInstance3D.new()
		var shrub_mesh := SphereMesh.new()
		shrub_mesh.radius = 0.65
		shrub_mesh.height = 1.3
		shrub.mesh = shrub_mesh
		shrub.material_override = _material(Color("456c43"))
		add_child(shrub)
		shrub.position = Vector3(-9 + i * 2.2, 1.1, -9)

func _build_environment_ui(root: Control) -> void:
	environment_panel = PanelContainer.new()
	root.add_child(environment_panel)
	environment_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	environment_panel.offset_left = -340
	environment_panel.offset_right = -24
	environment_panel.offset_top = 68
	environment_panel.add_theme_stylebox_override("panel", _style(Color(0.045, 0.085, 0.085, 0.96)))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	environment_panel.add_child(column)
	_label(column, "WEATHER & PANEL SURFACE", 13, GREEN)
	weather_picker = OptionButton.new()
	for mode in weather_names:
		weather_picker.add_item(mode)
	weather_picker.item_selected.connect(func(index: int): weather_mode = index)
	column.add_child(weather_picker)
	labels.weather = _label(column, "Cloudy · changing naturally", 14, MUTED)
	labels.cloud = _label(column, "Cloud cover", 13, MUTED)
	cloud_slider = _slider(column, 0, 1, clouds, 0.01, func(value: float): clouds = value; weather_mode = 5; weather_picker.select(5))
	labels.rain = _label(column, "Rain intensity", 13, MUTED)
	rain_slider = _slider(column, 0, 1, rain, 0.01, func(value: float): rain = value; weather_mode = 5; weather_picker.select(5))
	labels.soil = _label(column, "", 14, MUTED)
	labels.soil.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels.soil.custom_minimum_size.x = 270
	var clean := Button.new()
	clean.text = "Clean selected panel"
	clean.pressed.connect(func(): _clean(false))
	column.add_child(clean)
	var all := Button.new()
	all.text = "Clean all 16 panels"
	all.pressed.connect(func(): _clean(true))
	column.add_child(all)
	var gust := Button.new()
	gust.text = "Add dust gust"
	gust.pressed.connect(func():
		for visual in field_visuals:
			visual.dust = minf(1, visual.dust + rng.randf_range(0.15, 0.3)))
	column.add_child(gust)
	var dropping := Button.new()
	dropping.text = "Bird dropping on selected panel"
	dropping.pressed.connect(func():
		var index := maxi(0, panel_picker.selected)
		field_visuals[index].birds = minf(1, field_visuals[index].birds + 0.12))
	column.add_child(dropping)
	_label(column, "Rain washes dust gradually.\nWhite marks = droppings; tan = dust.", 12, MUTED)

func _clean(all: bool) -> void:
	var selected := maxi(0, panel_picker.selected)
	for i in range(field_visuals.size()):
		if all or i == selected:
			field_visuals[i].dust = 0.0
			field_visuals[i].birds = 0.0

func _update_weather(delta: float) -> void:
	if running:
		weather_elapsed += delta
		weather_clock += delta
		if weather_mode == 0 and weather_clock >= weather_next:
			weather_clock = 0
			weather_next = rng.randf_range(25, 45)
			weather_phase = rng.randi_range(1, 4)
		var mode := weather_phase if weather_mode == 0 else weather_mode
		if mode != 5:
			var target_cloud: float = [0.0, 0.08, 0.72, 0.95, 0.30][mode]
			var target_rain := 0.85 if mode == 3 else 0.0
			clouds = move_toward(clouds, target_cloud, delta * 0.12)
			rain = move_toward(rain, target_rain, delta * 0.16)
		var hours := delta * 24.0 / day_seconds
		for visual in field_visuals:
			var soil := Weather.soil_step(visual.dust, visual.birds, rain, hours, mode == 4)
			visual.dust = soil.x
			visual.birds = soil.y
			if rng.randf() < hours * 0.09:
				visual.birds = minf(1, visual.birds + rng.randf_range(0.04, 0.12))
	for i in range(cloud_nodes.size()):
		var cloud: Node3D = cloud_nodes[i]
		cloud.position.x = fposmod((i - 3) * 3.5 + weather_elapsed * 0.15 + 14, 28) - 14
		cloud.visible = clouds > 0.03
		for puff in cloud.get_children():
			var color := Color("c5d0d1").lerp(Color("55616e"), rain * 0.8)
			color.a = clouds * 0.82
			puff.material_override.albedo_color = color
	rain_particles.emitting = rain > 0.03
	rain_particles.visible = rain > 0.03
	rain_particles.speed_scale = 1.0 if running else 0.0
	rain_particles.mesh.material.albedo_color.a = rain * 0.75
	sun_ball.visible = clouds < 0.9 and hour > 6 and hour < 18
	for dot in sun_path:
		dot.visible = clouds < 0.8
	world_settings.background_color = Color("aebbb5").lerp(Color("566775"), clouds * 0.65 + rain * 0.3)
	ground.material_override.roughness = lerpf(0.9, 0.12, rain)
	ground.material_override.albedo_color = Color("34473c").lerp(Color("253c37"), rain)
	for i in range(bird_nodes.size()):
		var bird: Dictionary = bird_nodes[i]
		var phase := weather_elapsed * 0.35 + i * PI
		bird.node.position = Vector3(cos(phase) * 7, 5 + i * 0.7, sin(phase) * 5)
		bird.node.rotation.y = -phase
		bird.left.rotation.z = sin(weather_elapsed * 9) * 0.45
		bird.right.rotation.z = -sin(weather_elapsed * 9) * 0.45
	for visual in field_visuals:
		visual.surface.material_override.roughness = lerpf(0.62, 0.16, rain)
		visual.dust_cover.material_override.albedo_color.a = visual.dust * 0.65
		for i in range(visual.spots.size()):
			visual.spots[i].visible = i < ceili(visual.birds * 8.0)
	if not labels.has("weather"):
		return
	var mode := weather_phase if weather_mode == 0 else weather_mode
	labels.weather.text = "%s%s" % [weather_names[mode], " · automatic" if weather_mode == 0 else ""]
	labels.cloud.text = "Cloud cover · %d%%" % (clouds * 100)
	labels.rain.text = "Rain intensity · %d%%" % (rain * 100)
	cloud_slider.set_value_no_signal(clouds)
	rain_slider.set_value_no_signal(rain)
	var selected: Dictionary = field_visuals[maxi(0, panel_picker.selected)]
	labels.soil.text = "Selected: dust %.0f%% / droppings %.0f%%\nSurface + rain loss: %.1f%%" % [selected.dust * 100, selected.birds * 100, (1 - Weather.transmission(selected.dust, selected.birds, rain)) * 100]

func _panel_reading(index: int, fixed: bool) -> Dictionary:
	var visual: Dictionary = field_visuals[clampi(index, 0, FIELD_COUNT - 1)]
	var rating := float(field_panels[index].capacity_watts) if field_mode and index < field_panels.size() else capacity
	var reading := Model.sample(hour, 180.0 if fixed else azimuth, 55.0 if fixed else elevation, clouds, rating)
	return Weather.apply(reading, visual.dust, visual.birds, rain)

func _new_day() -> void:
	timeline.next_day()
	hour = timeline.hour()
	# Advance calendar only. All totals, dirt, and saved records are retained.
	_save_local()

func _process(delta: float) -> void:
	if restoring:
		return
	_update_weather(delta)
	if running:
		timeline.advance(delta, day_seconds)
		hour = timeline.hour()
	var sun := Model.sun_at(hour)
	if tracking and running:
		azimuth = move_toward(azimuth, float(sun.azimuth), delta * 25.0)
		elevation = move_toward(elevation, float(sun.elevation), delta * 20.0)
	for visual in field_visuals:
		if visual.active:
			visual.yaw.rotation.y = -deg_to_rad(azimuth)
			visual.tilt.rotation.x = deg_to_rad(elevation - 90.0)
	var sun_dir := Model.direction(sun.azimuth, sun.elevation)
	sun_ball.position = sun_dir * 13.5
	sunlight.position = sun_dir * 20.0
	sunlight.look_at(Vector3.ZERO)
	sunlight.light_energy = maxf(0.05, sin(deg_to_rad(sun.elevation))) * (1.0 - clouds * 0.8) * 1.5
	var selected_index := maxi(0, panel_picker.selected)
	sample = _panel_reading(selected_index, false)
	fixed_sample = _panel_reading(selected_index, true)
	var selected_offline: bool = not panels.is_empty() and panels[panel_picker.selected].get("status", "Active") != "Active"
	if selected_offline:
		sample.power = 0.0
		sample.voltage = 0.0
		sample.current = 0.0
		fixed_sample.power = 0.0
	field_power = 0.0
	field_fixed_power = 0.0
	for i in range(field_panels.size()):
		if field_panels[i].status == "Active":
			field_power += _panel_reading(i, false).power
			field_fixed_power += _panel_reading(i, true).power
	if running:
		# Simulated energy uses accelerated simulation time, not wall-clock time.
		var simulated_hours := delta * 24.0 / day_seconds
		for i in range(FIELD_COUNT):
			var active: bool = field_panels[i].status == "Active" if field_mode else field_visuals[i].active
			if active:
				field_visuals[i].energy_wh += _panel_reading(i, false).power * simulated_hours
				field_visuals[i].fixed_wh += _panel_reading(i, true).power * simulated_hours
		history_tick += delta
		if history_tick >= 0.3:
			history_tick = 0
			history.append(Vector2(field_power, field_fixed_power) if field_mode else Vector2(sample.power, fixed_sample.power))
			if history.size() > 160:
				history.pop_front()
			plot.queue_redraw()
	tracked_wh = field_visuals[selected_index].energy_wh
	fixed_wh = field_visuals[selected_index].fixed_wh
	_update_labels()
	persist_elapsed += delta
	if persist_elapsed >= 2.0:
		persist_elapsed = 0
		_save_local()
	elapsed_send += delta
	send_cooldown -= delta
	if not busy and not sweep_queue.is_empty() and sending and running and send_cooldown <= 0:
		_send_next()
	elif elapsed_send >= 2.0 and not busy and sweep_queue.is_empty():
		elapsed_send = 0
		if panel_id == 0:
			_fetch_panels()
		elif sending and running:
			_begin_sweep()
	if integration:
		integration_elapsed += delta
		if saved >= (FIELD_COUNT if field_test else 3):
			print("INTEGRATION PASS: Godot saved %d dated readings through the Java API for panel %d" % [saved, panel_id])
			get_tree().quit(0)
		elif integration_elapsed > (120.0 if field_test else 45.0):
			push_error("INTEGRATION FAIL: expected database acknowledgements not received")
			get_tree().quit(1)

func _update_labels() -> void:
	var minutes := int(hour * 60.0)
	labels.clock.text = "%02d:%02d  /  SIMULATED TIME" % [minutes / 60, minutes % 60]
	labels.date.text = timeline.timestamp().substr(0, 10) + " · PKT · resumes on restart"
	labels.power.text = "%.1f W" % sample.power
	labels.electrical.text = "%.2f V  /  %.2f A" % [sample.voltage, sample.current]
	labels.fixed.text = "Fixed reference: %.1f W" % fixed_sample.power
	labels.energy.text = "Lifetime: %.1f tracked / %.1f fixed Wh" % [tracked_wh, fixed_wh]
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
	tracked_wh = field_visuals[index].energy_wh
	fixed_wh = field_visuals[index].fixed_wh
	labels.connection.text = "Ready · panel %d · %d W total array rating" % [panel_id, capacity]

func _post_reading() -> void:
	sweep_queue = [_sample_payload(maxi(0, panel_picker.selected), panel_id, sample)]
	_send_next()

func _begin_sweep() -> void:
	if not field_mode:
		_post_reading()
		return
	sweep_queue.clear()
	for i in range(field_panels.size()):
		var panel: Dictionary = field_panels[i]
		var reading := _panel_reading(i, false)
		var active: bool = panel.status == "Active"
		if not active:
			reading.voltage = 0.0
			reading.current = 0.0
		sweep_queue.append(_sample_payload(i, int(panel.panel_id), reading))
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
	var body := "panel=%d&voltage=%.2f&current=%.2f&simulated_at=%s&cloud_cover=%.4f&rain_intensity=%.4f&dust_level=%.4f&bird_level=%.4f" % [request_panel_id, reading.voltage, reading.current, reading.simulated_at.uri_encode(), reading.cloud, reading.rain, reading.dust, reading.birds]
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
		var field_regex := RegEx.new()
		field_regex.compile("^Godot Field R0[1-4] C0[1-4]$")
		field_panels = data.filter(func(p): return p is Dictionary and field_regex.search(str(p.get("model_name", ""))) != null)
		field_panels.sort_custom(func(a, b): return a.model_name < b.model_name)
		field_mode = field_panels.size() == FIELD_COUNT
		panels = field_panels if field_mode else data.filter(func(p): return p is Dictionary and p.get("status") == "Active" and float(p.get("capacity_watts", 0)) > 0 and float(p.get("capacity_watts", 0)) <= 600).slice(0, FIELD_COUNT)
		panel_picker.clear()
		if panels.is_empty():
			panel_picker.add_item("No active panels (1–600 W)")
			labels.connection.text = "No compatible active panel in database."
			return
		for panel in panels:
			panel_picker.add_item("%s · %s" % [panel.model_name, panel.status])
		if field_mode:
			var active_count := 0
			for i in range(FIELD_COUNT):
				var active: bool = panels[i].status == "Active"
				field_visuals[i].active = active
				field_visuals[i].surface.material_override = _material(Color("133d59") if active else Color("a83e35"), 0.25)
				if active:
					active_count += 1
				else:
					field_visuals[i].yaw.rotation.y = -PI
					field_visuals[i].tilt.rotation.x = deg_to_rad(-35)
			labels.field.text = "16 panels · %d Active / %d Offline" % [active_count, FIELD_COUNT - active_count]
		panel_picker.select(0)
		_select_panel(0)
		elapsed_send = 2.0
	elif data is Dictionary and data.get("saved") == true:
		saved += 1
		sweep_saved += 1
		if sweep_queue.is_empty():
			elapsed_send = 0
			_save_checkpoint()
		labels.connection.text = "Connected · sweep %d/%d saved\n%d total acknowledgements" % [sweep_saved, sweep_total, saved]
	else:
		labels.connection.text = "Backend did not confirm saving this sample."

func _sample_payload(index: int, id: int, reading: Dictionary) -> Dictionary:
	var visual: Dictionary = field_visuals[index]
	return {"panel_id": id, "voltage": reading.voltage, "current": reading.current,
		"simulated_at": timeline.timestamp(), "cloud": clouds, "rain": rain, "dust": visual.dust, "birds": visual.birds}

func _snapshot() -> Dictionary:
	var soil: Array = []
	for visual in field_visuals:
		soil.append({"dust": visual.dust, "birds": visual.birds, "energy_wh": visual.energy_wh, "fixed_wh": visual.fixed_wh})
	var points: Array = []
	for point in history:
		points.append([point.x, point.y])
	return {"version": 1, "simulated_unix": timeline.unix, "day_seconds": day_seconds,
		"clouds": clouds, "rain": rain, "weather_mode": weather_mode, "weather_phase": weather_phase,
		"weather_clock": weather_clock, "weather_next": weather_next, "weather_elapsed": weather_elapsed,
		"azimuth": azimuth, "elevation": elevation, "tracking": tracking, "running": running, "soil": soil,
		"history": points, "rng_state": str(rng.state)}

func _restore_snapshot(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1:
		return false
	var time_value := float(data.get("simulated_unix", 0))
	var soil: Variant = data.get("soil", [])
	if not is_finite(time_value) or time_value < 1577836800 or time_value >= 4133980800 or not soil is Array or soil.size() != FIELD_COUNT:
		return false
	for item in soil:
		if not item is Dictionary:
			return false
	timeline.unix = time_value
	hour = timeline.hour()
	day_seconds = clampf(float(data.get("day_seconds", 180)), 30, 600)
	clouds = clampf(float(data.get("clouds", 0.35)), 0, 1)
	rain = clampf(float(data.get("rain", 0)), 0, 1)
	weather_mode = clampi(int(data.get("weather_mode", 0)), 0, 5)
	weather_phase = clampi(int(data.get("weather_phase", 2)), 1, 4)
	weather_clock = float(data.get("weather_clock", 0))
	weather_next = float(data.get("weather_next", 30))
	weather_elapsed = float(data.get("weather_elapsed", 0))
	azimuth = float(data.get("azimuth", 90))
	elevation = float(data.get("elevation", 10))
	tracking = bool(data.get("tracking", true))
	running = bool(data.get("running", true))
	for i in range(FIELD_COUNT):
		field_visuals[i].dust = clampf(float(soil[i].get("dust", 0)), 0, 1)
		field_visuals[i].birds = clampf(float(soil[i].get("birds", 0)), 0, 1)
		field_visuals[i].energy_wh = maxf(0, float(soil[i].get("energy_wh", 0)))
		field_visuals[i].fixed_wh = maxf(0, float(soil[i].get("fixed_wh", 0)))
	history.clear()
	for point in data.get("history", []).slice(-160):
		if point is Array and point.size() == 2:
			history.append(Vector2(float(point[0]), float(point[1])))
	if data.has("rng_state"):
		rng.state = str(data.rng_state).to_int()
	weather_picker.select(weather_mode)
	speed_slider.set_value_no_signal(day_seconds)
	labels.speed.text = "Day duration · %d seconds" % day_seconds
	tracking_toggle.set_pressed_no_signal(tracking)
	pause_button.text = "Pause" if running else "Resume"
	plot.queue_redraw()
	return true

func _load_local() -> bool:
	if FileAccess.file_exists(persistence_path):
		return _restore_snapshot(JSON.parse_string(FileAccess.get_file_as_string(persistence_path)))
	return false

func _save_local() -> void:
	if not persistence_enabled or restoring:
		return
	var file := FileAccess.open(persistence_path + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_snapshot()))
		file.close()
		DirAccess.rename_absolute(ProjectSettings.globalize_path(persistence_path + ".tmp"), ProjectSettings.globalize_path(persistence_path))

func _save_checkpoint() -> void:
	_save_local()
	if not persistence_enabled or state_busy:
		return
	state_busy = true
	var body := "simulated_at=%s&state=%s" % [timeline.timestamp().uri_encode(), JSON.stringify(_snapshot()).uri_encode()]
	if state_http.request(api_url + "/api/simulation-state", ["Content-Type: application/x-www-form-urlencoded"], HTTPClient.METHOD_POST, body) != OK:
		state_busy = false

func _state_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	state_busy = false
	if restoring:
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var rows: Variant = JSON.parse_string(body.get_string_from_utf8())
			if rows is Array and not rows.is_empty():
				var state: Variant = JSON.parse_string(str(rows[0].get("state_json", "")))
				if state is Dictionary and (not has_local_state or float(state.get("simulated_unix", 0)) > timeline.unix):
					_restore_snapshot(state)
		restoring = false
		_save_local()
	else:
		labels.persistence.text = "Database checkpoint saved" if result == 0 and code == 201 else "Local state saved · database checkpoint pending"

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		running = false
		_save_checkpoint()
		if state_busy:
			await get_tree().create_timer(1.0).timeout
		get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		camera_yaw -= event.relative.x * 0.006
		camera_pitch = clampf(camera_pitch + event.relative.y * 0.004, 0.16, 1.25)
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(12, camera_distance - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(55, camera_distance + 1)
		_update_camera()
