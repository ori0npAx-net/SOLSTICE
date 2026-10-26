class_name SimulationTimeline
extends RefCounted
## Calendar arithmetic on a civil PKT clock; no host timezone conversions.
var unix: float = 0.0

func _init() -> void:
	var today := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + 18000)
	unix = float(Time.get_unix_time_from_datetime_dict({"year": today.year, "month": today.month, "day": today.day, "hour": 8, "minute": 0, "second": 0}))

func advance(seconds: float, day_duration: float) -> void:
	unix += maxf(0, seconds) * 86400.0 / maxf(1, day_duration)

func hour() -> float:
	return fposmod(unix, 86400.0) / 3600.0

func timestamp() -> String:
	return Time.get_datetime_string_from_unix_time(int(unix)).replace("T", " ")

func next_day() -> void:
	unix = (floor(unix / 86400.0) + 1) * 86400.0 + 6 * 3600.0
