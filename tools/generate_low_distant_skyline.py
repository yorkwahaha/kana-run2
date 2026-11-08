"""Generate a low, distant, atmospheric 2160x420 Tokyo pixel skyline with 65% top transparency and soft ground blend."""
import numpy as np
from PIL import Image

w, h = 2160, 420
arr = np.zeros((h, w, 4), dtype=np.uint8)

np.random.seed(2026)

# Base skyline baseline: buildings sit below y=270 (top 270px is 100% transparent sky)
sky_cutoff = 260

# 1. Distant low-contrast silhouette layer
x = 0
while x < w:
    bw = np.random.randint(40, 80)
    bh = np.random.randint(70, 110)
    top_y = h - bh
    arr[top_y:h, x:x+bw] = [18, 14, 32, 255]
    # small window dots
    for wy in range(top_y + 10, h - 25, 7):
        for wx in range(x + 5, x + bw - 5, 7):
            if np.random.rand() > 0.45:
                arr[wy:wy+2, wx:wx+3] = [150, 140, 90, 160]
    x += bw

# 2. Main varied Tokyo skyline buildings (heights 80..150 px, top_y between 270 and 340)
x = 0
b_idx = 0
while x < w:
    bw = np.random.randint(50, 100)
    bh = np.random.randint(90, 145)
    top_y = h - bh
    
    # building body color: dark night purple-indigo
    col = [26, 18, 48, 255] if b_idx % 2 == 0 else [34, 24, 62, 255]
    arr[top_y:h, x:x+bw] = col
    
    # Top roof antenna / mast
    if np.random.rand() > 0.45:
        ant_x = x + bw // 2
        ant_h = np.random.randint(15, 35)
        ant_top = top_y - ant_h
        arr[ant_top:top_y, ant_x:ant_x+2] = [80, 70, 110, 255]
        # Red warning light at tip
        arr[ant_top:ant_top+2, ant_x-1:ant_x+3] = [255, 30, 30, 255]
        
    # Windows
    cols_n = bw // 10
    for r in range(top_y + 12, h - 20, 8):
        for c in range(cols_n):
            wx = x + 5 + c * 9
            if wx + 4 < x + bw and np.random.rand() > 0.35:
                rnd = np.random.rand()
                if rnd < 0.65:
                    wcol = [255, 230, 120, 240] # Warm yellow
                elif rnd < 0.85:
                    wcol = [80, 230, 255, 240]  # Cyan
                else:
                    wcol = [255, 80, 190, 240]  # Magenta
                arr[r:r+3, wx:wx+4] = wcol
                
    x += bw
    b_idx += 1

# 3. Tokyo Tower silhouette at x=1350
tx = 1350
t_base = h - 40
arr[t_base - 130:t_base, tx-1:tx+2] = [230, 50, 40, 255]
for ty in range(t_base - 100, t_base):
    span = int(((ty - (t_base - 100)) / 100.0) * 18)
    arr[ty, tx - span : tx + span + 1] = [220, 45, 35, 255]
    if ty in [t_base - 80, t_base - 50]:
        arr[ty:ty+3, tx - span - 2 : tx + span + 3] = [255, 240, 180, 255]

# 4. Horizontal seamless wrapping (blend first and last 120px)
bw_blend = 120
for i in range(bw_blend):
    t = i / float(bw_blend)
    arr[:, w - bw_blend + i] = ((1.0 - t) * arr[:, w - bw_blend + i].astype(np.float32) + t * arr[:, i].astype(np.float32)).astype(np.uint8)

# 5. Smooth bottom fog fade into dark street level (y=380..420)
for y in range(380, h):
    t = (y - 380) / 40.0
    street_dark = np.array([12, 10, 24, 255], dtype=np.float32)
    arr[y, :] = ((1.0 - t) * arr[y, :].astype(np.float32) + t * street_dark).astype(np.uint8)

im = Image.fromarray(arr, "RGBA")
out_p = "art/stage/far_skyline.png"
im.save(out_p)
print(f"Generated clean low-profile Tokyo skyline: {im.size}, 65% transparent sky!")

