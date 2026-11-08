"""
Process AI-generated pixel art Shibuya buildings with external floodfill cutout.
Extracts left-perspective and right-perspective buildings cleanly with zero clipping.
"""
import os
import cv2
import numpy as np
from PIL import Image

BRAIN_DIR = r"C:\Users\York\.gemini\antigravity\brain\ffac2da6-5838-475f-8815-ccaa0e071612"
PROPS_DIR = os.path.join("art", "stage", "props")
os.makedirs(PROPS_DIR, exist_ok=True)

BUILDINGS = [
    {
        "src": os.path.join(BRAIN_DIR, "cyberpunk_sega_arcade_building_left_street_1793997493556.jpg"),
        "dest": os.path.join(PROPS_DIR, "house_a.png"),
        "name": "house_a (Left Arcade)",
        "target_h": 720
    },
    {
        "src": os.path.join(BRAIN_DIR, "cyberpunk_ramen_tavern_building_v2_1793997588786.jpg"),
        "dest": os.path.join(PROPS_DIR, "shop.png"),
        "name": "shop (Left Ramen)",
        "target_h": 720
    },
    {
        "src": os.path.join(BRAIN_DIR, "shibuya_cyberpunk_record_tower_left_perspective_1793998911870.jpg"),
        "dest": os.path.join(PROPS_DIR, "house_l_record.png"),
        "name": "house_l_record (Left Record)",
        "target_h": 720
    },
    {
        "src": os.path.join(BRAIN_DIR, "shibuya_izakaya_tower_right_side_1793997506475.jpg"),
        "dest": os.path.join(PROPS_DIR, "house_b.png"),
        "name": "house_b (Right Izakaya)",
        "target_h": 720
    },
    {
        "src": os.path.join(BRAIN_DIR, "shibuya_karaoke_capsule_tower_right_perspective_1793997596327.jpg"),
        "dest": os.path.join(PROPS_DIR, "house_r_karaoke.png"),
        "name": "house_r_karaoke (Right Karaoke)",
        "target_h": 720
    },
    {
        "src": os.path.join(BRAIN_DIR, "shibuya_tower_right_side_1793998841739.jpg"),
        "dest": os.path.join(PROPS_DIR, "house_r_109.png"),
        "name": "house_r_109 (Right Shibuya 109)",
        "target_h": 720
    }
]

def extract_building(src_path, dest_path, target_h=720):
    bgr = cv2.imread(src_path)
    if bgr is None:
        raise FileNotFoundError(f"Could not load {src_path}")
    h, w = bgr.shape[:2]
    
    # 1. Pad image by 2 pixels on all sides with white to allow border flood fill to flow freely
    pad = 2
    padded_bgr = cv2.copyMakeBorder(bgr, pad, pad, pad, pad, cv2.BORDER_CONSTANT, value=[255, 255, 255])
    ph, pw = padded_bgr.shape[:2]
    
    # 2. FloodFill from (0,0) to identify the outer background only
    # Tolerance: 16 (matches near-white background without bleeding into colored building)
    mask = np.zeros((ph + 2, pw + 2), np.uint8)
    flood_fill_val = (0, 0, 0)
    # We flood fill with a distinctive value
    filled = padded_bgr.copy()
    cv2.floodFill(filled, mask, (0, 0), flood_fill_val, loDiff=(16, 16, 16), upDiff=(16, 16, 16), flags=4 | (255 << 8) | cv2.FLOODFILL_MASK_ONLY)
    
    # mask: 255 where flood fill reached (outer background), 0 inside building
    # Strip padding from mask
    bg_mask = mask[1+pad:ph+1-pad, 1+pad:pw+1-pad]
    
    # Building alpha: 255 where NOT background
    alpha = np.where(bg_mask == 0, 255, 0).astype(np.uint8)
    
    # Secondary check: Also flood from other three corners to ensure isolated pockets of exterior white are cleared
    for cx, cy in [(w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        if alpha[cy, cx] == 255 and np.all(bgr[cy, cx] > 235):
            sub_mask = np.zeros((h + 2, w + 2), np.uint8)
            cv2.floodFill(bgr.copy(), sub_mask, (cx, cy), 0, loDiff=(16, 16, 16), upDiff=(16, 16, 16), flags=4 | (255 << 8) | cv2.FLOODFILL_MASK_ONLY)
            alpha[sub_mask[1:-1, 1:-1] == 255] = 0

    # 3. Trim bounding box of the building
    coords = cv2.findNonZero(alpha)
    if coords is None:
        raise ValueError(f"Building extraction failed for {src_path} - no building detected!")
    bx, by, bw, bh = cv2.boundingRect(coords)
    
    # Crop to exact building bounds
    crop_bgr = bgr[by:by+bh, bx:bx+bw]
    crop_alpha = alpha[by:by+bh, bx:bx+bw]
    
    # 4. Clean edge despill / white matte de-halo:
    # Any border pixel with alpha > 0 that is very close to white (R,G,B > 240) should be blended or clipped
    near_white_edge = (crop_alpha > 0) & (crop_bgr[:, :, 0] > 242) & (crop_bgr[:, :, 1] > 242) & (crop_bgr[:, :, 2] > 242)
    # Soften / clear these extreme white fringe pixels on the outer contour
    crop_alpha[near_white_edge] = 0
    
    # Merge RGBA
    crop_rgb = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2RGB)
    rgba = np.dstack([crop_rgb, crop_alpha])
    
    pil_im = Image.fromarray(rgba, "RGBA")
    
    # 5. Scale to target height preserving exact aspect ratio
    scale = target_h / float(bh)
    target_w = max(1, int(round(bw * scale)))
    scaled_im = pil_im.resize((target_w, target_h), Image.LANCZOS)
    
    scaled_im.save(dest_path)
    print(f"Successfully processed {dest_path}: original=({bw}x{bh}), scaled=({target_w}x{target_h})")
    return target_w, target_h

if __name__ == "__main__":
    results = {}
    for item in BUILDINGS:
        tw, th = extract_building(item["src"], item["dest"], item["target_h"])
        results[os.path.basename(item["dest"]).replace(".png", "")] = [tw, th]
    print("\nUpdated Building Sizes:", results)
