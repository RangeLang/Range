#!/usr/bin/env python3
"""Synthetic proof for The Flash ambient-subtracted material capture.

The experiment renders a metallic sphere under a real HDR environment and uses
an equirectangular 360 camera to capture a complete HDRI at every state in an
OFF/W/R/G/B/C/Y/M/W/OFF burst. It performs ambient interpolation/subtraction in
linear radiance and fits roughness/metallic parameters against the isolated
white-flash response.

This is deliberately a small inverse-rendering proof, not a production renderer.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
ASSET = ROOT / "assets" / "studio_small_01_1k.hdr"
OUTPUT = ROOT / "output_hdri"
HDR_OUTPUT = OUTPUT / "captures"

PANORAMA_WIDTH = 640
PANORAMA_HEIGHT = 320

GROUND_TRUTH = {
    "base_color": np.array([0.91, 0.48, 0.19], dtype=np.float32),
    "roughness": 0.22,
    "metallic": 0.92,
}

FLASH_SEQUENCE = [
    ("white_0", np.array([1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0], dtype=np.float32)),
    ("red", np.array([1.0, 0.0, 0.0], dtype=np.float32)),
    ("green", np.array([0.0, 1.0, 0.0], dtype=np.float32)),
    ("blue", np.array([0.0, 0.0, 1.0], dtype=np.float32)),
    ("cyan", np.array([0.0, 0.5, 0.5], dtype=np.float32)),
    ("yellow", np.array([0.5, 0.5, 0.0], dtype=np.float32)),
    ("magenta", np.array([0.5, 0.0, 0.5], dtype=np.float32)),
    ("white_1", np.array([1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0], dtype=np.float32)),
]


def read_radiance_hdr(path: Path) -> np.ndarray:
    """Read the modern scanline-RLE subset used by Poly Haven .hdr files."""
    with path.open("rb") as stream:
        signature = stream.readline().decode("ascii", "replace").strip()
        if not signature.startswith("#?"):
            raise ValueError("Not a Radiance HDR file")

        while True:
            line = stream.readline()
            if not line:
                raise ValueError("HDR header ended before resolution")
            if line in (b"\n", b"\r\n"):
                break

        resolution = stream.readline().decode("ascii").strip().split()
        if len(resolution) != 4 or resolution[0] != "-Y" or resolution[2] != "+X":
            raise ValueError(f"Unsupported HDR orientation: {' '.join(resolution)}")
        height, width = int(resolution[1]), int(resolution[3])
        rgbe = np.empty((height, width, 4), dtype=np.uint8)

        for y in range(height):
            marker = stream.read(4)
            if len(marker) != 4 or marker[0] != 2 or marker[1] != 2:
                raise ValueError("Only modern Radiance scanline RLE is supported")
            scanline_width = (marker[2] << 8) | marker[3]
            if scanline_width != width:
                raise ValueError("HDR scanline width mismatch")
            channels = np.empty((4, width), dtype=np.uint8)
            for channel in range(4):
                x = 0
                while x < width:
                    count_byte = stream.read(1)
                    if not count_byte:
                        raise ValueError("Unexpected EOF in HDR scanline")
                    count = count_byte[0]
                    if count > 128:
                        run = count - 128
                        value = stream.read(1)
                        if not value:
                            raise ValueError("Unexpected EOF in HDR RLE run")
                        channels[channel, x : x + run] = value[0]
                        x += run
                    else:
                        values = stream.read(count)
                        if len(values) != count:
                            raise ValueError("Unexpected EOF in HDR literal run")
                        channels[channel, x : x + count] = np.frombuffer(values, dtype=np.uint8)
                        x += count
            rgbe[y] = channels.T

    exponent = rgbe[..., 3].astype(np.int32)
    scale = np.zeros_like(exponent, dtype=np.float32)
    nonzero = exponent > 0
    scale[nonzero] = np.ldexp(1.0, exponent[nonzero] - 136)
    return rgbe[..., :3].astype(np.float32) * scale[..., None]


def write_radiance_hdr(path: Path, linear: np.ndarray) -> None:
    """Write non-negative linear RGB as a Radiance RGBE scanline-RLE file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    rgb = np.maximum(np.asarray(linear, dtype=np.float32), 0.0)
    height, width = rgb.shape[:2]
    if width < 8 or width > 32767:
        raise ValueError("Radiance scanline RLE requires a width from 8 to 32767")

    maximum = np.max(rgb, axis=-1)
    exponent = np.zeros_like(maximum, dtype=np.int32)
    nonzero = maximum > 1e-32
    exponent[nonzero] = np.floor(np.log2(maximum[nonzero])).astype(np.int32) + 1
    scale = np.zeros_like(maximum, dtype=np.float32)
    scale[nonzero] = np.ldexp(256.0, -exponent[nonzero])
    rgbe = np.zeros((height, width, 4), dtype=np.uint8)
    rgbe[..., :3] = np.clip(rgb * scale[..., None], 0.0, 255.0).astype(np.uint8)
    rgbe[..., 3][nonzero] = np.clip(exponent[nonzero] + 128, 1, 255).astype(np.uint8)

    with path.open("wb") as stream:
        stream.write(b"#?RADIANCE\n")
        stream.write(b"FORMAT=32-bit_rle_rgbe\n\n")
        stream.write(f"-Y {height} +X {width}\n".encode("ascii"))
        for scanline in rgbe:
            stream.write(bytes((2, 2, width >> 8, width & 255)))
            channels = scanline.T
            for channel in channels:
                # Literal packets are valid Radiance RLE. Compression is unnecessary
                # for this small proof and keeping the encoder plain aids inspection.
                start = 0
                while start < width:
                    count = min(128, width - start)
                    stream.write(bytes((count,)))
                    stream.write(channel[start : start + count].tobytes())
                    start += count


def normalize(vector: np.ndarray, axis: int = -1) -> np.ndarray:
    length = np.linalg.norm(vector, axis=axis, keepdims=True)
    return vector / np.maximum(length, 1e-8)


def sample_environment(environment: np.ndarray, directions: np.ndarray) -> np.ndarray:
    directions = normalize(directions)
    theta = np.arctan2(directions[..., 1], directions[..., 0])
    u = (theta / (2.0 * np.pi) + 0.5) % 1.0
    v = np.arccos(np.clip(directions[..., 2], -1.0, 1.0)) / np.pi
    height, width = environment.shape[:2]
    x = u * (width - 1)
    y = v * (height - 1)
    x0 = np.floor(x).astype(np.int32)
    y0 = np.floor(y).astype(np.int32)
    x1 = (x0 + 1) % width
    y1 = np.minimum(y0 + 1, height - 1)
    tx = (x - x0)[..., None]
    ty = (y - y0)[..., None]
    top = environment[y0, x0] * (1.0 - tx) + environment[y0, x1] * tx
    bottom = environment[y1, x0] * (1.0 - tx) + environment[y1, x1] * tx
    return top * (1.0 - ty) + bottom * ty


def rough_environment_sample(
    environment: np.ndarray, directions: np.ndarray, roughness: float
) -> np.ndarray:
    """Small deterministic lobe approximation for an environment-prefiltered BRDF."""
    direction = normalize(directions)
    helper = np.zeros_like(direction)
    helper[..., 2] = 1.0
    near_pole = np.abs(direction[..., 2]) > 0.92
    helper[near_pole] = np.array([0.0, 1.0, 0.0], dtype=np.float32)
    tangent = normalize(np.cross(helper, direction))
    bitangent = normalize(np.cross(direction, tangent))
    result = sample_environment(environment, direction) * 0.30
    spread = 0.075 + roughness * roughness * 0.65
    rings = [(0.55, 0.11), (1.0, 0.065)]
    for radius, weight in rings:
        for angle in np.linspace(0.0, 2.0 * np.pi, 8, endpoint=False):
            offset = math.cos(angle) * tangent + math.sin(angle) * bitangent
            sample_direction = normalize(direction + offset * spread * radius)
            result += sample_environment(environment, sample_direction) * weight
    return result


def panorama_rays() -> np.ndarray:
    """World-space rays for a complete equirectangular 360 camera capture."""
    u = (np.arange(PANORAMA_WIDTH, dtype=np.float32) + 0.5) / PANORAMA_WIDTH
    v = (np.arange(PANORAMA_HEIGHT, dtype=np.float32) + 0.5) / PANORAMA_HEIGHT
    theta = (u - 0.5) * 2.0 * np.pi
    phi = v * np.pi
    theta_grid, phi_grid = np.meshgrid(theta, phi)
    sin_phi = np.sin(phi_grid)
    return np.stack(
        [
            sin_phi * np.cos(theta_grid),
            sin_phi * np.sin(theta_grid),
            np.cos(phi_grid),
        ],
        axis=-1,
    ).astype(np.float32)


def panorama_sphere_geometry(
    camera: np.ndarray, center: np.ndarray, radius: float
) -> dict[str, np.ndarray]:
    rays = panorama_rays()
    camera_to_center = camera - center
    b = np.sum(camera_to_center[None, None, :] * rays, axis=-1)
    c = np.dot(camera_to_center, camera_to_center) - radius * radius
    discriminant = b * b - c
    mask = discriminant >= 0.0
    distance = -b - np.sqrt(np.maximum(discriminant, 0.0))
    mask &= distance > 0.0
    points = camera[None, None, :] + rays * distance[..., None]
    normals = normalize(points - center[None, None, :])
    view = normalize(camera[None, None, :] - points)
    reflection = normalize(2.0 * np.sum(normals * view, axis=-1, keepdims=True) * normals - view)
    return {
        "rays": rays,
        "mask": mask,
        "points": points,
        "normals": normals,
        "view": view,
        "reflection": reflection,
    }


def material_f0(base_color: np.ndarray, metallic: float) -> np.ndarray:
    return 0.04 * (1.0 - metallic) + base_color * metallic


def render_ambient(
    environment: np.ndarray,
    geometry: dict[str, np.ndarray],
    base_color: np.ndarray,
    roughness: float,
    metallic: float,
    tint: np.ndarray,
) -> np.ndarray:
    background = sample_environment(environment, geometry["rays"]) * 0.16
    env_specular = rough_environment_sample(environment, geometry["reflection"], roughness)
    n_dot_v = np.clip(np.sum(geometry["normals"] * geometry["view"], axis=-1), 0.0, 1.0)
    f0 = material_f0(base_color, metallic)
    fresnel = f0 + (1.0 - f0) * (1.0 - n_dot_v[..., None]) ** 5
    diffuse_light = np.mean(environment.reshape(-1, 3), axis=0) * 0.38
    diffuse = (1.0 - metallic) * base_color * diffuse_light
    sphere = env_specular * fresnel + diffuse
    image = background.copy()
    image[geometry["mask"]] = sphere[geometry["mask"]]
    return image * tint


def render_flash(
    camera: np.ndarray,
    geometry: dict[str, np.ndarray],
    color: np.ndarray,
    base_color: np.ndarray,
    roughness: float,
    metallic: float,
) -> np.ndarray:
    normals = geometry["normals"]
    view = geometry["view"]
    points = geometry["points"]
    # Coaxial camera-ring approximation: the active light travels from camera to surface.
    light = normalize(camera[None, None, :] - points)
    half_vector = normalize(light + view)
    n_dot_l = np.clip(np.sum(normals * light, axis=-1), 0.0, 1.0)
    n_dot_v = np.clip(np.sum(normals * view, axis=-1), 0.0, 1.0)
    n_dot_h = np.clip(np.sum(normals * half_vector, axis=-1), 0.0, 1.0)
    v_dot_h = np.clip(np.sum(view * half_vector, axis=-1), 0.0, 1.0)

    alpha = max(roughness * roughness, 0.002)
    alpha_squared = alpha * alpha
    denominator = n_dot_h * n_dot_h * (alpha_squared - 1.0) + 1.0
    distribution = alpha_squared / np.maximum(np.pi * denominator * denominator, 1e-7)

    k = ((roughness + 1.0) ** 2) / 8.0
    g_l = n_dot_l / np.maximum(n_dot_l * (1.0 - k) + k, 1e-7)
    g_v = n_dot_v / np.maximum(n_dot_v * (1.0 - k) + k, 1e-7)
    geometry_term = g_l * g_v

    f0 = material_f0(base_color, metallic)
    fresnel = f0 + (1.0 - f0) * (1.0 - v_dot_h[..., None]) ** 5
    specular = (
        distribution[..., None]
        * geometry_term[..., None]
        * fresnel
        / np.maximum(4.0 * n_dot_l[..., None] * n_dot_v[..., None], 1e-6)
    )
    diffuse = (1.0 - metallic) * (1.0 - fresnel) * base_color / np.pi
    distance_squared = np.sum((camera[None, None, :] - points) ** 2, axis=-1)
    radiance = color * 3.6 / np.maximum(distance_squared[..., None], 0.1)
    response = (diffuse + specular) * radiance * n_dot_l[..., None]
    response[~geometry["mask"]] = 0.0
    return response


def tonemap(linear: np.ndarray, exposure: float = 1.0) -> np.ndarray:
    value = np.maximum(linear * exposure, 0.0)
    # ACES fitted curve, then display gamma.
    mapped = np.clip((value * (2.51 * value + 0.03)) / (value * (2.43 * value + 0.59) + 0.14), 0.0, 1.0)
    srgb = np.where(mapped <= 0.0031308, mapped * 12.92, 1.055 * mapped ** (1.0 / 2.4) - 0.055)
    return np.round(np.clip(srgb, 0.0, 1.0) * 255.0).astype(np.uint8)


def save_png(path: Path, linear: np.ndarray, exposure: float = 1.0) -> None:
    Image.fromarray(tonemap(linear, exposure), mode="RGB").save(path)


def label_image(image: Image.Image, label: str) -> Image.Image:
    result = image.copy()
    draw = ImageDraw.Draw(result)
    font = ImageFont.load_default()
    box = draw.textbbox((0, 0), label, font=font)
    width = box[2] - box[0]
    draw.rounded_rectangle((8, 8, 18 + width, 28), radius=5, fill=(7, 10, 18, 220))
    draw.text((13, 12), label, fill=(245, 247, 255), font=font)
    return result


def contact_sheet(paths: list[tuple[str, Path]], columns: int, destination: Path) -> None:
    images = [(label, Image.open(path).convert("RGB")) for label, path in paths]
    cell_width = max(image.width for _, image in images)
    cell_height = max(image.height for _, image in images)
    rows = math.ceil(len(images) / columns)
    sheet = Image.new("RGB", (columns * cell_width, rows * cell_height), (9, 11, 18))
    for index, (label, image) in enumerate(images):
        x = (index % columns) * cell_width
        y = (index // columns) * cell_height
        sheet.paste(label_image(image, label), (x, y))
    sheet.save(destination)


def fit_material(
    cameras: list[np.ndarray],
    geometries: list[dict[str, np.ndarray]],
    isolated_white: list[np.ndarray],
) -> tuple[float, float, list[dict[str, float]]]:
    observations = []
    sample_masks = []
    for geometry, observed in zip(geometries, isolated_white):
        mask = geometry["mask"]
        # Use a deterministic sparse set and avoid the unstable silhouette.
        n_dot_v = np.sum(geometry["normals"] * geometry["view"], axis=-1)
        sample = mask & (n_dot_v > 0.18)
        sample[::2, ::2] = False
        sample[1::4, 1::4] &= True
        observations.append(observed[sample])
        sample_masks.append(sample)

    scores: list[dict[str, float]] = []
    for roughness in np.linspace(0.10, 0.42, 17):
        for metallic in np.linspace(0.5, 1.0, 21):
            squared_error = 0.0
            sample_count = 0
            for camera, geometry, observed, mask in zip(cameras, geometries, observations, sample_masks):
                predicted = render_flash(
                    camera,
                    geometry,
                    FLASH_SEQUENCE[0][1],
                    GROUND_TRUTH["base_color"],
                    float(roughness),
                    float(metallic),
                )[mask]
                difference = predicted - observed
                squared_error += float(np.sum(difference * difference))
                sample_count += difference.size
            scores.append(
                {
                    "roughness": float(roughness),
                    "metallic": float(metallic),
                    "mse": squared_error / max(sample_count, 1),
                }
            )
    scores.sort(key=lambda item: item["mse"])
    best = scores[0]
    return best["roughness"], best["metallic"], scores[:10]


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    environment = read_radiance_hdr(ASSET)
    camera = np.zeros(3, dtype=np.float32)
    surface_center = np.array([1.8, 0.0, 0.0], dtype=np.float32)
    surface_radius = 0.8
    geometry = panorama_sphere_geometry(camera, surface_center, surface_radius)

    burst_directory = HDR_OUTPUT / "burst_00"
    before_tint = np.array([1.0, 1.0, 1.0], dtype=np.float32)
    after_tint = np.array([1.045, 1.018, 0.985], dtype=np.float32)
    rendered_before = render_ambient(
        environment,
        geometry,
        GROUND_TRUTH["base_color"],
        GROUND_TRUTH["roughness"],
        GROUND_TRUTH["metallic"],
        before_tint,
    )
    rendered_after = render_ambient(
        environment,
        geometry,
        GROUND_TRUTH["base_color"],
        GROUND_TRUTH["roughness"],
        GROUND_TRUTH["metallic"],
        after_tint,
    )
    before_hdr_path = burst_directory / "ambient_before.hdr"
    after_hdr_path = burst_directory / "ambient_after.hdr"
    write_radiance_hdr(before_hdr_path, rendered_before)
    write_radiance_hdr(after_hdr_path, rendered_after)
    before = read_radiance_hdr(before_hdr_path)
    after = read_radiance_hdr(after_hdr_path)

    before_preview = OUTPUT / "ambient_before_hdri.png"
    after_preview = OUTPUT / "ambient_after_hdri.png"
    save_png(before_preview, before, exposure=0.75)
    save_png(after_preview, after, exposure=0.75)

    burst_paths: list[tuple[str, Path]] = [("ambient before", before_preview)]
    sequence_paths: list[tuple[str, Path]] = []
    isolated_paths: list[tuple[str, Path]] = []
    isolated_responses: dict[str, np.ndarray] = {}

    mask_y, mask_x = np.where(geometry["mask"])
    crop_box = (
        max(int(mask_x.min()) - 18, 0),
        max(int(mask_y.min()) - 18, 0),
        min(int(mask_x.max()) + 19, PANORAMA_WIDTH),
        min(int(mask_y.max()) + 19, PANORAMA_HEIGHT),
    )
    selected_paths: list[tuple[str, Path]] = []

    for flash_index, (name, color) in enumerate(FLASH_SEQUENCE):
        t = (flash_index + 1) / (len(FLASH_SEQUENCE) + 1)
        ambient_at_capture = rendered_before * (1.0 - t) + rendered_after * t
        flash_only = render_flash(
            camera,
            geometry,
            color,
            GROUND_TRUTH["base_color"],
            GROUND_TRUTH["roughness"],
            GROUND_TRUTH["metallic"],
        )
        rendered_observed = ambient_at_capture + flash_only
        observed_hdr_path = burst_directory / f"flash_{name}.hdr"
        isolated_hdr_path = burst_directory / f"isolated_{name}.hdr"
        write_radiance_hdr(observed_hdr_path, rendered_observed)

        # Analysis begins by loading the complete HDRIs from disk.
        observed = read_radiance_hdr(observed_hdr_path)
        estimated_ambient_hdri = before * (1.0 - t) + after * t
        isolated = np.maximum(observed - estimated_ambient_hdri, 0.0)
        isolated[~geometry["mask"]] = 0.0
        write_radiance_hdr(isolated_hdr_path, isolated)
        isolated_reloaded = read_radiance_hdr(isolated_hdr_path)
        isolated_responses[name] = isolated_reloaded

        observed_preview = OUTPUT / f"flash_{name}_hdri.png"
        isolated_preview = OUTPUT / f"isolated_{name}_hdri.png"
        selected_preview = OUTPUT / f"selected_{name}.png"
        save_png(observed_preview, observed, exposure=0.75)
        save_png(isolated_preview, isolated_reloaded, exposure=1.4)
        Image.fromarray(tonemap(isolated_reloaded, exposure=1.4)).crop(crop_box).save(selected_preview)
        sequence_paths.append((name.replace("_", " "), observed_preview))
        isolated_paths.append((name.replace("_", " "), isolated_preview))
        selected_paths.append((name.replace("_", " "), selected_preview))
        burst_paths.append((name.replace("_", " "), observed_preview))

    burst_paths.append(("ambient after", after_preview))
    contact_sheet(
        [("ambient before", before_preview), ("ambient after", after_preview)],
        columns=2,
        destination=OUTPUT / "ambient_hdri_pair.png",
    )
    contact_sheet(burst_paths, columns=2, destination=OUTPUT / "hdri_burst_contact_sheet.png")
    contact_sheet(sequence_paths, columns=2, destination=OUTPUT / "flash_hdri_sequence.png")
    contact_sheet(isolated_paths, columns=2, destination=OUTPUT / "isolated_hdri_sequence.png")
    contact_sheet(selected_paths, columns=4, destination=OUTPUT / "selected_material_responses.png")
    Image.fromarray(np.where(geometry["mask"], 255, 0).astype(np.uint8), mode="L").save(
        OUTPUT / "selected_surface_mask.png"
    )

    fitted_roughness, fitted_metallic, top_fits = fit_material(
        [camera], [geometry], [isolated_responses["white_0"]]
    )
    expected_white = render_flash(
        camera,
        geometry,
        FLASH_SEQUENCE[0][1],
        GROUND_TRUTH["base_color"],
        GROUND_TRUTH["roughness"],
        GROUND_TRUTH["metallic"],
    )
    white_repeat_error = float(
        np.mean(np.abs(isolated_responses["white_0"] - isolated_responses["white_1"]))
    )
    subtraction_error = float(np.mean(np.abs(isolated_responses["white_0"] - expected_white)))

    summary = {
        "experiment": "The Flash synthetic HDRI capture",
        "environment": "Poly Haven studio_small_01_1k.hdr (CC0)",
        "capture_type": "full equirectangular HDRI",
        "processing_space": "linear Radiance RGBE HDR",
        "panorama_dimensions": [PANORAMA_WIDTH, PANORAMA_HEIGHT],
        "angular_field_degrees": [360, 180],
        "capture_contract": "ambient_before HDRI + eight flash HDRIs + ambient_after HDRI",
        "flash_mapping": {
            "normalization": "equal integrated incident energy in the synthetic RGB basis",
            "vectors": {name: color.tolist() for name, color in FLASH_SEQUENCE},
            "hardware_requirement": "replace RGB basis vectors with measured LED spectral power distributions",
        },
        "source_hdri_count": len(FLASH_SEQUENCE) + 2,
        "derived_isolated_hdri_count": len(FLASH_SEQUENCE),
        "registered_pose_count": 1,
        "burst": ["ambient_before"] + [name for name, _ in FLASH_SEQUENCE] + ["ambient_after"],
        "ambient_drift_tint": {
            "before": before_tint.tolist(),
            "after": after_tint.tolist(),
        },
        "ground_truth": {
            "base_color": GROUND_TRUTH["base_color"].tolist(),
            "roughness": GROUND_TRUTH["roughness"],
            "metallic": GROUND_TRUTH["metallic"],
        },
        "fit_assuming_separately_measured_base_color": {
            "roughness": fitted_roughness,
            "metallic": fitted_metallic,
            "top_candidates": top_fits,
        },
        "selected_surface": {
            "panorama_pixel_fraction": float(np.mean(geometry["mask"])),
            "mask": "selected_surface_mask.png",
        },
        "local_light_hdri": {
            "mean_before_after_absolute_delta": float(np.mean(np.abs(after - before))),
            "interpolation": "linear per flash timestamp",
        },
        "mean_white_repeat_absolute_error": white_repeat_error,
        "mean_linear_ambient_subtraction_absolute_error": subtraction_error,
        "limitations": [
            "Synthetic renderer and inverse fit share the same simplified GGX model.",
            "Base color is treated as separately measured, as polarization would provide.",
            "No sensor noise, clipping, rolling shutter, motion, or polarization is simulated.",
            "A 360 camera captures a full environment around one pose but cannot see the back of an opaque object.",
            "Object-complete capture still requires multiple registered HDRI bursts from different poses.",
            "C/Y/M are RGB mixtures and therefore add redundancy, not new spectral bands.",
        ],
    }
    (OUTPUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
