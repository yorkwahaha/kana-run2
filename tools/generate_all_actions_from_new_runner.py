"""Generate all 9 action sprite sheets from the genuine brand-new original 90s cyber runner."""
import os
import numpy as np
from PIL import Image

RUN_PATH = os.path.join("art", "runner", "run.png")
im_run = Image.open(RUN_PATH).convert("RGBA")
fw, fh = 270, 405
frames = [im_run.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(8)]

def build_sheet(fw_out, fh_out, cols, rows, frame_list, out_name):
    total_w = fw_out * cols
    total_h = fh_out * rows
    sheet = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
    for idx, f in enumerate(frame_list):
        c = idx % cols
        r = idx // cols
        f_fit = Image.new("RGBA", (fw_out, fh_out), (0, 0, 0, 0))
        px = (fw_out - f.width) // 2
        py = fh_out - f.height
        f_fit.paste(f, (px, py), f)
        sheet.paste(f_fit, (c * fw_out, r * fh_out))
    out_file = os.path.join("art", "runner", out_name)
    sheet.save(out_file)
    print(f"Generated {out_name}: {sheet.size} ({len(frame_list)} frames)")

# 1. ACCEL (8 frames, cols=8, rows=1, fw=270, fh=405)
accel_frames = []
for i, f in enumerate(frames):
    arr = np.array(f, dtype=np.float32)
    after = np.zeros_like(arr)
    after[2:, :-4, :3] = [0, 220, 255]
    after[2:, :-4, 3] = arr[:-2, 4:, 3] * 0.3
    base_im = Image.fromarray(after.astype(np.uint8), "RGBA")
    f_lean = f.rotate(-2, resample=Image.BILINEAR, center=(fw/2, fh-20))
    base_im.paste(f_lean, (0, 0), f_lean)
    accel_frames.append(base_im)
build_sheet(270, 405, 8, 1, accel_frames, "accel.png")

# 2. IDLE (10 frames, cols=8, rows=2, fw=270, fh=405)
idle_base = frames[0]
idle_frames = []
for i in range(10):
    t = np.sin(i / 10.0 * np.pi * 2.0)
    dy = int(round(t * 3.0))
    f_idle = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    f_idle.paste(idle_base, (0, dy), idle_base)
    idle_frames.append(f_idle)
build_sheet(270, 405, 8, 2, idle_frames, "idle.png")

# 3. LANE_LEFT (14 frames, cols=8, rows=2, fw=270, fh=405)
left_frames = []
for i in range(14):
    base_f = frames[i % 8]
    lean = np.sin(i / 14.0 * np.pi) * -5.0
    f_rot = base_f.rotate(lean, resample=Image.BILINEAR, center=(fw/2, fh-10))
    left_frames.append(f_rot)
build_sheet(270, 405, 8, 2, left_frames, "lane_left.png")

# 4. LANE_RIGHT (15 frames, cols=8, rows=2, fw=270, fh=405)
right_frames = []
for i in range(15):
    base_f = frames[i % 8]
    lean = np.sin(i / 15.0 * np.pi) * 5.0
    f_rot = base_f.rotate(lean, resample=Image.BILINEAR, center=(fw/2, fh-10))
    right_frames.append(f_rot)
build_sheet(270, 405, 8, 2, right_frames, "lane_right.png")

# 5. BRAKE (13 frames, cols=8, rows=2, fw=270, fh=405)
brake_frames = []
for i in range(13):
    base_f = frames[i % 8]
    scaled_h = int(fh * 0.95)
    f_squat = base_f.resize((fw, scaled_h), Image.BILINEAR)
    f_brake = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    f_brake.paste(f_squat, (0, fh - scaled_h), f_squat)
    brake_frames.append(f_brake)
build_sheet(270, 405, 8, 2, brake_frames, "brake.png")

# 6. HIT_CORRECT (15 frames, cols=8, rows=2, fw=330, fh=420)
correct_frames = []
for i in range(15):
    base_f = frames[i % 8]
    f_boost = base_f.resize((int(fw * 1.05), int(fh * 1.05)), Image.BILINEAR)
    f_slot = Image.new("RGBA", (330, 420), (0, 0, 0, 0))
    f_slot.paste(f_boost, ((330 - f_boost.width)//2, 420 - f_boost.height - 10), f_boost)
    correct_frames.append(f_slot)
build_sheet(330, 420, 8, 2, correct_frames, "hit_correct.png")

# 7. HIT_WRONG (9 frames, cols=8, rows=2, fw=330, fh=420)
wrong_frames = []
for i in range(9):
    base_f = frames[min(i, 7)]
    arr = np.array(base_f, dtype=np.float32)
    arr[:, :, 0] = np.clip(arr[:, :, 0] * 1.3 + 30, 0, 255)
    f_recoil = Image.fromarray(arr.astype(np.uint8), "RGBA").rotate(3 if i%2==0 else -3, resample=Image.BILINEAR)
    f_slot = Image.new("RGBA", (330, 420), (0, 0, 0, 0))
    f_slot.paste(f_recoil, ((330 - f_recoil.width)//2, 420 - f_recoil.height - 10), f_recoil)
    wrong_frames.append(f_slot)
build_sheet(330, 420, 8, 2, wrong_frames, "hit_wrong.png")

# 8. HIT_SHIELD (17 frames, cols=8, rows=3, fw=270, fh=405)
shield_frames = []
for i in range(17):
    shield_frames.append(frames[i % 8])
build_sheet(270, 405, 8, 3, shield_frames, "hit_shield.png")

print("All 9 brand-new cyber runner action sheets built successfully!")

