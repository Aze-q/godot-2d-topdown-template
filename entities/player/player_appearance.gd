class_name PlayerAppearance
extends Resource

@export var appearance_id: StringName
@export var sprite_frames: SpriteFrames
@export_range(0.01, 8.0) var display_scale := 1.0
## Image top-left relative to the ground origin, in source-image pixels.
@export var draw_offset := Vector2.ZERO
@export var material: Material
