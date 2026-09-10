extends Node2D

const Rig = preload("res://entities/player/rig_trial_character.gd")
const SIZE := Vector2i(1100, 760)
var rigs: Array = []
var frames: Array[PlayerVisual] = []
var missing: Array[Label] = []
var heading: Label
var elapsed := 0.0
var action := "run"
var paused := false
var backward := false
var capture_path := ""
var capture_time := 0.18
var capture_frames := 0

func _ready() -> void:
	get_window().content_scale_size = SIZE
	get_window().size = SIZE
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		if argument.begins_with("--action="):
			action = argument.trim_prefix("--action=")
		if argument.begins_with("--time="):
			capture_time = float(argument.trim_prefix("--time="))
		if argument == "--bones":
			paused = true
	heading = _label(Vector2(24, 12), "", 23)
	_label(Vector2(24, 48), "1 Run   2 Sword (replay)   3 Bow + legs   4 Idle   P Pause   B Bones   R Reverse legs", 16)
	_label(Vector2(24, 76), "TECHNICAL TRIAL | Original flat art: hidden areas unpainted; joint gaps are expected.", 15)
	_label(Vector2(170, 120), "EXISTING SPRITE FRAMES", 18)
	_label(Vector2(655, 120), "LIVE SKELETON2D / 11 PIECES", 18)
	var appearance := load("res://entities/player/appearances/traveler_01/appearance.tres") as PlayerAppearance
	for index in 2:
		var y := 410.0 + index * 280.0
		var visual := PlayerVisual.new()
		visual.position = Vector2(310, y)
		add_child(visual)
		visual.apply_appearance(appearance)
		frames.append(visual)
		var rig = Rig.new()
		rig.position = Vector2(815, y)
		add_child(rig)
		rig.build("se" if index == 0 else "ne")
		rig.show_bones = paused
		rigs.append(rig)
		_label(Vector2(28, y - 134), "SE\nfront" if index == 0 else "NE\nback", 18)
		missing.append(_label(Vector2(155, y - 126), "", 15))
	_label(Vector2(24, 717), "Same native source scale / same run cycle. Sword & bow are rig-only studies; no matching frame assets.", 14)
	_label(Vector2(24, 739), "Bow: upper/lower independence only; no two-hand IK, full strafe gait, hit detection or game integration.", 14)
	if not capture_path.is_empty():
		elapsed = capture_time
		paused = true

func _label(at: Vector2, text: String, size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	add_child(label)
	return label

func _process(delta: float) -> void:
	if not paused:
		elapsed += delta
	heading.text = "ANIMATION COMPARISON  /  %s%s" % [action.to_upper(), "  PAUSED" if paused else ""]
	for index in 2:
		var direction := Vector2(1, 1) if index == 0 else Vector2(1, -1)
		var available := frames[index].sample_visual(StringName(action), direction, elapsed)
		missing[index].text = "" if available else "No generated %s frames\nComparison not available" % action
		rigs[index].sample_visual(action, elapsed, backward)
	if not capture_path.is_empty():
		capture_frames += 1
		if capture_frames == 8:
			_capture.call_deferred()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(capture_path)
	print("RIG_TRIAL_CAPTURE ", capture_path, " error=", error)
	get_tree().quit(error)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: action = "run"; elapsed = 0.0
		KEY_2: action = "sword"; elapsed = 0.0
		KEY_3: action = "bow"; elapsed = 0.0
		KEY_4: action = "idle"; elapsed = 0.0
		KEY_P: paused = not paused
		KEY_R: backward = not backward
		KEY_B:
			for rig in rigs:
				rig.show_bones = not rig.show_bones

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), Color("20252c"))
	draw_line(Vector2(550, 116), Vector2(550, 702), Color("465362"))
	for y in [410, 690]:
		for x in [310, 815]:
			draw_line(Vector2(x - 130, y), Vector2(x + 130, y), Color("566676"))
