extends SceneTree
const Scene = preload("res://Main.tscn")
var test_path := "user://db-restore-regression.json"

func _initialize() -> void:
	call_deferred("run")

func create_scene() -> Node:
	var scene = Scene.instantiate()
	scene.persistence_path = test_path
	scene.sending = false
	root.add_child(scene)
	scene.set_process(false)
	return scene

func wait_restore(scene: Node) -> void:
	for i in range(40):
		if not scene.restoring:
			return
		await create_timer(0.25).timeout
	assert(false, "Database restore timed out")

func run() -> void:
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	var scene = create_scene()
	await wait_restore(scene)
	assert(FileAccess.file_exists(test_path), "Fresh client must save restored state locally")
	# The existing database must contain a real checkpoint from running Godot.
	assert(scene.timeline.unix > 0 and scene.history.size() > 0, "Fresh client must recover database clock and chart")
	scene.timeline.unix += 3600
	scene.field_visuals[0].dust = 0.77
	var newer: float = scene.timeline.unix
	scene._save_local()
	scene.persistence_enabled = false
	scene.http.cancel_request()
	scene.queue_free()
	await process_frame
	var resumed = create_scene()
	await wait_restore(resumed)
	assert(resumed.has_local_state and resumed.timeline.unix == newer, "Newer local state must not be rolled back by older database checkpoint")
	assert(is_equal_approx(resumed.field_visuals[0].dust, 0.77), "Local contamination must survive restart")
	resumed.persistence_enabled = false
	resumed.http.cancel_request()
	resumed.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	print("DATABASE RESTORE PASS: fresh client recovery and newer local checkpoint precedence")
	quit(0)
