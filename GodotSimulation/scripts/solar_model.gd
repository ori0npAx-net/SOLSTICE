class_name SolarModel
extends RefCounted
## Educational model, not an astronomical ephemeris or engineering forecast.
## Azimuth: 0 north, 90 east, 180 south, 270 west. Elevation: above horizon.

static func sun_at(hour: float) -> Dictionary:
	var phase := clampf((hour - 6.0) / 12.0, 0.0, 1.0)
	var elevation := 65.0 * sin(PI * phase) if hour > 6.0 and hour < 18.0 else 0.0
	return {"azimuth": 90.0 + 180.0 * phase, "elevation": elevation}

static func direction(azimuth: float, elevation: float) -> Vector3:
	var az := deg_to_rad(azimuth)
	var el := deg_to_rad(elevation)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))

static func sample(hour: float, azimuth: float, elevation: float, cloud: float, capacity: float) -> Dictionary:
	var sun := sun_at(hour)
	var sun_direction := direction(sun.azimuth, sun.elevation)
	var normal := direction(azimuth, elevation)
	var incidence := maxf(0.0, normal.dot(sun_direction))
	var daylight := pow(maxf(0.0, sin(deg_to_rad(sun.elevation))), 0.22)
	var transmission := 1.0 - 0.85 * clampf(cloud, 0.0, 1.0)
	var irradiance := 1000.0 * daylight * transmission if sun.elevation > 0.01 else 0.0
	# Cap at the existing API's 60 V / 20 A envelope. Default register is 300 W.
	var power := clampf(capacity * irradiance / 1000.0 * incidence, 0.0, 600.0)
	var voltage := 30.0 * (0.90 + 0.10 * irradiance / 1000.0) if power > 0.0 else 0.0
	var current := power / voltage if voltage > 0.0 else 0.0
	return {"power": power, "voltage": voltage, "current": current,
		"irradiance": irradiance, "lux": irradiance * 120.0,
		"alignment": incidence, "sun": sun}
