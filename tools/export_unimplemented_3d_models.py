"""Export the Blender 5.x source models that do not yet have Godot scenes.

Run with the Steam installation of Blender:

    blender --background --factory-startup --python tools/export_unimplemented_3d_models.py

Pass ``-- --report-only`` to inspect the files without writing output assets.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = PROJECT_ROOT / "assets" / "3DModel"

# Source filename: (Godot asset stem, root node name)
MODELS = {
    "PC.blend": ("pc", "PC"),
    "エレベーター.blend": ("elevator", "Elevator"),
    "エレベーター扉.blend": ("elevator_door", "ElevatorDoor"),
    "ブレーカー.blend": ("breaker", "Breaker"),
    "ロッカー.blend": ("locker", "Locker"),
    "ロッカー扉.blend": ("locker_door", "LockerDoor"),
    "床長.blend": ("floor_long", "FloorLong"),
    "柱細.blend": ("pillar_thin", "PillarThin"),
    "柱大.blend": ("pillar_large", "PillarLarge"),
    "柱中.blend": ("pillar_medium", "PillarMedium"),
    "天井(長ライト付).blend": ("ceiling_long_with_light", "CeilingLongWithLight"),
    "天井(長ライト無).blend": ("ceiling_long_without_light", "CeilingLongWithoutLight"),
    "壁短.blend": ("wall_short", "WallShort"),
    "壁長.blend": ("wall_long", "WallLong"),
    "廊下床.blend": ("corridor_floor", "CorridorFloor"),
    "廊下天井.blend": ("corridor_ceiling", "CorridorCeiling"),
    "廊下天井ライト無.blend": (
        "corridor_ceiling_without_light",
        "CorridorCeilingWithoutLight",
    ),
    "廊下壁.blend": ("corridor_wall", "CorridorWall"),
}

LIGHT_MODEL_STEMS = {"ceiling_long_with_light", "corridor_ceiling"}


def object_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    """Return the world-space bounds of the supplied mesh objects."""
    points = [
        obj.matrix_world @ Vector(corner)
        for obj in objects
        for corner in obj.bound_box
    ]
    if not points:
        raise RuntimeError("scene contains no renderable mesh objects")

    minimum = Vector(min(point[axis] for point in points) for axis in range(3))
    maximum = Vector(max(point[axis] for point in points) for axis in range(3))
    return minimum, maximum


def scene_meshes() -> list[bpy.types.Object]:
    return [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "MESH" and not obj.hide_render
    ]


def blender_to_godot(vector: Vector) -> Vector:
    """Match Blender's Z-up to the glTF/Godot Y-up conversion."""
    return Vector((vector.x, vector.z, -vector.y))


def number(value: float) -> str:
    value = 0.0 if abs(value) < 0.000001 else value
    return f"{value:.6f}".rstrip("0").rstrip(".") or "0"


def vector3(vector: Vector) -> str:
    return f"Vector3({number(vector.x)}, {number(vector.y)}, {number(vector.z)})"


def make_tscn(
    asset_stem: str,
    root_name: str,
    minimum: Vector,
    maximum: Vector,
    light_positions: list[Vector],
) -> str:
    center = blender_to_godot((minimum + maximum) * 0.5)
    blender_size = maximum - minimum
    size = blender_to_godot(blender_size)
    size = Vector((max(abs(size.x), 0.01), max(abs(size.y), 0.01), max(abs(size.z), 0.01)))

    scene = f'''[gd_scene load_steps=4 format=3]

[ext_resource type="PackedScene" path="res://assets/3DModel/{asset_stem}.glb" id="1_model"]
[ext_resource type="Script" path="res://world_surface.gd" id="2_script"]

[sub_resource type="BoxShape3D" id="BoxShape_model"]
size = {vector3(size)}

[node name="{root_name}" type="StaticBody3D"]
collision_layer = 4
collision_mask = 0
script = ExtResource("2_script")

[node name="Model" parent="." instance=ExtResource("1_model")]

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
position = {vector3(center)}
shape = SubResource("BoxShape_model")
'''

    for index, blender_position in enumerate(light_positions, start=1):
        node_name = "AreaLight3D" if index == 1 else f"AreaLight3D{index}"
        position = blender_to_godot(blender_position)
        scene += f'''

[node name="{node_name}" type="AreaLight3D" parent="." groups=["lights"]]
transform = Transform3D(1, 0, 0, 0, -0.00000004371139, 1, 0, -1, -0.00000004371139, {number(position.x)}, {number(position.y)}, {number(position.z)})
layers = 4
light_energy = 2.0
area_range = 15.0
'''

    return scene


def describe(source_name: str, minimum: Vector, maximum: Vector) -> None:
    print(
        "MODEL_INFO "
        + json.dumps(
            {
                "source": source_name,
                "blender_version": bpy.app.version_string,
                "objects": [
                    {
                        "name": obj.name,
                        "type": obj.type,
                        "dimensions": [round(value, 4) for value in obj.dimensions],
                    }
                    for obj in bpy.context.scene.objects
                ],
                "bounds_min": [round(value, 4) for value in minimum],
                "bounds_max": [round(value, 4) for value in maximum],
            },
            ensure_ascii=False,
        )
    )


def main() -> None:
    if bpy.app.version < (5, 0, 0):
        raise RuntimeError(
            f"Blender 5.0 or newer is required; running {bpy.app.version_string}"
        )

    report_only = "--report-only" in sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else False
    missing = [source_name for source_name in MODELS if not (MODEL_DIR / source_name).is_file()]
    if missing:
        raise FileNotFoundError(f"missing source models: {missing}")

    for source_name, (asset_stem, root_name) in MODELS.items():
        source_path = MODEL_DIR / source_name
        bpy.ops.wm.open_mainfile(filepath=str(source_path))
        meshes = scene_meshes()
        visual_minimum, visual_maximum = object_bounds(meshes)
        describe(source_name, visual_minimum, visual_maximum)

        if report_only:
            continue

        glb_path = MODEL_DIR / f"{asset_stem}.glb"
        tscn_path = MODEL_DIR / f"{asset_stem}.tscn"
        collision_meshes = meshes
        light_positions: list[Vector] = []
        if asset_stem in LIGHT_MODEL_STEMS:
            collision_meshes = [max(meshes, key=lambda obj: obj.dimensions.x * obj.dimensions.y * obj.dimensions.z)]
            light_positions = [
                obj.matrix_world.translation.copy()
                for obj in meshes
                if obj.name.startswith("球")
            ]
        collision_minimum, collision_maximum = object_bounds(collision_meshes)

        bpy.ops.export_scene.gltf(
            filepath=str(glb_path),
            export_format="GLB",
            export_yup=True,
            export_cameras=False,
            export_lights=True,
        )
        tscn_path.write_text(
            make_tscn(
                asset_stem,
                root_name,
                collision_minimum,
                collision_maximum,
                light_positions,
            ),
            encoding="utf-8",
            newline="\n",
        )
        print(f"EXPORTED {source_name} -> {glb_path.name}, {tscn_path.name}")


if __name__ == "__main__":
    main()
