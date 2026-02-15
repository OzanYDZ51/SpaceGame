"""
Convert Babbage Station OBJ parts into a single GLB file for Godot 4.
Uses trimesh for geometry and pygltflib for GLB assembly.
Generates box-projected UVs and embeds texture images for PBR materials.

Fixes:
- doubleSided only on thin geometry (solar panels, fins) to prevent z-fighting
- All blue panels now have hull texture (no flat untextured blue blocks)
- Docking Bay texture used for bay/docking internals
- Duplicate geometry detection between OBJ parts
"""

import trimesh
import numpy as np
from pathlib import Path

SRC_DIR = Path(r"C:\Users\ozany\Downloads\Babbage Station")
OUT_PATH = Path(r"E:\Games\SpaceGame\assets\models\babbage_station.glb")

OBJ_PARTS = [
    "Hanger.obj",
    "Reactor.obj",
    "RingBig.obj",
    "Ring Small1.obj",
    "Ring Small2.obj",
    "Arms.obj",
    "Arms Small.obj",
    "Cooling Arms.obj",
    "Solar Panels.obj",
    "Parts.obj",
    "Triangle Parts.obj",
]

# ============================================================================
# TEXTURE DEFINITIONS
# ============================================================================

# (filename, uv_scale) — uv_scale controls tiling density
TEXTURES = {
    "hull1":       ("HullPlates1.jpg", 0.004),   # Main hull grey
    "hull2":       ("HullPlates2.jpg", 0.004),   # Warm hull
    "hull3":       ("HullPlates3.jpg", 0.004),   # Grey dark hull
    "solar_dark":  ("SolarGrid.jpg",   0.008),   # Solar panels dark hex
    "solar_light": ("SolarGrid2.jpg",  0.008),   # Solar panels light hex
    "green":       ("Green.jpg",       0.002),   # Biodome vegetation
    "dockbay":     ("Docking Bay.jpg", 0.003),   # Docking bay interior
}

# ============================================================================
# MATERIAL -> TEXTURE + PBR MAPPING
# ============================================================================

# Materials that need doubleSided (thin/single-sided geometry)
DOUBLE_SIDED_MATERIALS = {
    "solar", "solar_arm", "solar_edges", "solar_frame",
    "solar_tank_parts", "solar_tanks",
    "power_fin_coolers", "power_fins_lower", "power_fins_upper",
    "power_fin_spine",
}


def get_material_info(mat_name: str) -> dict:
    """Map material name to full PBR info with optional texture.
    Reference: Babbage Station renders (Pic1-6) from Ron L. Long.
    Color factor multiplies the texture sample in glTF PBR.

    From reference analysis:
    - Station is primarily grey/silver metallic with hull plate textures
    - Blue accent panels are dark navy/steel blue (NOT bright blue)
    - Solar panels are dark blue-grey hex grid
    - Orange/copper pipes on ring bands
    - Green biodomes on rings
    - Observation windows are dark blue-grey glass
    """
    ml = mat_name.lower()

    # === EMISSIVE LIGHTS (no texture, strong glow) ===
    if "red_light" in ml:
        return {"tex": None, "color": [1.0, 0.2, 0.08, 1.0],
                "met": 0.0, "rough": 0.8, "emissive": [2.0, 0.15, 0.05]}
    if "white_light" in ml:
        return {"tex": None, "color": [1.0, 1.0, 0.92, 1.0],
                "met": 0.0, "rough": 0.8, "emissive": [1.5, 1.5, 1.3]}

    # === GLASS / OBSERVATION WINDOWS (textured dark blue-grey, NOT flat) ===
    if "observation" in ml:
        return {"tex": "hull3", "color": [0.15, 0.20, 0.35, 1.0],
                "met": 0.3, "rough": 0.15, "emissive": [0.02, 0.04, 0.08]}
    if "window" in ml:
        return {"tex": "hull3", "color": [0.12, 0.18, 0.32, 1.0],
                "met": 0.3, "rough": 0.15, "emissive": [0.02, 0.04, 0.08]}

    # === BLUE ACCENT PANELS (hull texture + dark navy tint, per Pic1/Pic5) ===
    if ml.endswith("_blue"):
        return {"tex": "hull1", "color": [0.25, 0.30, 0.48, 1.0],
                "met": 0.65, "rough": 0.35}

    # === ORANGE / COPPER ACCENTS (pipes, ring bands — bright in reference) ===
    if "orange" in ml:
        return {"tex": "hull2", "color": [0.95, 0.45, 0.08, 1.0],
                "met": 0.75, "rough": 0.35}
    if ml == "reactor_pipes":
        return {"tex": "hull2", "color": [0.85, 0.40, 0.08, 1.0],
                "met": 0.75, "rough": 0.35}

    # === GREEN BIODOME (vegetation inside rings) ===
    if "green" in ml:
        return {"tex": "green", "color": [0.85, 1.0, 0.85, 1.0],
                "met": 0.0, "rough": 0.75}

    # === SOLAR PANELS (hex grid — dark grey-blue, not bright blue) ===
    if ml == "solar":
        return {"tex": "solar_dark", "color": [0.18, 0.22, 0.38, 1.0],
                "met": 0.2, "rough": 0.25}

    # === SOLAR STRUCTURAL (frame, arms, tanks, edges — grey metallic) ===
    if "solar" in ml:
        return {"tex": "hull1", "color": [0.60, 0.62, 0.65, 1.0],
                "met": 0.85, "rough": 0.4}

    # === COOLING FINS ===
    if "power_fin" in ml and "cooler" in ml:
        return {"tex": "solar_light", "color": [0.65, 0.67, 0.70, 1.0],
                "met": 0.5, "rough": 0.4}
    if "power_fin" in ml:
        return {"tex": "hull1", "color": [0.65, 0.67, 0.70, 1.0],
                "met": 0.8, "rough": 0.4}

    # === GUN PARTS (darker metallic) ===
    if "gun" in ml and "dark" in ml:
        return {"tex": "hull3", "color": [0.35, 0.37, 0.40, 1.0],
                "met": 0.9, "rough": 0.3}
    if "gun" in ml:
        return {"tex": "hull2", "color": [0.50, 0.52, 0.55, 1.0],
                "met": 0.9, "rough": 0.3}

    # === DARK / TRENCH (recessed detail, very dark) ===
    if "trench" in ml:
        return {"tex": "hull3", "color": [0.22, 0.23, 0.25, 1.0],
                "met": 0.85, "rough": 0.6}
    # Generic "dark" materials — must come before specific section checks
    if ml.endswith("_dark") or "_dark_" in ml:
        return {"tex": "hull3", "color": [0.30, 0.32, 0.35, 1.0],
                "met": 0.85, "rough": 0.55}

    # === LANDING BAY / DOCKING (use Docking Bay texture) ===
    if "landing_bay" in ml:
        return {"tex": "dockbay", "color": [0.55, 0.57, 0.60, 1.0],
                "met": 0.75, "rough": 0.45}
    if "docking" in ml:
        return {"tex": "dockbay", "color": [0.60, 0.62, 0.65, 1.0],
                "met": 0.8, "rough": 0.4}

    # === REACTOR (distinct warm metallic core) ===
    if "reactor" in ml and "core" in ml:
        return {"tex": "hull2", "color": [0.65, 0.60, 0.55, 1.0],
                "met": 0.9, "rough": 0.35}
    if "reactor" in ml and ("ring" in ml or "trim" in ml or "mount" in ml):
        return {"tex": "hull2", "color": [0.62, 0.64, 0.67, 1.0],
                "met": 0.85, "rough": 0.4}
    if "reactor" in ml and ("cooling" in ml or "fin" in ml):
        return {"tex": "hull1", "color": [0.55, 0.57, 0.60, 1.0],
                "met": 0.8, "rough": 0.45}
    if "reactor" in ml:
        return {"tex": "hull1", "color": [0.70, 0.72, 0.75, 1.0],
                "met": 0.85, "rough": 0.45}

    # === HANGAR INTERNALS ===
    if "coffin" in ml:
        return {"tex": "hull2", "color": [0.45, 0.47, 0.50, 1.0],
                "met": 0.8, "rough": 0.5}
    if "hanger_lower" in ml or "hanger_bottom" in ml:
        return {"tex": "hull2", "color": [0.50, 0.52, 0.55, 1.0],
                "met": 0.8, "rough": 0.45}
    if "hanger" in ml and ("rib" in ml or "brace" in ml or "flange" in ml):
        return {"tex": "hull1", "color": [0.60, 0.62, 0.65, 1.0],
                "met": 0.85, "rough": 0.45}
    if "hanger" in ml and "spear" in ml:
        return {"tex": "hull1", "color": [0.55, 0.57, 0.60, 1.0],
                "met": 0.85, "rough": 0.4}
    if "hanger" in ml:
        return {"tex": "hull1", "color": [0.70, 0.72, 0.75, 1.0],
                "met": 0.85, "rough": 0.45}

    # === TRIANGLE MODULES (big modular blocks — Pic5) ===
    if "triangle" in ml and ("dome" in ml or "round" in ml):
        return {"tex": "hull1", "color": [0.68, 0.70, 0.74, 1.0],
                "met": 0.65, "rough": 0.5}
    if "triangle" in ml and ("frame" in ml or "core" in ml):
        return {"tex": "hull1", "color": [0.58, 0.60, 0.63, 1.0],
                "met": 0.85, "rough": 0.4}
    if "triangle" in ml and "cutout" in ml:
        return {"tex": "hull3", "color": [0.28, 0.30, 0.33, 1.0],
                "met": 0.85, "rough": 0.5}
    if "triangle" in ml:
        return {"tex": "hull1", "color": [0.72, 0.74, 0.78, 1.0],
                "met": 0.85, "rough": 0.45}

    # === PENTEGON parts ===
    if "pentegon" in ml and ("frame" in ml or "core" in ml):
        return {"tex": "hull1", "color": [0.55, 0.57, 0.60, 1.0],
                "met": 0.85, "rough": 0.4}
    if "pentegon" in ml:
        return {"tex": "hull1", "color": [0.68, 0.70, 0.73, 1.0],
                "met": 0.85, "rough": 0.45}

    # === RINGS (main ring structure) ===
    if "ring" in ml and ("brace" in ml or "clamp" in ml):
        return {"tex": "hull1", "color": [0.58, 0.60, 0.63, 1.0],
                "met": 0.85, "rough": 0.4}
    if "ring" in ml and "rib" in ml:
        return {"tex": "hull1", "color": [0.50, 0.52, 0.55, 1.0],
                "met": 0.85, "rough": 0.4}
    if "ring" in ml:
        return {"tex": "hull1", "color": [0.72, 0.74, 0.78, 1.0],
                "met": 0.85, "rough": 0.45}

    # === ARMS / STRUTS ===
    if "arm" in ml and ("strut" in ml or "hex" in ml):
        return {"tex": "hull1", "color": [0.55, 0.57, 0.60, 1.0],
                "met": 0.85, "rough": 0.4}
    if "arm" in ml:
        return {"tex": "hull1", "color": [0.65, 0.67, 0.70, 1.0],
                "met": 0.85, "rough": 0.45}

    # === TANKS ===
    if "tank" in ml and "light" in ml:
        return {"tex": "hull1", "color": [0.78, 0.80, 0.83, 1.0],
                "met": 0.85, "rough": 0.45}
    if "tank" in ml:
        return {"tex": "hull1", "color": [0.65, 0.67, 0.70, 1.0],
                "met": 0.85, "rough": 0.45}

    # === VENTS (dark grating) ===
    if "vent" in ml:
        return {"tex": "hull3", "color": [0.22, 0.24, 0.27, 1.0],
                "met": 0.8, "rough": 0.6}

    # === COLLAR sections (grey hull plates) ===
    if "collar" in ml:
        return {"tex": "hull1", "color": [0.68, 0.70, 0.73, 1.0],
                "met": 0.85, "rough": 0.45}

    # === BOW TIE / SUPORT / LONG structures ===
    if "bow_tie" in ml or "suport" in ml or "long_bace" in ml:
        return {"tex": "hull1", "color": [0.60, 0.62, 0.65, 1.0],
                "met": 0.85, "rough": 0.45}

    # === DIVIDER / END structures ===
    if "divider" in ml or "end_" in ml:
        return {"tex": "hull1", "color": [0.65, 0.67, 0.70, 1.0],
                "met": 0.85, "rough": 0.45}

    # === DOOR HULL ===
    if "door" in ml:
        return {"tex": "hull1", "color": [0.60, 0.62, 0.65, 1.0],
                "met": 0.85, "rough": 0.4}

    # === DEFAULT HULL ===
    return {"tex": "hull1", "color": [0.75, 0.77, 0.80, 1.0],
            "met": 0.85, "rough": 0.45}


def is_double_sided(mat_name: str) -> bool:
    """Only thin/single-sided geometry should be double-sided."""
    ml = mat_name.lower()
    if ml in DOUBLE_SIDED_MATERIALS:
        return True
    # Cooling fins are thin panels
    if "power_fin" in ml and ("cooler" in ml or "fin" in ml):
        return True
    return False


# ============================================================================
# UV GENERATION (box projection / triplanar)
# ============================================================================

def generate_box_uvs(vertices: np.ndarray, normals: np.ndarray, uv_scale: float) -> np.ndarray:
    """Generate box-projected UVs from vertex positions and normals."""
    abs_n = np.abs(normals)
    dominant = np.argmax(abs_n, axis=1)
    uvs = np.zeros((len(vertices), 2), dtype=np.float32)

    # X-dominant faces -> project on YZ
    m = dominant == 0
    uvs[m, 0] = vertices[m, 1] * uv_scale
    uvs[m, 1] = vertices[m, 2] * uv_scale

    # Y-dominant faces -> project on XZ
    m = dominant == 1
    uvs[m, 0] = vertices[m, 0] * uv_scale
    uvs[m, 1] = vertices[m, 2] * uv_scale

    # Z-dominant faces -> project on XY
    m = dominant == 2
    uvs[m, 0] = vertices[m, 0] * uv_scale
    uvs[m, 1] = vertices[m, 1] * uv_scale

    return uvs


# ============================================================================
# OBJ LOADER (split by material)
# ============================================================================

def load_obj_split_by_material(filepath: Path) -> list:
    """Load OBJ and split into sub-meshes by usemtl groups.
    Returns list of (name, trimesh.Trimesh) tuples."""

    vertices = []
    normals = []
    groups = {}  # mat_name -> list of face vertex indices
    current_mat = "Default"

    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('v '):
                parts = line.split()
                vertices.append([float(parts[1]), float(parts[2]), float(parts[3])])
            elif line.startswith('vn '):
                parts = line.split()
                normals.append([float(parts[1]), float(parts[2]), float(parts[3])])
            elif line.startswith('usemtl '):
                current_mat = line[7:].strip()
                if current_mat not in groups:
                    groups[current_mat] = []
            elif line.startswith('f '):
                parts = line.split()[1:]
                face_verts = []
                for p in parts:
                    vi = int(p.split('/')[0]) - 1
                    face_verts.append(vi)
                if current_mat not in groups:
                    groups[current_mat] = []
                for i in range(1, len(face_verts) - 1):
                    groups[current_mat].append([face_verts[0], face_verts[i], face_verts[i+1]])

    if not vertices:
        return []

    verts_np = np.array(vertices, dtype=np.float32)
    results = []

    for mat_name, faces in groups.items():
        if not faces:
            continue
        faces_np = np.array(faces, dtype=np.int32)
        max_idx = faces_np.max()
        if max_idx >= len(verts_np):
            print(f"  WARNING: {mat_name} has face index {max_idx} but only {len(verts_np)} verts, skipping")
            continue
        try:
            unique_indices = np.unique(faces_np)
            remap = np.full(len(verts_np), -1, dtype=np.int32)
            remap[unique_indices] = np.arange(len(unique_indices), dtype=np.int32)
            compact_verts = verts_np[unique_indices]
            compact_faces = remap[faces_np]
            mesh = trimesh.Trimesh(vertices=compact_verts, faces=compact_faces, process=False)
            if len(mesh.faces) > 0:
                results.append((mat_name, mesh))
        except Exception as e:
            print(f"  WARNING: Failed to create mesh for {mat_name}: {e}")

    return results


# ============================================================================
# DUPLICATE GEOMETRY DETECTION
# ============================================================================

def mesh_signature(mesh: trimesh.Trimesh) -> tuple:
    """Create a signature for a mesh to detect duplicates.
    Uses bounding box center, size, and face count."""
    bounds = mesh.bounds
    center = tuple(np.round((bounds[0] + bounds[1]) / 2, 1))
    size = tuple(np.round(bounds[1] - bounds[0], 1))
    return (center, size, len(mesh.faces))


# ============================================================================
# GLB BUILDER
# ============================================================================

def build_glb(all_meshes: list, output_path: Path):
    """Build a GLB file with embedded textures from (part_name, mat_name, trimesh) tuples."""
    from pygltflib import (
        GLTF2, Scene, Node, Mesh, Primitive,
        Accessor, BufferView, Buffer,
        Material as GltfMaterial, PbrMetallicRoughness,
        Image as GltfImage, Texture as GltfTexture,
        Sampler as GltfSampler, TextureInfo,
    )
    from pygltflib import FLOAT, UNSIGNED_INT, SCALAR, VEC2, VEC3
    from pygltflib import ELEMENT_ARRAY_BUFFER, ARRAY_BUFFER

    gltf = GLTF2()
    gltf.scene = 0
    gltf.scenes = [Scene(nodes=[0], name="BabbageStation")]
    gltf.nodes = [Node(name="BabbageStation", children=[])]
    gltf.meshes = []
    gltf.accessors = []
    gltf.bufferViews = []
    gltf.materials = []
    gltf.buffers = []
    gltf.images = []
    gltf.textures = []
    gltf.samplers = []

    bin_data = bytearray()

    # ---- 1. Embed textures ----
    REPEAT = 10497
    LINEAR = 9729
    LINEAR_MIPMAP_LINEAR = 9987

    gltf.samplers.append(GltfSampler(
        magFilter=LINEAR,
        minFilter=LINEAR_MIPMAP_LINEAR,
        wrapS=REPEAT,
        wrapT=REPEAT,
    ))

    tex_key_to_idx = {}  # "hull1" -> glTF texture index

    for tex_key, (filename, _uv_scale) in TEXTURES.items():
        img_path = SRC_DIR / filename
        if not img_path.exists():
            print(f"  WARNING: Texture {filename} not found, skipping")
            continue

        img_bytes = img_path.read_bytes()
        img_offset = len(bin_data)
        bin_data.extend(img_bytes)
        # Pad to 4-byte alignment
        while len(bin_data) % 4 != 0:
            bin_data.append(0)

        # BufferView for image
        img_bv_idx = len(gltf.bufferViews)
        gltf.bufferViews.append(BufferView(
            buffer=0,
            byteOffset=img_offset,
            byteLength=len(img_bytes),
        ))

        # Image
        img_idx = len(gltf.images)
        gltf.images.append(GltfImage(
            bufferView=img_bv_idx,
            mimeType="image/jpeg",
        ))

        # Texture
        tex_idx = len(gltf.textures)
        gltf.textures.append(GltfTexture(
            sampler=0,
            source=img_idx,
        ))

        tex_key_to_idx[tex_key] = tex_idx
        size_kb = len(img_bytes) / 1024
        print(f"  Embedded texture: {filename} ({size_kb:.0f} KB) -> tex[{tex_idx}]")

    # ---- 2. Build materials and geometry ----
    mat_cache = {}  # mat_name -> material index

    # Group meshes by part name
    parts = {}
    for part_name, mat_name, mesh in all_meshes:
        if part_name not in parts:
            parts[part_name] = []
        parts[part_name].append((mat_name, mesh))

    node_idx = 1  # 0 is root

    for part_name, sub_meshes in parts.items():
        primitives = []

        for mat_name, mesh in sub_meshes:
            info = get_material_info(mat_name)
            tex_key = info.get("tex")
            has_texture = tex_key is not None and tex_key in tex_key_to_idx
            double_sided = is_double_sided(mat_name)

            # Get or create material
            mat_key = f"{mat_name}__ds{int(double_sided)}"
            if mat_key not in mat_cache:
                pbr = PbrMetallicRoughness(
                    baseColorFactor=info["color"],
                    metallicFactor=info["met"],
                    roughnessFactor=info["rough"],
                )
                if has_texture:
                    pbr.baseColorTexture = TextureInfo(index=tex_key_to_idx[tex_key])

                mat = GltfMaterial(
                    name=mat_name,
                    pbrMetallicRoughness=pbr,
                    doubleSided=double_sided,
                )
                if info.get("emissive"):
                    mat.emissiveFactor = info["emissive"]

                mat_cache[mat_key] = len(gltf.materials)
                gltf.materials.append(mat)

            mat_idx = mat_cache[mat_key]

            # --- Vertex positions ---
            verts = np.array(mesh.vertices, dtype=np.float32)
            verts_bytes = verts.tobytes()
            verts_offset = len(bin_data)
            bin_data.extend(verts_bytes)
            while len(bin_data) % 4 != 0:
                bin_data.append(0)

            pos_bv_idx = len(gltf.bufferViews)
            gltf.bufferViews.append(BufferView(
                buffer=0, byteOffset=verts_offset,
                byteLength=len(verts_bytes), target=ARRAY_BUFFER,
            ))

            pos_min = verts.min(axis=0).tolist()
            pos_max = verts.max(axis=0).tolist()
            pos_acc_idx = len(gltf.accessors)
            gltf.accessors.append(Accessor(
                bufferView=pos_bv_idx, componentType=FLOAT,
                count=len(verts), type=VEC3, max=pos_max, min=pos_min,
            ))

            # --- Normals ---
            norms = np.array(mesh.vertex_normals, dtype=np.float32)
            norms_bytes = norms.tobytes()
            norms_offset = len(bin_data)
            bin_data.extend(norms_bytes)
            while len(bin_data) % 4 != 0:
                bin_data.append(0)

            norm_bv_idx = len(gltf.bufferViews)
            gltf.bufferViews.append(BufferView(
                buffer=0, byteOffset=norms_offset,
                byteLength=len(norms_bytes), target=ARRAY_BUFFER,
            ))

            norm_acc_idx = len(gltf.accessors)
            gltf.accessors.append(Accessor(
                bufferView=norm_bv_idx, componentType=FLOAT,
                count=len(norms), type=VEC3,
            ))

            # --- UVs (box projection) ---
            uv_scale = TEXTURES[tex_key][1] if has_texture else 0.004
            uvs = generate_box_uvs(verts, norms, uv_scale)
            uv_bytes = uvs.tobytes()
            uv_offset = len(bin_data)
            bin_data.extend(uv_bytes)
            while len(bin_data) % 4 != 0:
                bin_data.append(0)

            uv_bv_idx = len(gltf.bufferViews)
            gltf.bufferViews.append(BufferView(
                buffer=0, byteOffset=uv_offset,
                byteLength=len(uv_bytes), target=ARRAY_BUFFER,
            ))

            uv_acc_idx = len(gltf.accessors)
            gltf.accessors.append(Accessor(
                bufferView=uv_bv_idx, componentType=FLOAT,
                count=len(uvs), type=VEC2,
            ))

            # --- Indices ---
            faces = np.array(mesh.faces, dtype=np.uint32).flatten()
            idx_bytes = faces.tobytes()
            idx_offset = len(bin_data)
            bin_data.extend(idx_bytes)
            while len(bin_data) % 4 != 0:
                bin_data.append(0)

            idx_bv_idx = len(gltf.bufferViews)
            gltf.bufferViews.append(BufferView(
                buffer=0, byteOffset=idx_offset,
                byteLength=len(idx_bytes), target=ELEMENT_ARRAY_BUFFER,
            ))

            idx_acc_idx = len(gltf.accessors)
            gltf.accessors.append(Accessor(
                bufferView=idx_bv_idx, componentType=UNSIGNED_INT,
                count=len(faces), type=SCALAR,
            ))

            primitives.append(Primitive(
                attributes={
                    "POSITION": pos_acc_idx,
                    "NORMAL": norm_acc_idx,
                    "TEXCOORD_0": uv_acc_idx,
                },
                indices=idx_acc_idx,
                material=mat_idx,
            ))

        # Create mesh and node for this part
        mesh_idx = len(gltf.meshes)
        gltf.meshes.append(Mesh(name=part_name, primitives=primitives))
        gltf.nodes.append(Node(name=part_name, mesh=mesh_idx))
        gltf.nodes[0].children.append(node_idx)
        node_idx += 1

    # ---- 3. Finalize ----
    gltf.buffers = [Buffer(byteLength=len(bin_data))]
    gltf.set_binary_blob(bytes(bin_data))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    gltf.save(str(output_path))

    # Count stats
    ds_count = sum(1 for m in gltf.materials if m.doubleSided)
    ss_count = len(gltf.materials) - ds_count
    print(f"\nSaved GLB to: {output_path}")
    print(f"  Binary data: {len(bin_data) / 1024 / 1024:.1f} MB")
    print(f"  Nodes: {len(gltf.nodes)}")
    print(f"  Meshes: {len(gltf.meshes)}")
    print(f"  Materials: {len(gltf.materials)} ({ss_count} single-sided, {ds_count} double-sided)")
    print(f"  Textures: {len(gltf.textures)}")
    print(f"  Images: {len(gltf.images)}")


# ============================================================================
# MAIN
# ============================================================================

def main():
    print("=== Babbage Station OBJ -> GLB Converter v3 (z-fight fix + color fix) ===\n")

    all_meshes = []
    total_verts = 0
    total_faces = 0

    # Track geometry signatures to detect duplicates across OBJ files
    seen_signatures = {}  # (mat_name, signature) -> part_name

    duplicates_skipped = 0

    for obj_name in OBJ_PARTS:
        obj_path = SRC_DIR / obj_name
        if not obj_path.exists():
            print(f"SKIP: {obj_name} not found")
            continue

        part_name = obj_name.replace(".obj", "").replace(" ", "_")
        print(f"Loading {obj_name}...")
        sub_meshes = load_obj_split_by_material(obj_path)

        part_verts = 0
        part_faces = 0
        for mat_name, mesh in sub_meshes:
            # Check for duplicate geometry (same material, same bounding box)
            sig = mesh_signature(mesh)
            dup_key = (mat_name, sig)
            if dup_key in seen_signatures:
                orig_part = seen_signatures[dup_key]
                print(f"  SKIP duplicate: {mat_name} ({len(mesh.faces)} faces, same as {orig_part})")
                duplicates_skipped += 1
                continue

            seen_signatures[dup_key] = part_name
            all_meshes.append((part_name, mat_name, mesh))
            part_verts += len(mesh.vertices)
            part_faces += len(mesh.faces)

        print(f"  -> {len(sub_meshes)} material groups, {part_verts} verts, {part_faces} faces")
        total_verts += part_verts
        total_faces += part_faces

    print(f"\nTotal: {len(all_meshes)} sub-meshes, {total_verts} verts, {total_faces} faces")
    if duplicates_skipped > 0:
        print(f"  Duplicates skipped: {duplicates_skipped}")

    print(f"\nEmbedding textures...")
    for tex_key, (filename, _) in TEXTURES.items():
        path = SRC_DIR / filename
        if path.exists():
            print(f"  Found: {filename}")
        else:
            print(f"  MISSING: {filename}")

    print(f"\nBuilding GLB...")
    build_glb(all_meshes, output_path=OUT_PATH)
    print("Done!")


if __name__ == "__main__":
    main()
