"""
Decimate a GLB model via: trimesh (load GLB) -> PLY -> pymeshlab (decimate) -> trimesh (save GLB).
"""
import trimesh
import pymeshlab
import numpy as np
import os
import tempfile

INPUT_PATH = r"C:\Users\ozany\Downloads\super_destroyer_helldivers_zeo.glb"
OUTPUT_DIR = r"E:\Games\SpaceGame\assets\models\ships\super_destroyer"

LODS = [
    ("super_destroyer_lod0.glb", 50000),
    ("super_destroyer_lod1.glb", 10000),
]


def load_and_merge_glb(path):
    """Load GLB, merge all meshes, clean up."""
    print(f"Loading {os.path.basename(path)}...")
    scene = trimesh.load(path, force='scene')

    meshes = []
    for name, geom in scene.geometry.items():
        if isinstance(geom, trimesh.Trimesh):
            meshes.append(geom)

    print(f"  {len(meshes)} meshes")
    combined = trimesh.util.concatenate(meshes)
    print(f"  Combined: {combined.vertices.shape[0]:,} verts, {combined.faces.shape[0]:,} faces")

    combined.merge_vertices(merge_tex=True, merge_norm=True)
    mask = combined.nondegenerate_faces()
    combined.update_faces(mask)
    print(f"  Cleaned: {combined.vertices.shape[0]:,} verts, {combined.faces.shape[0]:,} faces")
    return combined


def decimate_via_pymeshlab(mesh, target_faces, output_glb_path):
    """Save to PLY, decimate in pymeshlab, reload and save as GLB."""
    with tempfile.TemporaryDirectory() as tmpdir:
        ply_in = os.path.join(tmpdir, "input.ply")
        ply_out = os.path.join(tmpdir, "output.ply")

        # Export from trimesh to PLY
        print(f"  Exporting to PLY...")
        mesh.export(ply_in, file_type='ply')

        # Load in pymeshlab and decimate
        print(f"  Loading in pymeshlab...")
        ms = pymeshlab.MeshSet()
        ms.load_new_mesh(ply_in)

        m = ms.current_mesh()
        print(f"  pymeshlab sees: {m.vertex_number():,} verts, {m.face_number():,} faces")

        print(f"  Decimating to {target_faces:,} faces...")
        ms.apply_filter('meshing_decimation_quadric_edge_collapse',
                         targetfacenum=target_faces,
                         qualitythr=1.0,
                         preserveboundary=False,
                         preservenormal=False,
                         preservetopology=False,
                         planarquadric=True,
                         autoclean=True)

        m = ms.current_mesh()
        print(f"  Result: {m.vertex_number():,} verts, {m.face_number():,} faces")

        # Save decimated PLY
        ms.save_current_mesh(ply_out)

        # Reload in trimesh and save as GLB
        decimated = trimesh.load(ply_out, file_type='ply')
        decimated.fix_normals()
        scene = trimesh.Scene()
        scene.add_geometry(decimated, node_name="SuperDestroyer")
        glb_bytes = scene.export(file_type='glb')
        with open(output_glb_path, 'wb') as f:
            f.write(glb_bytes)

        size_mb = os.path.getsize(output_glb_path) / (1024 * 1024)
        print(f"  Saved: {output_glb_path} ({size_mb:.1f} MB)")


if __name__ == "__main__":
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    combined = load_and_merge_glb(INPUT_PATH)

    for filename, target in LODS:
        print(f"\n--- {filename} (target: {target:,} faces) ---")
        output_path = os.path.join(OUTPUT_DIR, filename)
        decimate_via_pymeshlab(combined, target, output_path)

    print(f"\n{'='*60}")
    print("Done!")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        if f.endswith('.glb') and 'temp' not in f and 'original' not in f:
            p = os.path.join(OUTPUT_DIR, f)
            size = os.path.getsize(p) / (1024 * 1024)
            print(f"  {f}: {size:.1f} MB")
