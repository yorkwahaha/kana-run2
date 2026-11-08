"""Upgrade roadside props in res://art/stage/props/ to 90s Cyber Shibuya theme."""
import os
import numpy as np
from PIL import Image

BRAIN_DIR = r"C:\Users\York\.gemini\antigravity\brain\ffac2da6-5838-475f-8815-ccaa0e071612"
concept_b = os.path.join(BRAIN_DIR, "concept_B_shibuya.jpg")
im = Image.open(concept_b).convert("RGB")
w, h = im.size

PROPS_DIR = os.path.join("art", "stage", "props")
os.makedirs(PROPS_DIR, exist_ok=True)

# 1. shop.png: Ramen & Izakaya storefront (from mid-left of concept_b)
# Target size ~640 x 566
shop_crop = im.crop((int(w * 0.35), int(h * 0.25), int(w * 0.65), int(h * 0.65)))
shop_im = shop_crop.resize((640, 566), Image.LANCZOS).convert("RGBA")
shop_im.save(os.path.join(PROPS_DIR, "shop.png"))
print("Saved cyber shop.png")

# 2. house_a.png: Neon commercial building A (left skyscraper facade with Karaoke signs)
# Target size ~611 x 640
house_a_crop = im.crop((int(w * 0.02), int(h * 0.15), int(w * 0.3), int(h * 0.65)))
house_a_im = house_a_crop.resize((611, 640), Image.LANCZOS).convert("RGBA")
house_a_im.save(os.path.join(PROPS_DIR, "house_a.png"))
print("Saved cyber house_a.png")

# 3. house_b.png: Neon commercial building B (right side arcade & neon signs)
# Target size ~640 x 601
house_b_crop = im.crop((int(w * 0.7), int(h * 0.15), int(w * 0.98), int(h * 0.65)))
house_b_im = house_b_crop.resize((640, 601), Image.LANCZOS).convert("RGBA")
house_b_im.save(os.path.join(PROPS_DIR, "house_b.png"))
print("Saved cyber house_b.png")

# 4. sakura_big.png & sakura_small.png:
# Replace the pink ancient cherry trees with clean modern cyber street trees / light poles with electric cyan leaves
for name, sz in [("sakura_big.png", (640, 640)), ("sakura_small.png", (468, 640))]:
    # create a night street tree tinted in cool electric cyan/purple with neon fairy light sparkles
    old_p = os.path.join(PROPS_DIR, name)
    if os.path.exists(old_p):
        old_im = Image.open(old_p).convert("RGBA")
        arr = np.array(old_im, dtype=np.float32)
        # Shift pink petals (high red, high blue) to electric cyber cyan/magenta
        # where alpha > 0
        mask = arr[:, :, 3] > 20
        # Tint leaves into cyberpunk cool indigo and mint cyan
        arr[mask, 0] = arr[mask, 0] * 0.3 + 20   # reduce warm pink
        arr[mask, 1] = arr[mask, 1] * 1.3 + 30   # boost cool cyan/green
        arr[mask, 2] = arr[mask, 2] * 1.4 + 50   # boost electric blue
        tree_out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
        tree_out.save(os.path.join(PROPS_DIR, name))
        print(f"Tinted cyber {name}")

# 5. wall.png: Modern concrete barrier with yellow safety stripes
# Target size 640 x 218
wall_arr = np.zeros((218, 640, 4), dtype=np.uint8)
wall_arr[:, :, :3] = [30, 25, 45]  # dark concrete
wall_arr[:, :, 3] = 255
# Add yellow diagonal safety stripes
for x in range(640):
    if (x // 25) % 2 == 0:
        wall_arr[50:110, x, :3] = [230, 190, 40]
wall_im = Image.fromarray(wall_arr, "RGBA")
wall_im.save(os.path.join(PROPS_DIR, "wall.png"))
print("Saved cyber wall.png")

print("All cyber props upgraded successfully!")

