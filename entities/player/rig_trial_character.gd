extends Node2D
## Experimental cutout: original pixels, rigid weights, no hidden-area repaint.
## The caller owns time. This scene has no movement, damage or network authority.

const ORIGIN := Vector2(90, 174)
const PERIOD := 2.0 / 3.0
static var shared_library: AnimationLibrary

var skeleton := Skeleton2D.new()
var bones: Dictionary = {}
var pieces: Array[Polygon2D] = []
var lower := AnimationPlayer.new()
var upper := AnimationPlayer.new()
var grip := Marker2D.new()
var sword := Line2D.new()
var bow := Line2D.new()
var string_line := Line2D.new()
var bone_overlay := Node2D.new()
var show_bones := false
var direction_id := "se"

func build(direction: String) -> void:
	direction_id = direction
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	skeleton.name = "Skeleton"
	skeleton.position = -ORIGIN
	add_child(skeleton)
	# Provisional pivots. Rear view swaps projected limb sides, not texture pixels;
	# each view still needs an art-specific pivot and perspective pass.
	_bone("Hips", "", Vector2(90, 117))
	_bone("Chest", "Hips", Vector2(90, 80))
	_bone("Head", "Chest", Vector2(90, 62))
	_bone("ArmL", "Chest", Vector2(80, 70))
	_bone("ForearmL", "ArmL", Vector2(75, 91))
	_bone("ArmR", "Chest", Vector2(99, 70))
	_bone("ForearmR", "ArmR", Vector2(104, 91))
	_bone("ThighL", "Hips", Vector2(83, 120))
	_bone("ShinL", "ThighL", Vector2(78, 146))
	_bone("ThighR", "Hips", Vector2(96, 120))
	_bone("ShinR", "ThighR", Vector2(95, 146))
	var texture := load("res://entities/player/appearances/traveler_01/rig_trial/%s.png" % direction) as Texture2D
	# These partitions reconstruct the flat source at rest. Moving them reveals
	# occluded pixels the source does not contain; do not hide that art limitation.
	_piece("Head", [0, 0, 180, 0, 180, 62, 0, 62], texture, 4)
	_piece("Chest", [82, 62, 100, 62, 101, 90, 101, 113, 81, 113, 80, 90], texture, 2)
	_piece("Hips", [81, 113, 101, 113, 101, 123, 81, 123], texture, 1)
	_piece("ArmL", [0, 62, 82, 62, 80, 90, 0, 90], texture, 3 if direction == "se" else 0)
	_piece("ForearmL", [0, 90, 80, 90, 81, 113, 81, 123, 0, 123], texture, 4 if direction == "se" else 0)
	_piece("ArmR", [100, 62, 180, 62, 180, 90, 101, 90], texture, 0 if direction == "se" else 3)
	_piece("ForearmR", [101, 90, 180, 90, 180, 123, 101, 123, 101, 113], texture, 0 if direction == "se" else 4)
	_piece("ThighL", [0, 123, 88, 123, 88, 146, 0, 146], texture, 0)
	_piece("ShinL", [0, 146, 88, 146, 88, 180, 0, 180], texture, 0)
	_piece("ThighR", [88, 123, 180, 123, 180, 146, 88, 146], texture, 0)
	_piece("ShinR", [88, 146, 180, 146, 180, 180, 88, 180], texture, 0)
	if shared_library == null:
		shared_library = _make_library()
	for player in [lower, upper]:
		add_child(player)
		player.add_animation_library("", shared_library)
	grip.name = "Grip"
	bones.ForearmL.add_child(grip)
	grip.position = Vector2(0, 23)
	grip.z_index = 5
	grip.add_child(sword)
	sword.points = PackedVector2Array([Vector2(0, 5), Vector2(0, -34)])
	sword.width = 3
	sword.default_color = Color("cedae4")
	grip.add_child(bow)
	bow.points = PackedVector2Array([Vector2(0, -22), Vector2(10, -10), Vector2(12, 0), Vector2(10, 10), Vector2(0, 22)])
	bow.width = 2
	bow.default_color = Color("b88d59")
	grip.add_child(string_line)
	string_line.points = PackedVector2Array([Vector2(0, -22), Vector2(-9, 0), Vector2(0, 22)])
	string_line.width = 1
	string_line.default_color = Color("ded6b5")
	add_child(bone_overlay)
	bone_overlay.z_index = 20
	bone_overlay.draw.connect(_draw_bones)
	sample_visual("idle", 0.0)

func _bone(id: String, parent_id: String, at: Vector2) -> void:
	if direction_id == "ne" and (id.ends_with("L") or id.ends_with("R")):
		at.x = 180.0 - at.x
	var bone := Bone2D.new()
	bone.name = id
	bone.set_autocalculate_length_and_angle(false)
	bone.set_length(15)
	var parent: Node2D = skeleton if parent_id.is_empty() else bones[parent_id]
	parent.add_child(bone)
	bone.position = at if parent == skeleton else at - skeleton.to_local(parent.global_position)
	bone.rest = bone.transform
	bones[id] = bone

func _piece(id: String, coordinates: Array, texture: Texture2D, layer: int) -> void:
	var polygon := Polygon2D.new()
	polygon.name = id + "Pixels"
	var points := PackedVector2Array()
	for i in range(0, coordinates.size(), 2):
		points.append(Vector2(coordinates[i], coordinates[i + 1]))
	polygon.polygon = points
	polygon.uv = points
	polygon.texture = texture
	polygon.position = -ORIGIN
	polygon.z_index = layer
	add_child(polygon)
	polygon.skeleton = polygon.get_path_to(skeleton)
	var weights := PackedFloat32Array()
	weights.resize(points.size())
	weights.fill(1.0)
	var bone_id := id
	if direction_id == "ne" and (id.ends_with("L") or id.ends_with("R")):
		bone_id = id.substr(0, id.length() - 1) + ("R" if id.ends_with("L") else "L")
	polygon.add_bone(skeleton.get_path_to(bones[bone_id]), weights)
	pieces.append(polygon)

func _make_library() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	# Rotation tracks are shared across the compatible two-view rest hierarchies.
	# They demonstrate reuse, not perspective-correct final eight-view motion.
	var clips := {
		"lower_idle": {"ThighL": [0, 0, 0, 0, 0], "ShinL": [0, 0, 0, 0, 0], "ThighR": [0, 0, 0, 0, 0], "ShinR": [0, 0, 0, 0, 0]},
		"upper_idle": {"Chest": [0, 1, 0, -1, 0], "Head": [0, -1, 0, 1, 0]},
		"lower_run": {"ThighL": [-18, 0, 18, 0, -18], "ShinL": [12, 32, 8, 0, 12], "ThighR": [18, 0, -18, 0, 18], "ShinR": [8, 0, 12, 32, 8]},
		"upper_run": {"Chest": [-2, 0, 2, 0, -2], "Head": [2, 0, -2, 0, 2], "ArmL": [16, 0, -16, 0, 16], "ForearmL": [-18, -22, -26, -22, -18], "ArmR": [-16, 0, 16, 0, -16], "ForearmR": [-26, -22, -18, -22, -26]},
		"upper_sword": {"Chest": [0, -8, 10, 4, 0], "Head": [0, 4, -4, 0, 0], "ArmL": [0, 62, -52, -18, 0], "ForearmL": [0, -48, 12, 6, 0], "ArmR": [0, -8, 8, 0, 0]},
		"upper_bow": {"Chest": [0, 0, 0, 0, 0], "Head": [0, 0, 0, 0, 0], "ArmL": [-55, -55, -55, -55, -55], "ForearmL": [-15, -15, -15, -15, -15], "ArmR": [42, 42, 42, 42, 42], "ForearmR": [-78, -78, -78, -78, -78]}
	}
	for clip_id in clips:
		var animation := Animation.new()
		animation.length = PERIOD
		animation.loop_mode = Animation.LOOP_LINEAR if clip_id != "upper_sword" else Animation.LOOP_NONE
		for bone_id in clips[clip_id]:
			var track := animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(track, NodePath(str(get_path_to(bones[bone_id])) + ":rotation"))
			var values: Array = clips[clip_id][bone_id]
			for index in values.size():
				animation.track_insert_key(track, index * PERIOD / 4.0, deg_to_rad(float(values[index])))
		library.add_animation(clip_id, animation)
	return library

func _sample(player: AnimationPlayer, clip: String, time: float) -> void:
	player.play(clip)
	player.pause()
	player.seek(time, true)

func sample_visual(action: String, elapsed: float, backward := false) -> void:
	for bone: Bone2D in bones.values():
		bone.apply_rest()
	var phase := fposmod(elapsed, PERIOD)
	var leg_phase := fposmod(-elapsed, PERIOD) if backward else phase
	_sample(lower, "lower_run" if action in ["run", "bow"] else "lower_idle", leg_phase)
	var upper_clip := "upper_" + action
	_sample(upper, upper_clip, minf(elapsed, PERIOD) if action == "sword" else phase)
	sword.visible = action == "sword"
	bow.visible = action == "bow"
	string_line.visible = action == "bow"
	bone_overlay.queue_redraw()

func _draw_bones() -> void:
	if not show_bones:
		return
	for bone: Bone2D in bones.values():
		var at := to_local(bone.global_position)
		if bone.get_parent() is Bone2D:
			bone_overlay.draw_line(at, to_local(bone.get_parent().global_position), Color("68ebd2"), 1)
		bone_overlay.draw_circle(at, 2, Color("fff097"))
