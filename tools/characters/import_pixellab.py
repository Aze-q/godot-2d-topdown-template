"""Import a completed PixelLab character ZIP as a Godot appearance; Python 3.11+, Pillow."""

import argparse
import hashlib
import io
import json
import re
import zipfile
from pathlib import Path

from PIL import Image


DIRECTIONS = {'south': 's', 'south-east': 'se', 'east': 'e', 'north-east': 'ne',
              'north': 'n', 'north-west': 'nw', 'west': 'w', 'south-west': 'sw'}


def import_character(archive_path, appearance_dir, project):
    record = json.loads((appearance_dir / 'production.json').read_text())
    settings = record['import_settings']
    resource_dir = 'res://' + appearance_dir.resolve().relative_to(project.resolve()).as_posix()
    clips, checks, canvas = {}, [], None
    with zipfile.ZipFile(archive_path) as archive:
        metadata = json.loads(archive.read('metadata.json'))
        states = [state for state in metadata['states'] if state['character']['id'] == record['character_id']]
        if len(states) != 1:
            raise ValueError('Export does not contain exactly one matching character state')
        exported = states[0]['frames']['animations']
        for action, name in settings['source_animation_names'].items():
            if not re.fullmatch(r'[a-z][a-z0-9_]*', action):
                raise ValueError('Invalid project action identifier')
            if name not in exported or set(exported[name]) != set(DIRECTIONS):
                raise ValueError(f'{action}: expected all eight directions; wait for the completed export')
            if settings['preview_fps'][action] <= 0:
                raise ValueError('Preview FPS must be positive')
            clips[action] = {}
            counts = set()
            for direction in DIRECTIONS:
                frames = []
                for source in exported[name][direction]:
                    data = archive.read(source)
                    frame = Image.open(io.BytesIO(data)).convert('RGBA')
                    canvas = canvas or frame.size
                    if frame.size != canvas or not frame.getbbox():
                        raise ValueError(f'Inconsistent canvas or empty frame: {source}')
                    bounds = frame.getbbox()
                    alpha = frame.getchannel('A').histogram()
                    checks.append({'action': action, 'direction': direction, 'frame': len(frames),
                                   'source': source, 'sha256': hashlib.sha256(data).hexdigest(),
                                   'canvas': frame.size, 'bounds': bounds,
                                   'partial_alpha_pixels': sum(alpha[1:255]),
                                   'touches_edge': 0 in bounds[:2] or bounds[2] == frame.width or bounds[3] == frame.height})
                    frames.append(frame)
                counts.add(len(frames))
                clips[action][direction] = frames
            if len(counts) != 1 or 0 in counts:
                raise ValueError(f'{action}: template frame counts must match across all directions')

    # Keep every source pixel and its original canvas position. Never recenter each
    # moving frame from its alpha bounds: doing so would erase intended body motion.
    width, height = canvas
    externals, textures, animations = [], [], []
    for action, directions in clips.items():
        count = len(directions['south'])
        sheet = Image.new('RGBA', (width * count, height * len(DIRECTIONS)))
        externals.append(f'[ext_resource type="Texture2D" path="{resource_dir}/{action}.png" id="{action}"]')
        for row, (direction, suffix) in enumerate(DIRECTIONS.items()):
            frame_refs = []
            for index, frame in enumerate(directions[direction]):
                sheet.paste(frame, (index * width, row * height))
                texture_id = f'{action}_{suffix}_{index}'
                textures.append(f'[sub_resource type="AtlasTexture" id="{texture_id}"]\natlas = ExtResource("{action}")\nregion = Rect2({index * width}, {row * height}, {width}, {height})')
                frame_refs.append('{"duration": 1.0, "texture": SubResource("' + texture_id + '")}')
            animations.append('{"frames": [' + ', '.join(frame_refs) + '], "loop": true, "name": &"' + action + '_' + suffix + '", "speed": ' + str(float(settings['preview_fps'][action])) + '}')
        sheet.save(appearance_dir / f'{action}.png')
    header = f'[gd_resource type="SpriteFrames" load_steps={1 + len(externals) + len(textures)} format=3]'
    (appearance_dir / 'sprite_frames.tres').write_text('\n\n'.join([header, *externals, *textures, '[resource]\nanimations = [' + ',\n'.join(animations) + ']']) + '\n')
    origin_x, origin_y = settings['ground_origin_px']
    appearance = '\n'.join([
        '[gd_resource type="Resource" script_class="PlayerAppearance" load_steps=3 format=3]', '',
        '[ext_resource type="Script" path="res://entities/player/player_appearance.gd" id="1"]',
        f'[ext_resource type="SpriteFrames" path="{resource_dir}/sprite_frames.tres" id="2"]', '',
        '[resource]', 'script = ExtResource("1")',
        'appearance_id = &' + json.dumps(record['appearance_id']),
        'sprite_frames = ExtResource("2")', f'display_scale = {float(settings["display_scale"])}',
        f'draw_offset = Vector2({-origin_x}, {-origin_y})', '',
    ])
    (appearance_dir / 'appearance.tres').write_text(appearance)
    report = {'source_archive': archive_path.name, 'archive_sha256': hashlib.sha256(archive_path.read_bytes()).hexdigest(),
              'frame_count': len(checks), 'frames': checks,
              'note': 'File validation only. Ground origin and preview rates require visual review; this does not accept the appearance.'}
    (appearance_dir / 'source/import_check.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Imported {len(checks)} frames, {len(animations)} directional clips; source canvas {width}x{height}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--appearance-dir', type=Path, required=True)
    parser.add_argument('--project', type=Path, default=Path.cwd())
    options = parser.parse_args()
    import_character(options.archive, options.appearance_dir, options.project)
