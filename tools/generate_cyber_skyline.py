"""Generate an authentic 2160x420 pixel art Tokyo night skyline (far_skyline.png) with true transparency and varied skyscraper heights."""
import numpy as np
from PIL import Image

w, h = 2160, 420
arr = np.zeros((h, w, 4), dtype=np.uint8)

# Color palette:
# Dark silhouettes: (22, 16, 42), (32, 22, 60), (16, 12, 30)
# Glowing windows: warm yellow (255, 230, 110), cyan (80, 240, 255), magenta (255, 80, 180)
# Neon roof signs: vibrant red, blue, green, yellow

np.random.seed(1995)

# 1. Distant layer of smaller buildings (silhouette depth)
x = 0
while x < w:
    bw = np.random.randint(40, 90)
    bh = np.random.randint(180, 280)
    top_y = h - bh
    col = [20, 14, 38, 255]
    arr[top_y:h, x:x+bw] = col
    # tiny window dots
    for wy in range(top_y + 15, h - 30, 8):
        for wx in range(x + 6, x + bw - 6, 8):
            if np.random.rand() > 0.4:
                win_col = [180, 160, 100, 200] if np.random.rand() > 0.3 else [60, 180, 220, 180]
                arr[wy:wy+3, wx:wx+4] = win_col
    x += bw

# 2. Main layer of distinct Tokyo skyscrapers, towers, and neon roof signs
x = 0
building_id = 0
while x < w:
    bw = np.random.randint(60, 130)
    # Varied heights: some tall (up to 340px tall, leaving 80px sky), some medium (200..260px)
    bh = np.random.randint(190, 330)
    top_y = h - bh
    col = [28, 20, 52, 255] if building_id % 2 == 0 else [36, 26, 68, 255]
    arr[top_y:h, x:x+bw] = col
    
    # Roof antenna / tower structures
    if np.random.rand() > 0.5:
        ant_x = x + bw // 2
        ant_h = np.random.randint(15, 45)
        ant_top = max(10, top_y - ant_h)
        arr[ant_top:top_y, ant_x:ant_x+2] = [80, 70, 110, 255]
        # flashing red aircraft beacon on top
        arr[ant_top:ant_top+2, ant_x-1:ant_x+3] = [255, 40, 40, 255]

    # Neon roof billboard on some buildings
    if np.random.rand() > 0.4 and bw > 75:
        sign_w = np.random.randint(45, bw - 10)
        sign_h = np.random.randint(22, 38)
        sign_x = x + (bw - sign_w) // 2
        sign_y = top_y - sign_h + 5
        sign_col = [255, 30, 100] if building_id % 3 == 0 else ([0, 220, 255] if building_id % 3 == 1 else [255, 200, 40])
        # Border frame
        arr[sign_y:top_y, sign_x:sign_x+sign_w] = [15, 12, 25, 255]
        arr[sign_y:sign_y+2, sign_x:sign_x+sign_w] = sign_col + [255]
        arr[top_y-2:top_y, sign_x:sign_x+sign_w] = sign_col + [255]
        arr[sign_y:top_y, sign_x:sign_x+2] = sign_col + [255]
        arr[sign_y:top_y, sign_x+sign_w-2:sign_x+sign_w] = sign_col + [255]
        # glowing text lines inside
        arr[sign_y+6:sign_y+10, sign_x+6:sign_x+sign_w-6] = sign_col + [255]
        if sign_h > 28:
            arr[sign_y+14:sign_y+17, sign_x+10:sign_x+sign_w-10] = [255, 255, 255, 255]

    # Windows on building facade
    cols_count = bw // 12
    for r in range(top_y + 18, h - 20, 10):
        for c in range(cols_count):
            wx = x + 6 + c * 11
            if wx + 5 < x + bw and np.random.rand() > 0.35:
                # Window color
                rnd = np.random.rand()
                if rnd < 0.6:
                    wcol = [255, 225, 110, 255] # warm yellow
                elif rnd < 0.85:
                    wcol = [80, 220, 255, 255]  # office cyan
                else:
                    wcol = [255, 80, 180, 255]  # neon magenta
                arr[r:r+4, wx:wx+6] = wcol
                
    x += bw
    building_id += 1

# 3. Tokyo Tower replica in one section (around x=1400)
tx = 1420
t_base_y = h - 180
arr[t_base_y - 120:t_base_y, tx-2:tx+4] = [240, 60, 40, 255] # antenna
# triangular truss lattice
for ty in range(t_base_y - 100, t_base_y):
    progress = (ty - (t_base_y - 100)) / 100.0
    half_span = int(progress * 22)
    arr[ty, tx - half_span : tx + half_span + 1] = [230, 50, 40, 255]
    if ty % 10 == 0:
        arr[ty, tx - half_span : tx + half_span + 1] = [255, 240, 200, 255] # observation deck lights

# 4. Make horizontal seamless wrap: blend first 120px and last 120px
blend_w = 120
for bx in range(blend_w):
    t = bx / float(blend_w)
    # alpha & color smooth crossfade
    arr[:, w - blend_w + bx] = ((1.0 - t) * arr[:, w - blend_w + bx].astype(np.float32) + t * arr[:, bx].astype(np.float32)).astype(np.uint8)

# 5. Smooth bottom fog fade into the dark street level
fog_h = 50
for y in range(h - fog_h, h):
    t = (y - (h - fog_h)) / float(fog_h)
    dark_c = np.array([12, 10, 24, 255], dtype=np.float32)
    arr[y, :] = ((1.0 - t) * arr[y, :].astype(np.float32) + t * dark_c).astype(np.uint8)

im = Image.fromarray(arr, "RGBA")
out_p = "art/stage/far_skyline.png"
im.save(out_p)
print(f"Generated clean Tokyo pixel skyline: {im.size}, transparent top, no ugly crop edges!")
