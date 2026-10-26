extends SceneTree
const Timeline = preload("res://scripts/timeline.gd")

func _initialize() -> void:
	var clock := Timeline.new()
	clock.unix = float(Time.get_unix_time_from_datetime_string("2026-12-31T23:59:59"))
	clock.advance(2.0, 86400.0)
	assert(clock.timestamp() == "2027-01-01 00:00:01", "Midnight rolls year forward")
	clock.unix = float(Time.get_unix_time_from_datetime_string("2028-02-28T23:59:59"))
	clock.advance(2, 86400)
	assert(clock.timestamp().begins_with("2028-02-29"), "Leap day supported")
	clock.next_day()
	assert(clock.timestamp() == "2028-03-01 06:00:00", "Next day keeps calendar")
	var before := clock.unix
	clock.advance(180, 180)
	assert(clock.unix == before + 86400, "Day duration represents a full 24 hours")
	print("TIMELINE PASS: midnight, year rollover, leap day, next day and continuous 24-hour clock")
	quit(0)
