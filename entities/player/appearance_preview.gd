extends Node2D

@export_file("*.tres") var appearance_path := "res://entities/player/appearances/traveler_01/appearance.tres"

const DIRECTIONS := [Vector2.DOWN, Vector2(1, 1), Vector2.RIGHT, Vector2(1, -1), Vector2.UP, Vector2(-1, -1), Vector2.LEFT, Vector2(-1, 1)]
var visuals: Array[PlayerVisual] = []
var labels: Array[Label] = []
var heading: Label
var action_id: StringName = &"idle"
var elapsed := 0.0
var paused := false

func _ready() -> void:
	get_window().content_scale_size = Vector2i(800, 480)
	get_window().size = Vector2i(800, 480)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--appearance="):
			appearance_path = argument.trim_prefix("--appearance=")
	heading = _label(Vector2(12, 4), "CANDIDATE PREVIEW | Space: idle/run | P: pause\nArtwork needs review; no combat, collision or networking")
	if not ResourceLoader.exists(appearance_path):
		heading.text = "Missing appearance resource:\n" + appearance_path
		push_error(heading.text)
		set_process(false)
		return
	var data := load(appearance_path) as PlayerAppearance
	if not data or not data.sprite_frames:
		heading.text = "Invalid PlayerAppearance: " + appearance_path
		push_error(heading.text)
		set_process(false)
		return
	for index in DIRECTIONS.size():
		var visual := PlayerVisual.new()
		visual.position = Vector2(100 + (index % 4) * 200, 215 + floori(index / 4.0) * 220)
		add_child(visual)
		visual.apply_appearance(data)
		visuals.append(visual)
		labels.append(_label(visual.position + Vector2(-32, 2), ""))

func _label(at: Vector2, text: String) -> Label:
	var label := Label.new()
	label.position = at
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	add_child(label)
	return label

func _process(delta: float) -> void:
	if not paused:
		elapsed += delta
	for index in visuals.size():
		var available := visuals[index].sample_visual(action_id, DIRECTIONS[index], elapsed)
		labels[index].text = "%s %s%s" % [action_id, PlayerVisual.direction_id(DIRECTIONS[index]), "" if available else " MISSING"]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			action_id = &"run" if action_id == &"idle" else &"idle"
			elapsed = 0.0
		if event.keycode == KEY_P:
			paused = not paused

func _draw() -> void:
	draw_rect(Rect2(0, 0, 800, 480), Color("20252c"))
	for index in DIRECTIONS.size():
		var origin := Vector2(100 + (index % 4) * 200, 215 + floori(index / 4.0) * 220)
		draw_line(origin - Vector2(60, 0), origin + Vector2(60, 0), Color("59616c"))
