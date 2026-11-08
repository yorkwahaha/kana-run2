"""Build authentic 90s Cyber Shibuya Arcade UI Suite.
High-tech dark titanium chassis, vibrant glowing neon borders, authentic arcade feel.
"""
import os
import numpy as np
from PIL import Image, ImageDraw

UI_DIR = os.path.join("art", "ui")
os.makedirs(UI_DIR, exist_ok=True)

C_BG = (12, 10, 22, 255)
C_DARK_PANEL = (18, 16, 32, 255)
C_CYAN = (0, 240, 255, 255)
C_MAGENTA = (255, 0, 140, 255)
C_AMBER = (255, 180, 30, 255)
C_RED = (255, 45, 75, 255)
C_WHITE = (245, 250, 255, 255)

def round_rect(draw, bbox, radius, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = bbox
    draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=fill, outline=outline, width=width)

# 1. ACTION & MENU BUTTONS (Dark Titanium + Glowing Neon Border + Subtle Metallic Scanlines)
def build_arcade_buttons():
    btn_configs = [
        ("btn_continue", 680, 210, C_CYAN),
        ("btn_restart", 680, 150, C_RED),
        ("btn_stage_select", 680, 150, C_AMBER),
        ("btn_start", 800, 210, C_MAGENTA),
        ("btn_retry", 460, 230, C_RED),
        ("btn_next", 460, 230, C_CYAN),
        ("btn_back", 160, 150, C_CYAN),
        ("btn_primary", 96, 106, C_CYAN),
        ("btn_secondary", 96, 106, (140, 130, 170, 255)),
        ("btn_small", 320, 80, C_CYAN),
    ]

    for prefix, bw, bh, accent in btn_configs:
        for state in ["normal", "pressed", "disabled"]:
            im = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
            d = ImageDraw.Draw(im)
            dy = 5 if state == "pressed" else 0
            
            if state == "disabled":
                bg = (14, 12, 22, 220)
                border = (45, 40, 60, 255)
                line_c = (60, 55, 75, 100)
            elif state == "pressed":
                bg = (int(accent[0] * 0.25), int(accent[1] * 0.25), int(accent[2] * 0.25), 255)
                border = C_WHITE
                line_c = accent
            else: # normal
                bg = (20, 16, 36, 255)
                border = accent
                line_c = (accent[0]//2, accent[1]//2, accent[2]//2, 120)

            # Outer chassis
            r = min(18, bh // 4)
            round_rect(d, [4, 4 + dy, bw - 5, bh - 5], radius=r, fill=bg, outline=border, width=3)
            # Inner neon rim
            if state != "disabled":
                round_rect(d, [8, 8 + dy, bw - 9, bh - 9], radius=max(2, r - 3), fill=None, outline=(border[0], border[1], border[2], 120), width=1)
                # Subtle metallic scanlines
                for sy in range(14 + dy, bh - 14, 6):
                    d.line([14, sy, bw - 15, sy], fill=(255, 255, 255, 18), width=1)
                # 4 Corner bracket accents
                c_len = 16
                d.line([10, 10 + dy, 10 + c_len, 10 + dy], fill=C_WHITE, width=2)
                d.line([10, 10 + dy, 10, 10 + dy + c_len], fill=C_WHITE, width=2)
                d.line([bw - 11, 10 + dy, bw - 11 - c_len, 10 + dy], fill=C_WHITE, width=2)
                d.line([bw - 11, 10 + dy, bw - 11, 10 + dy + c_len], fill=C_WHITE, width=2)

            im.save(os.path.join(UI_DIR, f"{prefix}_{state}.png"))
        print(f"Built arcade styled {prefix}_*.png")

# 2. SEGMENTED SPEED MODE TOGGLE (seg_mode_left_on, seg_mode_right_on)
def build_seg_mode_buttons():
    w, h = 680, 130
    for mode in ["left", "right"]:
        im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        # Outer dark pod
        round_rect(d, [4, 4, w - 5, h - 5], radius=20, fill=(16, 14, 30, 255), outline=(55, 45, 80, 255), width=3)
        
        # Center divider
        mid_x = w // 2
        d.line([mid_x, 14, mid_x, h - 15], fill=(50, 42, 75, 255), width=2)
        
        if mode == "left":
            # Left side active (Cyan neon pill)
            round_rect(d, [8, 8, mid_x - 6, h - 9], radius=16, fill=(10, 36, 60, 255), outline=C_CYAN, width=3)
            # Right side inactive
            round_rect(d, [mid_x + 6, 8, w - 9, h - 9], radius=16, fill=(20, 16, 32, 180), outline=(40, 35, 60, 255), width=1)
        else:
            # Left side inactive
            round_rect(d, [8, 8, mid_x - 6, h - 9], radius=16, fill=(20, 16, 32, 180), outline=(40, 35, 60, 255), width=1)
            # Right side active (Amber neon pill)
            round_rect(d, [mid_x + 6, 8, w - 9, h - 9], radius=16, fill=(45, 30, 12, 255), outline=C_AMBER, width=3)
            
        im.save(os.path.join(UI_DIR, f"seg_mode_{mode}_on.png"))
        print(f"Built seg_mode_{mode}_on.png")

if __name__ == "__main__":
    build_arcade_buttons()
    build_seg_mode_buttons()

