"""Upgrade petals_atlas and sparks_atlas into 90s Cyber Shibuya neon embers and arcade glass-break sparks."""
import os
import numpy as np
from PIL import Image

VFX_DIR = os.path.join("art", "vfx")
os.makedirs(VFX_DIR, exist_ok=True)

# 1. petals_atlas.png (256 x 64, 4 cells of 64x64)
# Turn into floating neon light embers (cyan, magenta, gold, electric white)
petals = Image.new("RGBA", (256, 64), (0, 0, 0, 0))

# Cell 0: Cyan 4-point pixel star
c0 = np.zeros((64, 64, 4), dtype=np.uint8)
# center cross star
cx, cy = 32, 32
for i in range(-12, 13):
    d = abs(i)
    a = max(0, 255 - d * 20)
    c0[cy, cx + i] = [0, 230, 255, a]
    c0[cy + i, cx] = [0, 230, 255, a]
# center core 3x3 bright white
c0[cy-1:cy+2, cx-1:cx+2] = [220, 255, 255, 255]
petals.paste(Image.fromarray(c0, "RGBA"), (0, 0))

# Cell 1: Neon magenta glowing ember square
c1 = np.zeros((64, 64, 4), dtype=np.uint8)
for y in range(24, 40):
    for x in range(24, 40):
        dx, dy = abs(x - 32), abs(y - 32)
        dist = max(dx, dy)
        if dist <= 6:
            c1[y, x] = [255, 40, 180, 240]
        elif dist <= 9:
            c1[y, x] = [200, 20, 140, 120]
c1[30:35, 30:35] = [255, 220, 245, 255]
petals.paste(Image.fromarray(c1, "RGBA"), (64, 0))

# Cell 2: Golden spark diamond
c2 = np.zeros((64, 64, 4), dtype=np.uint8)
for y in range(64):
    for x in range(64):
        d = abs(x - 32) + abs(y - 32)
        if d <= 5:
            c2[y, x] = [255, 220, 80, 255]
        elif d <= 9:
            c2[y, x] = [255, 160, 20, 140]
c2[31:34, 31:34] = [255, 255, 220, 255]
petals.paste(Image.fromarray(c2, "RGBA"), (128, 0))

# Cell 3: Electric cyan-white pixel dust mote
c3 = np.zeros((64, 64, 4), dtype=np.uint8)
for y in range(28, 37):
    for x in range(28, 37):
        c3[y, x] = [120, 240, 255, 180]
c3[30:35, 30:35] = [240, 255, 255, 255]
petals.paste(Image.fromarray(c3, "RGBA"), (192, 0))

petals.save(os.path.join(VFX_DIR, "petals_atlas.png"))
print("Saved cyber neon embers: petals_atlas.png")

# 2. sparks_atlas.png (256 x 64, 4 cells of 64x64)
# High-energy glass shatter / arcade hit sparks
sparks = Image.new("RGBA", (256, 64), (0, 0, 0, 0))

# 4 progressive explosive spark frames
for idx in range(4):
    s = np.zeros((64, 64, 4), dtype=np.uint8)
    n_sparks = 10 + idx * 6
    radius = 6 + idx * 7
    # generate radiant glass crystal sparks
    np.random.seed(42 + idx)
    angles = np.linspace(0, np.pi * 2, n_sparks, endpoint=False)
    for a in angles:
        r = radius + np.random.uniform(-3, 3)
        sx = int(32 + np.cos(a) * r)
        sy = int(32 + np.sin(a) * r)
        if 2 <= sx < 62 and 2 <= sy < 62:
            # Alternate cyan, gold, and white glass shards
            col = [0, 240, 255, 240] if idx % 2 == 0 else [255, 220, 60, 240]
            s[sy-1:sy+2, sx-1:sx+2] = col
            s[sy, sx] = [255, 255, 255, 255]
    # Center flare
    if idx < 2:
        s[29:36, 29:36] = [255, 255, 255, 255 - idx * 80]
    sparks.paste(Image.fromarray(s, "RGBA"), (idx * 64, 0))

sparks.save(os.path.join(VFX_DIR, "sparks_atlas.png"))
print("Saved cyber arcade glass sparks: sparks_atlas.png")

