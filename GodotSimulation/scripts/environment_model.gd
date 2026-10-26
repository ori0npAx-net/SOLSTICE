class_name FieldEnvironment
extends RefCounted
## Illustrative effects; coefficients are demonstration settings, not forecasts.

static func transmission(dust: float, birds: float, rain: float) -> float:
	return (1.0 - 0.45 * clampf(dust, 0, 1)) * (1.0 - 0.70 * clampf(birds, 0, 1)) * (1.0 - 0.12 * clampf(rain, 0, 1))

static func soil_step(dust: float, birds: float, rain: float, hours: float, dust_storm: bool = false) -> Vector2:
	var deposition := 0.018 * (5.0 if dust_storm else 1.0) * (1.0 - rain)
	return Vector2(clampf(dust + (deposition - rain * 0.24) * hours, 0, 1), clampf(birds - rain * 0.015 * hours, 0, 1))

static func apply(reading: Dictionary, dust: float, birds: float, rain: float) -> Dictionary:
	var adjusted := reading.duplicate(true)
	var factor := transmission(dust, birds, rain)
	adjusted.power *= factor
	adjusted.current *= factor
	adjusted.loss = 1.0 - factor
	return adjusted
