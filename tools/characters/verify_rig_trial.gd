extends SceneTree
## Technical checks only: this does not approve the cutout artwork or combat.

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
		printerr("FAIL: ", description)

func _pose(character: Node2D) -> Dictionary:
	var result := {}
	for id in character.bones:
		result[id] = character.bones[id].global_transform
	return result

func _same_pose(left: Dictionary, right: Dictionary) -> bool:
	for id in left:
		if not left[id].is_equal_approx(right[id]):
			return false
	return true

func _surface_state(character: Node2D) -> Array:
	var result := []
	for polygon in character.pieces:
		result.append([polygon.global_transform, polygon.texture.get_rid(), polygon.polygon, polygon.uv])
	return result

func _valid_binding(character: Node2D) -> bool:
	if character.skeleton.get_bone_count() != 11 or character.pieces.size() != 11:
		return false
	for polygon: Polygon2D in character.pieces:
		if polygon.get_node_or_null(polygon.skeleton) != character.skeleton:
			return false
		if polygon.get_bone_count() != 1 or polygon.uv.size() != polygon.polygon.size():
			return false
		var bone := character.skeleton.get_node_or_null(polygon.get_bone_path(0)) as Bone2D
		if bone == null or bone.get_index_in_skeleton() < 0:
			return false
		var weights := polygon.get_bone_weights(0)
		if weights.size() != polygon.polygon.size():
			return false
		for weight in weights:
			if not is_equal_approx(weight, 1.0):
				return false
	return true

func _run() -> void:
	var rig_script := load("res://entities/player/rig_trial_character.gd") as Script
	if rig_script == null or not rig_script.can_instantiate():
		printerr("FAIL: rig script cannot instantiate")
		quit(1)
		return
	var first: Node2D = rig_script.new()
	var second: Node2D = rig_script.new()
	root.add_child(first)
	root.add_child(second)
	first.build("se")
	second.build("ne")
	await process_frame
	await process_frame
	_check(_valid_binding(first) and _valid_binding(second), "Both views have registered bones, valid polygon bindings, UVs and rigid weights")
	var library: AnimationLibrary = first.lower.get_animation_library("")
	_check(library == first.upper.get_animation_library("") and library == second.lower.get_animation_library("") and library == second.upper.get_animation_library(""), "Both views and body layers share one AnimationLibrary resource")
	var expected: Array[StringName] = [&"lower_idle", &"lower_run", &"upper_bow", &"upper_idle", &"upper_run", &"upper_sword"]
	_check(library.get_animation_list() == expected, "Shared library contains exactly the six intended clips")
	_check(first.bones.Chest != second.bones.Chest and first.lower != second.lower and first.upper != second.upper, "Bone and animation playback state belong to each instance")
	var initial_surfaces := _surface_state(first)
	var second_pose := _pose(second)
	var all_deterministic := true
	var no_history := true
	for action in ["idle", "run", "sword", "bow"]:
		first.sample_visual(action, 0.11)
		var expected_pose := _pose(first)
		first.sample_visual(action, 0.11)
		all_deterministic = all_deterministic and _same_pose(expected_pose, _pose(first))
		first.sample_visual("bow" if action != "bow" else "sword", 0.37)
		first.sample_visual(action, 0.11)
		no_history = no_history and _same_pose(expected_pose, _pose(first))
	_check(all_deterministic, "Repeated sampling at the same action and time is deterministic")
	_check(no_history, "Returning from another action does not leave stale bone poses")
	_check(_same_pose(second_pose, _pose(second)), "Sampling the first instance does not change the second instance")
	first.sample_visual("run", 0.07)
	var early_pose := _pose(first)
	first.sample_visual("run", 0.28)
	_check(not _same_pose(early_pose, _pose(first)), "Run animation changes actual bone global transforms")
	_check(initial_surfaces == _surface_state(first), "Animation keeps polygon transforms, texture RIDs, vertices and UVs unchanged")
	first.sample_visual("bow", 0.07)
	var bow_pose := _pose(first)
	first.sample_visual("bow", 0.28)
	var fixed_upper := true
	var moving_lower := false
	for id in ["Chest", "Head", "ArmL", "ForearmL", "ArmR", "ForearmR"]:
		fixed_upper = fixed_upper and bow_pose[id].is_equal_approx(first.bones[id].global_transform)
	for id in ["ThighL", "ShinL", "ThighR", "ShinR"]:
		moving_lower = moving_lower or not bow_pose[id].is_equal_approx(first.bones[id].global_transform)
	_check(fixed_upper and moving_lower, "Bow aiming keeps the upper body steady while the lower body moves")
	var held_pose := _pose(first)
	await process_frame
	await process_frame
	_check(_same_pose(held_pose, _pose(first)), "Playback does not advance independently of caller sampling")
	first.free()
	second.free()
	print("RIG TRIAL: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
