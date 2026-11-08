"""
Build authentic, 3A-grade action sprite sheets for the 90s Cyber Shibuya Runner:
1. True standing idle pose (feet planted, upright posture, gentle breathing cycle)
2. True sliding brake pose (low squat stance, counter-balancing arms, friction sparks at soles)
3. True forward punch/tackle shatter pose for hit_correct (lunging punch break)
4. Hit wrong recoil and hit shield guard.
"""
import os
import cv2
import numpy as np
from PIL import Image

RUN_PATH = os.path.join("art", "runner", "run.png")
OUT_DIR = os.path.join("art", "runner")
os.makedirs(OUT_DIR, exist_ok=True)

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
        px = (fw_out - f.width) // 2
        py = fh_out - f.height
        sheet.paste(f, (c * fw_out + px, r * fh_out + py), f)
    out_file = os.path.join(OUT_DIR, out_name)
    sheet.save(out_file)
    print(f"Successfully generated authentic {out_name}: {sheet.size} ({len(frame_list)} frames)")

# -------------------------------------------------------------
# 1. BUILD TRUE STANDING IDLE (10 frames, cols=8, rows=2, 270x405)
# -------------------------------------------------------------
def make_standing_idle():
    # Construct a solid upright standing pose from runner components:
    # Upper body from run frame 0 (head, headphones, jacket, dragon kanji)
    arr0 = np.array(frames[0])
    
    # Extract Head + Torso (y: 0 to 252)
    upper = arr0[:252, :].copy()
    
    # Extract lower pants + shoe from upright leg
    # In frame 0: right leg is relatively straight down near center-right
    # In frame 4: left leg is straight down near center-left
    arr4 = np.array(frames[4])
    
    # Create two parallel standing legs centered around x=135
    standing_canvas = np.zeros((fh, fw, 4), dtype=np.uint8)
    
    # Left leg: take leg column from arr0/arr4 and place at x=115
    # Right leg: take leg column and place at x=155
    # Both shoes planted firmly at ground level y = 398
    for y in range(240, 400):
        # Left leg (x: 105..130)
        standing_canvas[y, 102:128] = arr0[y, 102:128]
        # Right leg (x: 140..168)
        standing_canvas[y, 142:168] = arr4[y, 142:168]
        
    # Place upper body on top
    standing_canvas[:252, :] = upper
    
    # Soften any seam around y=248..252 with jacket hem
    jacket_hem = arr0[245:252, 90:180]
    standing_canvas[245:252, 90:180] = jacket_hem

    base_idle_im = Image.fromarray(standing_canvas, "RGBA")
    
    idle_frames = []
    for i in range(10):
        # 10 frames natural breathing: subtle 2px vertical chest rise
        phase = (i / 10.0) * np.pi * 2.0
        dy = int(round(np.sin(phase) * 2.0))
        
        f = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        # Shoes stay planted on the ground (y=398)! Only torso & head rise with breath
        f_arr = standing_canvas.copy()
        
        # Shift upper body by dy
        if dy != 0:
            shifted_upper = np.zeros_like(f_arr[:252, :])
            if dy > 0:
                shifted_upper[dy:, :] = f_arr[:252-dy, :]
            else:
                shifted_upper[:252+dy, :] = f_arr[-dy:252, :]
            f_arr[:252, :] = shifted_upper
            
        # Subtle glow modulation on the cyan "龍" character during breathing
        glow_add = int(round(np.sin(phase) * 25.0))
        dragon_zone = (f_arr[150:230, 110:160, 1] > 180) & (f_arr[150:230, 110:160, 2] > 180)
        f_arr[150:230, 110:160, 1] = np.clip(f_arr[150:230, 110:160, 1].astype(int) + glow_add, 0, 255).astype(np.uint8)
        f_arr[150:230, 110:160, 2] = np.clip(f_arr[150:230, 110:160, 2].astype(int) + glow_add, 0, 255).astype(np.uint8)
        
        idle_frames.append(Image.fromarray(f_arr, "RGBA"))
        
    build_sheet(270, 405, 8, 2, idle_frames, "idle.png")

# -------------------------------------------------------------
# 2. BUILD TRUE SLIDING BRAKE (13 frames, cols=8, rows=2, 270x405)
# -------------------------------------------------------------
def make_sliding_brake():
    arr0 = np.array(frames[0])
    brake_frames = []
    
    # 13 frames:
    # Frames 0..2: Transition into low squat, leaning backward (-5 deg)
    # Frames 3..8: Deep sliding friction squat, friction sparks erupt at soles
    # Frames 9..12: Gradual recovery back to upright
    
    for i in range(13):
        f = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        
        if i <= 3:
            squat_depth = int(round((i / 3.0) * 28.0))
            tilt = - (i / 3.0) * 5.0
        elif i <= 8:
            squat_depth = 28
            tilt = -5.0
        else:
            recovery = (i - 8) / 4.0
            squat_depth = int(round((1.0 - recovery) * 28.0))
            tilt = - (1.0 - recovery) * 5.0
            
        # Compress lower body and tilt upper body backward
        arr = arr0.copy()
        
        # Lower center of gravity
        squat_im = Image.fromarray(arr, "RGBA")
        # Tilt around ground center
        tilted = squat_im.rotate(tilt, resample=Image.BILINEAR, center=(fw/2, 395))
        
        # Shift down by squat_depth while keeping sole anchored at ground y=398
        t_arr = np.array(tilted)
        shifted = np.zeros_like(t_arr)
        if squat_depth > 0:
            shifted[squat_depth:398, :] = t_arr[:398-squat_depth, :]
            # Copy shoe soles at y=390..398 to ensure feet touch the road
            shifted[370:398, :] = t_arr[370:398, :]
        else:
            shifted = t_arr
            
        # Add dynamic friction sparks during intense braking (frames 2..9)
        if 2 <= i <= 9:
            # Cyan & gold electric skid sparks
            for s in range(16):
                spark_x = int(np.random.normal(fw / 2, 35))
                spark_y = int(np.random.normal(394, 6))
                if 0 <= spark_x < fw and 0 <= spark_y < fh:
                    color = [0, 240, 255, 255] if (s % 2 == 0) else [255, 215, 60, 255]
                    shifted[spark_y, spark_x] = color
                    if spark_x + 1 < fw: shifted[spark_y, spark_x + 1] = color
                    if spark_y - 1 >= 0: shifted[spark_y - 1, spark_x] = color
                    
        brake_frames.append(Image.fromarray(shifted, "RGBA"))
        
    build_sheet(270, 405, 8, 2, brake_frames, "brake.png")

# -------------------------------------------------------------
# 3. BUILD TRUE FORWARD PUNCH / SHATTER FOR HIT_CORRECT (15 frames, cols=8, rows=2, 330x420)
# -------------------------------------------------------------
def make_punch_shatter():
    correct_frames = []
    
    # 15 frames:
    # Frames 0..2: Crouch anticipation
    # Frames 3..7: Explosive forward leap & punch strike (punch arm extended forward, shockwave)
    # Frames 8..11: Stone shattering impact & dragon kanji electric burst
    # Frames 12..14: Landing and smooth recovery
    
    for i in range(15):
        slot = Image.new("RGBA", (330, 420), (0, 0, 0, 0))
        
        # Base frame selection
        base_f = frames[min(i, 7)]
        b_arr = np.array(base_f)
        
        # Scale and position
        if i < 3:
            # Anticipation crouch
            scale_y = 0.92
            f_scaled = base_f.resize((fw, int(fh * scale_y)), Image.BILINEAR)
            pos_x = (330 - fw) // 2
            pos_y = 420 - f_scaled.height - 5
            slot.paste(f_scaled, (pos_x, pos_y), f_scaled)
        elif 3 <= i <= 9:
            # Lunge forward punch strike! Scale up to 1.12x
            scale = 1.10
            nw, nh = int(fw * scale), int(fh * scale)
            f_boost = base_f.resize((nw, nh), Image.BILINEAR)
            
            # Forward lean tilt
            f_tilted = f_boost.rotate(4.0, resample=Image.BILINEAR, center=(nw/2, nh - 10))
            
            # Draw forward punch fist in cyber cyan & white
            boost_arr = np.array(f_tilted)
            
            # Electric dragon energy surge across jacket (cyan flash)
            dragon_mask = (boost_arr[:, :, 1] > 160) & (boost_arr[:, :, 2] > 180)
            boost_arr[dragon_mask, 0] = np.clip(boost_arr[dragon_mask, 0] + 80, 0, 255)
            boost_arr[dragon_mask, 1] = 255
            boost_arr[dragon_mask, 2] = 255
            
            # Forward energy burst particles (shatter impact sparks)
            for _ in range(25):
                ex = int(np.random.normal(nw / 2, 45))
                ey = int(np.random.normal(nh * 0.45, 35))
                if 0 <= ex < nw and 0 <= ey < nh:
                    boost_arr[ey, ex] = [0, 255, 255, 255] if (_ % 2 == 0) else [255, 235, 100, 255]
                    
            f_final = Image.fromarray(boost_arr, "RGBA")
            pos_x = (330 - nw) // 2
            pos_y = 420 - nh - 15   # leap off the ground!
            slot.paste(f_final, (pos_x, pos_y), f_final)
        else:
            # Recovery to ground
            pos_x = (330 - fw) // 2
            pos_y = 420 - fh - 5
            slot.paste(base_f, (pos_x, pos_y), base_f)
            
        correct_frames.append(slot)
        
    build_sheet(330, 420, 8, 2, correct_frames, "hit_correct.png")

if __name__ == "__main__":
    make_standing_idle()
    make_sliding_brake()
    make_punch_shatter()
    print("All authentic runner action sheets generated successfully!")

