"""Restyle pure back-view runner frames into 90s Arcade Cyber Shibuya pixel style."""
import os
import numpy as np
from PIL import Image

def restyle_frame(f_orig):
    """
    Takes an original pure back-view frame (RGBA, 270x405),
    identifies clothing, skin, backpack, hair, shoes,
    and paints them in 90s Cyber Shibuya palette with crisp pixel outlines and neon accents.
    """
    arr = np.array(f_orig, dtype=np.float32)
    # alpha mask
    alpha = arr[:, :, 3]
    mask = alpha > 20
    
    r = arr[:, :, 0]
    g = arr[:, :, 1]
    b = arr[:, :, 2]
    
    # Identify parts by original color ranges:
    # 1. Hair: dark grey/brown (r < 75, g < 75, b < 75)
    is_hair = mask & (r < 80) & (g < 80) & (b < 80) & (np.arange(405)[:, None] < 160)
    
    # 2. Skin (arms, legs, neck): warm peach (r > 180, g in 130..190, b in 110..170, r > g > b)
    is_skin = mask & (r > 160) & (g > 110) & (b > 90) & (r > g) & (g >= b - 15) & ~is_hair
    
    # 3. Shirt/Torso: was pale mint green (r in 160..230, g in 200..255, b in 170..235)
    # or general upper body (y between 120 and 260)
    y_coords = np.arange(405)[:, None]
    is_torso_zone = mask & (y_coords >= 120) & (y_coords < 265) & ~is_skin & ~is_hair
    
    # 4. Bag: was red/coral (r > 190, g < 130, b < 130)
    is_bag = is_torso_zone & (r > 170) & (g < 130) & (b < 130)
    
    # Jacket is torso excluding bag
    is_jacket = is_torso_zone & ~is_bag
    
    # 5. Shorts: was navy blue (r < 90, g < 100, b in 90..160)
    is_shorts = mask & (y_coords >= 255) & (y_coords < 320) & ~is_skin
    
    # 6. Shoes: bottom region (y >= 330)
    is_shoes = mask & (y_coords >= 330) & ~is_skin
    
    # --- NOW APPLY 90s CYBER SHIBUYA RETRO COLORING ---
    out = np.zeros_like(arr)
    out[:, :, 3] = alpha
    
    # Base: keep original luminance/shading
    lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    
    # 1. Hair: dark anime purple-indigo with cyan highlight
    out[is_hair, 0] = np.clip(35 + lum[is_hair] * 40, 0, 255)
    out[is_hair, 1] = np.clip(25 + lum[is_hair] * 45, 0, 255)
    out[is_hair, 2] = np.clip(55 + lum[is_hair] * 80, 0, 255)
    
    # 2. Skin: clean anime shaded peach
    out[is_skin, 0] = np.clip(245 * (0.6 + 0.4 * lum[is_skin]), 0, 255)
    out[is_skin, 1] = np.clip(185 * (0.6 + 0.4 * lum[is_skin]), 0, 255)
    out[is_skin, 2] = np.clip(160 * (0.6 + 0.4 * lum[is_skin]), 0, 255)
    
    # 3. Jacket: 90s retro color-block windbreaker!
    # Split torso by x/y into Electric Violet (#541882) and Mint Cyan (#00e5c8), with Hot Magenta (#ff2080) trims
    x_coords = np.arange(270)[None, :]
    mid_x = 135
    
    # Upper shoulders & center spine: Electric Violet
    is_violet = is_jacket & ((y_coords < 170) | (np.abs(x_coords - mid_x) < 22))
    # Outer sleeves / sides: Mint Cyan
    is_cyan = is_jacket & ~is_violet
    
    # Violet shading
    out[is_violet, 0] = np.clip(70 + lum[is_violet] * 90, 0, 255)
    out[is_violet, 1] = np.clip(20 + lum[is_violet] * 50, 0, 255)
    out[is_violet, 2] = np.clip(120 + lum[is_violet] * 120, 0, 255)
    
    # Cyan shading
    out[is_cyan, 0] = np.clip(0 + lum[is_cyan] * 50, 0, 255)
    out[is_cyan, 1] = np.clip(170 + lum[is_cyan] * 85, 0, 255)
    out[is_cyan, 2] = np.clip(160 + lum[is_cyan] * 95, 0, 255)
    
    # Hot magenta stripe along bottom hem of jacket
    is_hem = is_jacket & (y_coords >= 248) & (y_coords <= 256)
    out[is_hem, 0] = 255
    out[is_hem, 1] = 30
    out[is_hem, 2] = 130
    
    # Neon kanji patch on center back (130 <= x <= 140, 180 <= y <= 220)
    is_patch = is_jacket & (np.abs(x_coords - mid_x) <= 12) & (y_coords >= 180) & (y_coords <= 222)
    # make glowing cyan cross/kanji pattern
    if is_patch.any():
        out[is_patch, 0] = 220
        out[is_patch, 1] = 255
        out[is_patch, 2] = 255
        
    # 4. Bag: Cyber tech cross-body sling bag (deep charcoal + electric magenta zipper)
    out[is_bag, 0] = np.clip(35 + lum[is_bag] * 50, 0, 255)
    out[is_bag, 1] = np.clip(30 + lum[is_bag] * 40, 0, 255)
    out[is_bag, 2] = np.clip(50 + lum[is_bag] * 60, 0, 255)
    
    # 5. Shorts: Dark cyber cargo pants/shorts (charcoal navy)
    out[is_shorts, 0] = np.clip(25 + lum[is_shorts] * 35, 0, 255)
    out[is_shorts, 1] = np.clip(22 + lum[is_shorts] * 30, 0, 255)
    out[is_shorts, 2] = np.clip(42 + lum[is_shorts] * 55, 0, 255)
    
    # 6. Shoes: 90s chunky sneakers with glowing neon cyan soles
    out[is_shoes, 0] = np.clip(30 + lum[is_shoes] * 60, 0, 255)
    out[is_shoes, 1] = np.clip(25 + lum[is_shoes] * 50, 0, 255)
    out[is_shoes, 2] = np.clip(55 + lum[is_shoes] * 90, 0, 255)
    # Sole glow (lowest 10% of shoe pixels)
    is_sole = is_shoes & (y_coords >= 385)
    out[is_sole, 0] = 0
    out[is_sole, 1] = 240
    out[is_sole, 2] = 255
    
    # Add Headphones resting on neck (around y=115..135, x near shoulders)
    is_headphone_band = mask & (y_coords >= 118) & (y_coords <= 126) & (np.abs(x_coords - mid_x) <= 24) & ~is_hair
    out[is_headphone_band, :3] = [30, 30, 35]
    is_headphone_ear = mask & (y_coords >= 122) & (y_coords <= 138) & (np.abs(np.abs(x_coords - mid_x) - 26) <= 4)
    out[is_headphone_ear, :3] = [0, 220, 255] # glowing cyan ear-cups!
    
    # Pixel art quantization: snap colors to 32-bit pixel clusters
    quantized = (np.round(out / 16.0) * 16.0).clip(0, 255)
    quantized[:, :, 3] = alpha
    return Image.fromarray(quantized.astype(np.uint8), "RGBA")

if __name__ == "__main__":
    im = Image.open("art_backup_v1/runner/run.png").convert("RGBA")
    f0 = im.crop((0, 0, 270, 405))
    res = restyle_frame(f0)
    res.save("scratch_cyber_back_f0.png")
    print("Test restyled frame 0 saved to scratch_cyber_back_f0.png")

