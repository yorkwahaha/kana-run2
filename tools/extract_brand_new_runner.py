"""Extract and auto-center the brand new original 90s cyber runner (baggy cargo pants, oversized jacket, chunky sneakers) from chroma-key green sheet."""
import os
import numpy as np
from PIL import Image

src_p = r"C:\Users\York\.gemini\antigravity\brain\ffac2da6-5838-475f-8815-ccaa0e071612\pure_back_cyber_runner_1793986272202.jpg"
im = Image.open(src_p).convert("RGB")
w, h = im.size
fw_src, fh_src = w // 4, h // 2

fw_target, fh_target = 270, 405
sheet = Image.new("RGBA", (fw_target * 8, fh_target), (0, 0, 0, 0))

frames = []
for idx in range(8):
    c = idx % 4
    r = idx // 4
    crop = im.crop((c * fw_src, r * fh_src, (c + 1) * fw_src, (r + 1) * fh_src))
    arr = np.array(crop, dtype=np.float32)
    
    # Chroma key green:
    # greenness = g - max(r, b)
    greenness = arr[:, :, 1] - np.maximum(arr[:, :, 0], arr[:, :, 2])
    alpha = np.clip((50.0 - greenness) * (255.0 / 30.0), 0, 255)
    
    # Clean spill
    is_spill = greenness > 15
    arr[is_spill, 1] = np.maximum(arr[is_spill, 0], arr[is_spill, 2])
    
    rgba = np.zeros((fh_src, fw_src, 4), dtype=np.uint8)
    rgba[:, :, :3] = np.clip(arr, 0, 255).astype(np.uint8)
    rgba[:, :, 3] = alpha.astype(np.uint8)
    
    f_im = Image.fromarray(rgba, "RGBA")
    
    # Find bounding box of character
    alpha_ch = rgba[:, :, 3]
    mask = alpha_ch > 40
    y_idx, x_idx = np.where(mask)
    if len(y_idx) > 0:
        char_w = x_idx.max() - x_idx.min() + 1
        char_h = y_idx.max() - y_idx.min() + 1
        char_cropped = f_im.crop((x_idx.min(), y_idx.min(), x_idx.max() + 1, y_idx.max() + 1))
        
        # Scale character to fit target height ~315 px (leaving headroom and anchor room)
        target_char_h = 310
        scale = target_char_h / float(char_h)
        target_char_w = max(1, int(round(char_w * scale)))
        char_scaled = char_cropped.resize((target_char_w, target_char_h), Image.LANCZOS)
        
        # Center horizontally, place feet at y = 390
        slot = Image.new("RGBA", (fw_target, fh_target), (0, 0, 0, 0))
        paste_x = (fw_target - target_char_w) // 2
        paste_y = 390 - target_char_h
        slot.paste(char_scaled, (paste_x, paste_y), char_scaled)
        frames.append(slot)
    else:
        frames.append(Image.new("RGBA", (fw_target, fh_target), (0, 0, 0, 0)))

# Paste all 8 frames into run sheet
for i, f in enumerate(frames):
    sheet.paste(f, (i * fw_target, 0))

out_path = os.path.join("art", "runner", "run.png")
sheet.save(out_path)
print(f"Saved brand new original cyber runner run.png: {sheet.size} (8 frames, perfectly centered, baggy pants, chunky sneakers!)")

