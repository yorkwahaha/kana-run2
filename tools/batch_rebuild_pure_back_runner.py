"""Batch rebuild all 9 runner action sprite sheets from verified pure back-view frames into 90s Cyber Shibuya style."""
import os
import numpy as np
from PIL import Image

BACKUP_DIR = os.path.join("art_backup_v1", "runner")
OUT_DIR = os.path.join("art", "runner")

def restyle_frame(f_orig):
    arr = np.array(f_orig, dtype=np.float32)
    fh, fw = arr.shape[:2]
    alpha = arr[:, :, 3]
    mask = alpha > 20
    
    r = arr[:, :, 0]
    g = arr[:, :, 1]
    b = arr[:, :, 2]
    
    y_coords = np.arange(fh)[:, None]
    x_coords = np.arange(fw)[None, :]
    mid_x = fw // 2
    
    # 1. Hair
    is_hair = mask & (r < 80) & (g < 80) & (b < 80) & (y_coords < 160)
    
    # 2. Skin (arms, legs, neck)
    is_skin = mask & (r > 160) & (g > 110) & (b > 90) & (r > g) & (g >= b - 15) & ~is_hair
    
    # 3. Torso / Shirt
    is_torso_zone = mask & (y_coords >= 115) & (y_coords < 265) & ~is_skin & ~is_hair
    
    # 4. Bag: red strap/pouch
    is_bag = is_torso_zone & (r > 170) & (g < 130) & (b < 130)
    
    # 5. Jacket: torso excluding bag
    is_jacket = is_torso_zone & ~is_bag
    
    # 6. Shorts
    is_shorts = mask & (y_coords >= 255) & (y_coords < 325) & ~is_skin
    
    # 7. Shoes
    is_shoes = mask & (y_coords >= 325) & ~is_skin
    
    out = np.zeros_like(arr)
    out[:, :, 3] = alpha
    lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    
    # 1. Hair: dark indigo with cyan anime sheen
    out[is_hair, 0] = np.clip(35 + lum[is_hair] * 40, 0, 255)
    out[is_hair, 1] = np.clip(25 + lum[is_hair] * 45, 0, 255)
    out[is_hair, 2] = np.clip(55 + lum[is_hair] * 80, 0, 255)
    
    # 2. Skin
    out[is_skin, 0] = np.clip(245 * (0.6 + 0.4 * lum[is_skin]), 0, 255)
    out[is_skin, 1] = np.clip(185 * (0.6 + 0.4 * lum[is_skin]), 0, 255)
    out[is_skin, 2] = np.clip(160 * (0.6 + 0.4 * lum[is_skin]), 0, 255)
    
    # 3. Jacket: 90s Color-block Windbreaker (Electric Violet & Mint Cyan & Hot Pink hem)
    is_violet = is_jacket & ((y_coords < 170) | (np.abs(x_coords - mid_x) < 22))
    is_cyan = is_jacket & ~is_violet
    
    out[is_violet, 0] = np.clip(70 + lum[is_violet] * 90, 0, 255)
    out[is_violet, 1] = np.clip(20 + lum[is_violet] * 50, 0, 255)
    out[is_violet, 2] = np.clip(120 + lum[is_violet] * 120, 0, 255)
    
    out[is_cyan, 0] = np.clip(0 + lum[is_cyan] * 50, 0, 255)
    out[is_cyan, 1] = np.clip(170 + lum[is_cyan] * 85, 0, 255)
    out[is_cyan, 2] = np.clip(160 + lum[is_cyan] * 95, 0, 255)
    
    # Hot magenta stripe along bottom hem
    is_hem = is_jacket & (y_coords >= 248) & (y_coords <= 256)
    out[is_hem, :3] = [255, 30, 130]
        
    # 4. Bag: Charcoal navy cross-body sling bag with dark strap
    out[is_bag, 0] = np.clip(32 + lum[is_bag] * 40, 0, 255)
    out[is_bag, 1] = np.clip(28 + lum[is_bag] * 35, 0, 255)
    out[is_bag, 2] = np.clip(45 + lum[is_bag] * 50, 0, 255)
    
    # 5. Shorts: Charcoal navy
    out[is_shorts, 0] = np.clip(25 + lum[is_shorts] * 35, 0, 255)
    out[is_shorts, 1] = np.clip(22 + lum[is_shorts] * 30, 0, 255)
    out[is_shorts, 2] = np.clip(42 + lum[is_shorts] * 55, 0, 255)
    
    # 6. Shoes: Dark retro sneakers with glowing cyan soles
    out[is_shoes, 0] = np.clip(30 + lum[is_shoes] * 60, 0, 255)
    out[is_shoes, 1] = np.clip(25 + lum[is_shoes] * 50, 0, 255)
    out[is_shoes, 2] = np.clip(55 + lum[is_shoes] * 90, 0, 255)
    
    is_sole = is_shoes & (y_coords >= fh - 20)
    out[is_sole, :3] = [0, 240, 255] # Glowing cyan sole
    
    # 7. Headphones around neck
    is_band = mask & (y_coords >= 118) & (y_coords <= 126) & (np.abs(x_coords - mid_x) <= 24) & ~is_hair
    out[is_band, :3] = [30, 30, 35]
    is_ear = mask & (y_coords >= 122) & (y_coords <= 138) & (np.abs(np.abs(x_coords - mid_x) - 26) <= 4)
    out[is_ear, :3] = [0, 220, 255]
    
    # 32-bit pixel cluster quantization
    quantized = (np.round(out / 12.0) * 12.0).clip(0, 255)
    quantized[:, :, 3] = alpha
    return Image.fromarray(quantized.astype(np.uint8), "RGBA")

SPECS = {
    "run": {"fw": 270, "fh": 405, "cols": 8, "rows": 2, "frames": 12},
    "accel": {"fw": 270, "fh": 405, "cols": 8, "rows": 1, "frames": 8},
    "idle": {"fw": 270, "fh": 405, "cols": 8, "rows": 2, "frames": 10},
    "brake": {"fw": 270, "fh": 405, "cols": 8, "rows": 2, "frames": 13},
    "lane_left": {"fw": 270, "fh": 405, "cols": 8, "rows": 2, "frames": 14},
    "lane_right": {"fw": 270, "fh": 405, "cols": 8, "rows": 2, "frames": 15},
    "hit_correct": {"fw": 330, "fh": 420, "cols": 8, "rows": 2, "frames": 15},
    "hit_wrong": {"fw": 330, "fh": 420, "cols": 8, "rows": 2, "frames": 9},
    "hit_shield": {"fw": 270, "fh": 405, "cols": 8, "rows": 3, "frames": 17},
}

def process_all():
    for name, spec in SPECS.items():
        src_path = os.path.join(BACKUP_DIR, f"{name}.png")
        if not os.path.exists(src_path):
            print(f"Skipping {name}: not found in backup")
            continue
        im = Image.open(src_path).convert("RGBA")
        fw = spec["fw"]
        fh = spec["fh"]
        cols = spec["cols"]
        rows = spec["rows"]
        n_frames = spec["frames"]
        
        out_sheet = Image.new("RGBA", (cols * fw, rows * fh), (0, 0, 0, 0))
        for idx in range(n_frames):
            c = idx % cols
            r = idx // cols
            frame_crop = im.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
            frame_styled = restyle_frame(frame_crop)
            out_sheet.paste(frame_styled, (c * fw, r * fh))
            
        out_path = os.path.join(OUT_DIR, f"{name}.png")
        out_sheet.save(out_path)
        print(f"Rebuilt pure back-view {name}.png: {out_sheet.size} ({n_frames} frames)")

if __name__ == "__main__":
    process_all()
    print("ALL 9 RUNNER ACTIONS REBUILT WITH PURE BACK-VIEW ANATOMY!")

