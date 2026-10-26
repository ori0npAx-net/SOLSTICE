extends SceneTree
const Model = preload("res://scripts/solar_model.gd")

func _initialize() -> void:
	assert(Model.sample(6, 90, 0, 0, 300).power == 0.0, "Dawn must produce zero")
	assert(Model.sample(18, 270, 0, 0, 300).power == 0.0, "Sunset must produce zero")
	var noon = Model.sample(12, 180, 65, 0, 300)
	assert(noon.power > 280 and noon.power <= 300, "Aligned noon power")
	assert(absf(noon.voltage * noon.current - noon.power) < 0.001, "P = V * I")
	assert(Model.sample(12, 180, 65, 1, 300).power < noon.power * 0.2, "Cloud attenuation")
	var morning = Model.sun_at(8)
	var tracked = Model.sample(8, morning.azimuth, morning.elevation, 0, 300)
	assert(tracked.power > Model.sample(8, 180, 55, 0, 300).power, "Tracking improves morning output")
	assert(Model.sample(12, 0, 0, 0, 300).power == 0, "Back-facing panel must produce zero")
	var basis_ = Basis(Vector3.UP, -deg_to_rad(120.0)) * Basis(Vector3.RIGHT, deg_to_rad(40.0 - 90.0))
	assert(basis_.y.distance_to(Model.direction(120, 40)) < 0.0001, "Visible panel normal must match physics")
	print("MODEL PASS: dawn, sunset, noon, power equation, clouds, tracking gain, back face, 3D orientation")
	quit(0)
