"""
Decimate a GLB model while preserving textures and materials.
Strategy: decimate each mesh primitive individually via pymeshlab,
then reassemble the scene with original materials via trimesh.
"""
import trimesh
import pymeshlab
import numpy as np
import os
import tempfile

INPUT_PATH = r"C:\Users\ozany\Downloads\super_destroyer_helldivers_zeo.glb"
OUTPUT_DIR = r"E:\Games\SpaceGame\assets\models\ships\super_destroyer"

LODS = [
    ("super_destroyer_lod0.glb", 0.02),   # 2% of original faces per mesh
    ("super_destroyer_lod1.glb", 0.004),   # 0.4% of original faces per mesh
]


def decimate_mesh(mesh: trimesh.Trimesh, ratio: float) -> trimesh.Trimesh:
    """Decimate a single trimesh using pymeshlab, preserving UVs."""
    if mesh.faces.shape[0] < 10:
        return mesh

    target_faces = max(4, int(mesh.faces.shape[0] * ratio))
    if target_faces >= mesh.faces.shape[0]:
        return mesh

    with tempfile.TemporaryDirectory() as tmpdir:
        # Export to PLY with vertex attributes
        ply_in = os.path.join(tmpdir, "in.ply")
        ply_out = os.path.join(tmpdir, "out.ply")
        mesh.export(ply_in, file_type='ply')

        ms = pymeshlab.MeshSet()
        ms.load_new_mesh(ply_in)

        ms.apply_filter('meshing_decimation_quadric_edge_collapse',
                         targetfacenum=target_faces,
                         qualitythr=1.0,
                         preserveboundary=True,
                         preservenormal=True,
                         preservetopology=False,
                         planarquadric=True,
                         autoclean=True)

        ms.save_current_mesh(ply_out)
        decimated = trimesh.load(ply_out, file_type='ply', process=False)

        return decimated


def process_scene(input_path: str, ratio: float, output_path: str):
    """Load GLB scene, decimate each geometry, export with materials."""
    print(f"\nLoading {os.path.basename(input_path)}...")
    scene = trimesh.load(input_path, force='scene')

    total_faces_before = 0
    total_faces_after = 0
    geom_count = len(scene.geometry)
    print(f"  {geom_count} geometries found")

    # Decimate each geometry individually
    new_geometry = {}
    for i, (name, geom) in enumerate(scene.geometry.items()):
        if not isinstance(geom, trimesh.Trimesh):
            new_geometry[name] = geom
            continue

        faces_before = geom.faces.shape[0]
        total_faces_before += faces_before

        decimated = decimate_mesh(geom, ratio)
        faces_after = decimated.faces.shape[0]
        total_faces_after += faces_after

        # Preserve original material/texture reference
        if hasattr(geom, 'visual') and hasattr(geom.visual, 'material'):
            try:
                mat = geom.visual.material
                decimated.visual = trimesh.visual.TextureVisuals(material=mat)
            except Exception:
                pass  # If material transfer fails, keep whatever visual we have

        new_geometry[name] = decimated

        if (i + 1) % 20 == 0 or i == geom_count - 1:
            print(f"  Processed {i + 1}/{geom_count} meshes...")

    print(f"  Total: {total_faces_before:,} -> {total_faces_after:,} faces "
          f"({total_faces_after / max(1, total_faces_before) * 100:.1f}%)")

    # Replace geometry in scene
    scene.geometry = new_geometry

    # Export as GLB
    glb_data = scene.export(file_type='glb')
    with open(output_path, 'wb') as f:
        f.write(glb_data)

    size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"  Saved: {output_path} ({size_mb:.1f} MB)")


if __name__ == "__main__":
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for filename, ratio in LODS:
        print(f"\n{'='*60}")
        print(f"--- {filename} (ratio: {ratio}) ---")
        output_path = os.path.join(OUTPUT_DIR, filename)
        process_scene(INPUT_PATH, ratio, output_path)

    print(f"\n{'='*60}")
    print("Done!")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        if f.endswith('.glb') and 'temp' not in f:
            p = os.path.join(OUTPUT_DIR, f)
            size = os.path.getsize(p) / (1024 * 1024)
            print(f"  {f}: {size:.1f} MB")
