from pathlib import Path
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art" / "stage"
FOCAL, CAMERA_HEIGHT = 1430.0, 3.35
VP_X, VP_Y = 773.0, 456.0
LEFT, RIGHT = 1.28 * CAMERA_HEIGHT, 1.22 * CAMERA_HEIGHT
HEIGHT = 11.6
WIDTH, ROWS = 2048, 1024
# At both ends of this span the two eaves are close to the same height.
START, PERIOD, OVERLAP = 12.0, 14.0, 2.8
WALL_COLS = round(WIDTH * HEIGHT / (2 * HEIGHT + LEFT + RIGHT))

def silhouettes(plate):
    """Trace the original eaves, including the parts above the lanterns."""
    alpha = np.zeros(plate.shape[:2], np.uint8)
    left = [(0, 0), (511, 0), (516, 25), (532, 44), (538, 66), (562, 101),
            (557, 118), (505, 138), (494, 211), (543, 244), (598, 270),
            (636, 303), (711, 294), (731, 333), (749, 369), (773, 417),
            (773, 1024), (0, 1024)]
    right = [(1536, 0), (1147, 0), (1112, 43), (1062, 102), (1003, 174),
             (948, 246), (956, 264), (922, 256), (899, 277), (869, 291),
             (837, 316), (807, 355), (773, 417), (773, 1024), (1536, 1024)]
    cv2.fillPoly(alpha, [np.array(left), np.array(right)], 255, lineType=cv2.LINE_AA)
    return alpha.astype(np.float32)

def sky_reveal(plate):
    """Extend only clear sky from the source to fill the view behind passing roofs."""
    y, x = np.indices(plate.shape[:2], dtype=np.float32)
    sky_y = np.minimum(y, 337)
    half = np.interp(sky_y[:, 0], [0, 210, 290, 337], [211, 144, 64, 20])[:, None]
    fold = np.mod(x - VP_X + half, 4 * half)
    sky_x = (VP_X - half + np.minimum(fold, 4 * half - fold)).astype(np.float32)
    return cv2.remap(plate, sky_x, sky_y, cv2.INTER_LINEAR)

def project(plate, alpha, depths):
    cross = (np.arange(WIDTH) + 0.5) * (HEIGHT * 2 + LEFT + RIGHT) / WIDTH
    x = np.clip(cross - HEIGHT - LEFT, -LEFT, RIGHT)
    y = np.maximum(0, np.maximum(HEIGHT - cross, cross - (HEIGHT + LEFT + RIGHT)))
    inv_depth = FOCAL / depths[:, None]
    u = (VP_X + x * inv_depth).astype(np.float32)
    v = (VP_Y + (CAMERA_HEIGHT - y) * inv_depth).astype(np.float32)
    rgb = cv2.remap(plate, u, v, cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT_101)
    coverage = cv2.remap(alpha, u, v, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    roof = VP_Y - np.abs(u - VP_X) * np.where(u < VP_X, 1.65, 1.15)
    coverage = np.where(v < 0, coverage * np.clip((v - roof + 3) / 6, 0, 1), coverage)
    rgb *= (1 - 0.32 * np.clip(-v / 140, 0, 1))[..., None]
    coverage[:, :WALL_COLS] = np.minimum.accumulate(coverage[:, :WALL_COLS][:, ::-1], axis=1)[:, ::-1]
    coverage[:, -WALL_COLS:] = np.minimum.accumulate(coverage[:, -WALL_COLS:], axis=1)
    return np.dstack((rgb, coverage)).astype(np.float32)

def join(near, far):
    # Keep each wall's seam vertical from the pavement to the eaves.
    rows, width = near.shape[:2]
    delta = np.abs(near - far)
    opaque = np.minimum(near[..., 3], far[..., 3]) / 255
    cost = cv2.GaussianBlur(delta[..., :3].mean(axis=2) * opaque + delta[..., 3] * 0.65, (0, 0), 2.0)
    cost += 8 * np.abs(np.linspace(-1, 1, rows))[:, None]
    cost[:22] += 500
    cost[-22:] += 500
    wall_cols = round(width * HEIGHT / (2 * HEIGHT + LEFT + RIGHT))
    left_seam = cost[:, :wall_cols].mean(axis=1).argmin()
    right_seam = cost[:, -wall_cols:].mean(axis=1).argmin()
    seam = np.r_[np.full(wall_cols, left_seam),
                 np.linspace(left_seam, right_seam, width - 2 * wall_cols),
                 np.full(wall_cols, right_seam)]
    mask = np.clip((np.arange(rows)[:, None] - seam + 3) / 6, 0, 1).astype(np.float32)
    # Feather light and pigment broadly while keeping architectural detail sharp.
    smooth_a = cv2.GaussianBlur(far, (0, 0), 12)
    smooth_b = cv2.GaussianBlur(near, (0, 0), 12)
    broad = cv2.GaussianBlur(mask, (0, 0), 15)[..., None]
    narrow = mask[..., None]
    blended = ((1 - broad) * smooth_a + broad * smooth_b
               + (1 - narrow) * (far - smooth_a) + narrow * (near - smooth_b))
    blended[..., 3] = (1 - mask) * far[..., 3] + mask * near[..., 3]
    blend = np.clip(np.minimum(np.arange(rows), np.arange(rows)[::-1]) / 18, 0, 1)[:, None, None]
    return blend * blended + (1 - blend) * ((1 - narrow) * far + narrow * near)

if __name__ == "__main__":
    plate = cv2.imread(str(ART / "night_road.png")).astype(np.float32)
    alpha = silhouettes(plate)
    depths = START + (np.arange(ROWS) + 0.5) * PERIOD / ROWS
    strip = project(plate, alpha, depths)
    overlap = depths >= START + PERIOD - OVERLAP
    strip[overlap] = join(project(plate, alpha, depths[overlap] - PERIOD), strip[overlap])
    cv2.imwrite(str(ART / "night_corridor.png"), np.uint8(np.clip(np.rint(strip), 0, 255)))
    cv2.imwrite(str(ART / "night_sky_reveal.png"), np.uint8(np.rint(sky_reveal(plate))))
