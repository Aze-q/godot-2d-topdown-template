class_name PlayerVisual
extends Node2D

const DIRECTIONS := [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]

var appearance: PlayerAppearance
var sprite := AnimatedSprite2D.new()
var facing := Vector2.DOWN

func _init() -> void:
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)

func apply_appearance(data: PlayerAppearance) -> void:
	appearance = data
	sprite.stop()
	sprite.visible = false
	sprite.sprite_frames = data.sprite_frames
	sprite.scale = Vector2.ONE * data.display_scale
	sprite.offset = data.draw_offset
	# Frames are shared read-only; shader parameters belong to this instance.
	sprite.material = data.material.duplicate() if data.material else null

static func direction_id(direction: Vector2) -> StringName:
	return DIRECTIONS[posmod(roundi(direction.angle() / (PI / 4.0)), 8)]

## The caller owns action time. This method never plays or resolves gameplay.
## Missing actions are explicit: hide the sprite and return false.
func sample_visual(action_id: StringName, direction: Vector2, elapsed_seconds: float) -> bool:
	if not appearance or not appearance.sprite_frames:
		return false
	if not direction.is_zero_approx():
		facing = direction.normalized()
	var animation_id := StringName("%s_%s" % [action_id, direction_id(facing)])
	var frames := appearance.sprite_frames
	if not frames.has_animation(animation_id) or frames.get_frame_count(animation_id) == 0:
		sprite.visible = false
		return false
	sprite.pause()
	sprite.animation = animation_id
	sprite.visible = true
	var total := 0.0
	for index in frames.get_frame_count(animation_id):
		total += frames.get_frame_duration(animation_id, index)
	var cursor := maxf(0.0, elapsed_seconds) * frames.get_animation_speed(animation_id)
	if frames.get_animation_loop(animation_id):
		cursor = fposmod(cursor, total)
	else:
		cursor = minf(cursor, total)
	for index in frames.get_frame_count(animation_id):
		var duration := frames.get_frame_duration(animation_id, index)
		if cursor < duration or index == frames.get_frame_count(animation_id) - 1:
			sprite.set_frame_and_progress(index, clampf(cursor / duration, 0.0, 1.0))
			break
		cursor -= duration
	return true
