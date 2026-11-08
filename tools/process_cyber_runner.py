import os
import numpy as np
from PIL import Image

BRAIN_DIR = r"C:\Users\York\.gemini\antigravity\brain\ffac2da6-5838-475f-8815-ccaa0e071612"
src = os.path.join(BRAIN_DIR, "cyber_runner_run_1793980666889.jpg")
im = Image.open(src).convert("RGB")
w, h = im.size

# Target: 8 frames, each 270 x 405 (total 2160 x 405)
fw, fh = 270, 405
sheet = Image.new("RGBA", (fw * 8, fh), (0, 0, 0, 0))

# 4 cols x 2 rows in source (344 x 384)
src_cols, src_rows = 4, 2
src_fw = w // src_cols
src_fh = h // src_rows

# Sample background color from outer border
arr = np.array(im, dtype=np.float32)
bg_col = np.array([152.0, 118.0, 130.0], dtype=np.float32)

for idx in range(8):
    c = idx % src_cols
    r = idx // src_cols
    box = (c * src_fw, r * src_fh, (c + 1) * src_fw, (r + 1) * src_fh)
    frame_crop = im.crop(box)
    
    # Chroma-key remove background
    f_arr = np.array(frame_crop, dtype=np.float32)
    # Distance from bg color
    dist = np.sqrt(np.sum((f_arr - bg_col) ** 2, axis=-1))
    
    # Threshold for transparency: < 18 is full transparent, 18..35 is feather
    alpha = np.clip((dist - 16.0) * (255.0 / 18.0), 0, 255)
    
    rgba = np.zeros((src_fh, src_fw, 4), dtype=np.uint8)
    rgba[:, :, :3] = np.clip(f_arr, 0, 255).astype(np.uint8)
    rgba[:, :, 3] = alpha.astype(np.uint8)
    
    frame_im = Image.fromarray(rgba, "RGBA")
    
    # Scale and center to 270 x 405, align feet to bottom anchor (ay ~ 399)
    # Character height in frame is around 320 px, scale by ~1.05
    scaled = frame_im.resize((int(src_fw * 0.95), int(src_fh * 0.95)), Image.LANCZOS)
    
    # Paste centered horizontally, feet anchored near y=390
    paste_x = (fw - scaled.width) // 2
    paste_y = fh - scaled.height - 15
    
    f_slot = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    f_slot.paste(scaled, (paste_x, paste_y), scaled)
    
    sheet.paste(f_slot, (idx * fw, 0))

out_path = os.path.join("art", "runner", "run.png")
sheet.save(out_path)
print("Saved cyber runner run.png:", sheet.size)

