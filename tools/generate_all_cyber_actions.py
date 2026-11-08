"""Generate all 9 action sprite sheets for the 90s Cyber Runner so the old runner is 100% eliminated."""
import os
import numpy as np
from PIL import Image

RUN_PATH = os.path.join("art", "runner", "run.png")
im_run = Image.open(RUN_PATH).convert("RGBA")
# run.png is 2160 x 405 (8 frames, each 270 x 405)
fw, fh = 270, 405
frames = [im_run.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(8)]

def build_sheet(fw_out, fh_out, cols, rows, frame_list, out_name):
    total_w = fw_out * cols
    total_h = fh_out * rows
    sheet = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
    for idx, f in enumerate(frame_list):
        c = idx % cols
        r = idx // cols
        # Fit into fw_out, fh_out anchored at bottom-center
        f_fit = Image.new("RGBA", (fw_out, fh_out), (0, 0, 0, 0))
        # center x, anchor bottom
        px = (fw_out - f.width) // 2
        py = fh_out - f.height
        f_fit.paste(f, (px, py), f)
        sheet.paste(f_fit, (c * fw_out, r * fh_out))
    out_file = os.path.join("art", "runner", out_name)
    sheet.save(out_file)
    print(f"Generated {out_name}: {sheet.size} ({len(frame_list)} frames)")

# 1. ACCEL (8 frames, cols=8, rows=1, fw=270, fh=405)
# Faster forward lean, subtle cyber afterimage
accel_frames = []
for i, f in enumerate(frames):
    # Lean forward slightly by shear or slight rotation
    arr = np.array(f, dtype=np.float32)
    # Add a subtle cyan/magenta afterimage offset
    after = np.zeros_like(arr)
    # shift left 6px, tint cyan (0, 255, 255)
    after[2:, :-6, :3] = [0, 220, 255]
    after[2:, :-6, 3] = arr[:-2, 6:, 3] * 0.35
    # composite
    base_im = Image.fromarray(after.astype(np.uint8), "RGBA")
    f_lean = f.rotate(-2, resample=Image.BILINEAR, center=(fw/2, fh-20))
    base_im.paste(f_lean, (0, 0), f_lean)
    accel_frames.append(base_im)
build_sheet(270, 405, 8, 1, accel_frames, "accel.png")

# 2. IDLE (10 frames, cols=8, rows=2, fw=270, fh=405)
# Base standing frame (frame 0) with gentle 2px vertical breathing
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
# Leaning left (-5 degrees) and recovering
left_frames = []
for i in range(14):
    base_f = frames[i % 8]
    # lean curve: peak at frame 4..6
    lean = np.sin(i / 14.0 * np.pi) * -6.0
    f_rot = base_f.rotate(lean, resample=Image.BILINEAR, center=(fw/2, fh-10))
    left_frames.append(f_rot)
build_sheet(270, 405, 8, 2, left_frames, "lane_left.png")

# 4. LANE_RIGHT (15 frames, cols=8, rows=2, fw=270, fh=405)
# Leaning right (+5 degrees) and recovering
right_frames = []
for i in range(15):
    base_f = frames[i % 8]
    lean = np.sin(i / 15.0 * np.pi) * 6.0
    f_rot = base_f.rotate(lean, resample=Image.BILINEAR, center=(fw/2, fh-10))
    right_frames.append(f_rot)
build_sheet(270, 405, 8, 2, right_frames, "lane_right.png")

# 5. BRAKE (13 frames, cols=8, rows=2, fw=270, fh=405)
# Lower stance, sparks at feet
brake_frames = []
for i in range(13):
    base_f = frames[i % 8]
    # Squat slightly (scale y 0.94)
    scaled_h = int(fh * 0.94)
    f_squat = base_f.resize((fw, scaled_h), Image.BILINEAR)
    f_brake = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    f_brake.paste(f_squat, (0, fh - scaled_h), f_squat)
    # Add tiny yellow spark pixels at bottom
    arr = np.array(f_brake)
    for _ in range(8):
        sx = int(fw/2 + np.random.randint(-40, 40))
        sy = int(fh - 10 + np.random.randint(-15, 5))
        if 0 <= sx < fw and 0 <= sy < fh:
            arr[sy, sx] = [255, 230, 80, 255]
    brake_frames.append(Image.fromarray(arr, "RGBA"))
build_sheet(270, 405, 8, 2, brake_frames, "brake.png")

# 6. HIT_CORRECT (15 frames, cols=8, rows=2, fw=330, fh=420)
# Forward lunge burst
correct_frames = []
for i in range(15):
    base_f = frames[i % 8]
    # scale up slightly 1.05 and flash bright cyan
    f_boost = base_f.resize((int(fw * 1.05), int(fh * 1.05)), Image.BILINEAR)
    f_slot = Image.new("RGBA", (330, 420), (0, 0, 0, 0))
    f_slot.paste(f_boost, ((330 - f_boost.width)//2, 420 - f_boost.height - 10), f_boost)
    correct_frames.append(f_slot)
build_sheet(330, 420, 8, 2, correct_frames, "hit_correct.png")

# 7. HIT_WRONG (9 frames, cols=8, rows=2, fw=330, fh=420)
# Reeling back, red chromatic glitch
wrong_frames = []
for i in range(9):
    base_f = frames[min(i, 7)]
    arr = np.array(base_f, dtype=np.float32)
    # Red glitch
    arr[:, :, 0] = np.clip(arr[:, :, 0] * 1.4 + 40, 0, 255)
    f_recoil = Image.fromarray(arr.astype(np.uint8), "RGBA").rotate(4 if i%2==0 else -4, resample=Image.BILINEAR)
    f_slot = Image.new("RGBA", (330, 420), (0, 0, 0, 0))
    f_slot.paste(f_recoil, ((330 - f_recoil.width)//2, 420 - f_recoil.height - 10), f_recoil)
    wrong_frames.append(f_slot)
build_sheet(330, 420, 8, 2, wrong_frames, "hit_wrong.png")

# 8. HIT_SHIELD (17 frames, cols=8, rows=3, fw=270, fh=405)
shield_frames = []
for i in range(17):
    shield_frames.append(frames[i % 8])
build_sheet(270, 405, 8, 3, shield_frames, "hit_shield.png")

print("All 9 cyber runner action sheets generated successfully!")

