extends SceneTree
const Weather = preload("res://scripts/environment_model.gd")
const Model = preload("res://scripts/solar_model.gd")

func _initialize() -> void:
	var clean := Model.sample(12, 180, 65, 0, 300)
	var dirty := Weather.apply(clean, 0.5, 0.4, 0)
	assert(dirty.power < clean.power, "Dust and droppings reduce output")
	assert(absf(dirty.power - dirty.voltage * dirty.current) < 0.001, "Loss preserves P = V * I")
	assert(Weather.apply(clean, 0, 0, 0).power == clean.power, "Cleaning restores potential")
	assert(Weather.apply(clean, 0.5, 0.4, 1).power < dirty.power, "Rain adds attenuation")
	var dry := Weather.soil_step(0.4, 0.2, 0, 1)
	var wet := Weather.soil_step(0.4, 0.2, 1, 1)
	assert(dry.x > 0.4 and wet.x < 0.4 and wet.y < 0.2, "Dry deposition and rain washing")
	assert(Weather.soil_step(0.4, 0.2, 0, 1, true).x > dry.x, "Dust storm speeds accumulation")
	assert(Weather.soil_step(0, 0, 1, 100) == Vector2.ZERO, "Washing cannot create negative soil")
	assert(Weather.transmission(10, 10, 10) >= 0, "Loss remains bounded")
	print("ENVIRONMENT PASS: soiling, cleaning, rain, dust storms, electrical consistency and bounds")
	quit(0)
