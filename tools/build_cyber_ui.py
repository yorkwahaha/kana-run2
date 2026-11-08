"""Craft the complete 90s Arcade Cyber Shibuya UI Suite (all 48+ UI assets).
Unified aesthetic: Midnight graphite chassis, electric neon cyan, arcade magenta, amber accents.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

UI_DIR = os.path.join("art", "ui")
os.makedirs(UI_DIR, exist_ok=True)

# Common Palette
C_DARK_BG = (13, 12, 24, 255)
C_DARK_PANEL = (20, 18, 36, 255)
C_DARK_BORDER = (45, 40, 72, 255)
C_CYAN = (0, 240, 255, 255)
C_CYAN_DIM = (0, 160, 180, 255)
C_MAGENTA = (255, 0, 140, 255)
C_MAGENTA_DIM = (180, 0, 95, 255)
C_AMBER = (255, 180, 30, 255)
C_GREEN = (0, 255, 140, 255)
C_WHITE = (240, 245, 255, 255)
C_GRAY_TEXT = (140, 145, 175, 255)

def round_rect(draw, bbox, radius, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = bbox
    draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=fill, outline=outline, width=width)

# ==========================================
# 1. MENU BACKGROUNDS (select_bg, result_bg)
# ==========================================
def build_menu_backgrounds():
    w, h = 646, 1400
    for name, accent in [("select_bg.png", C_CYAN), ("result_bg.png", C_MAGENTA)]:
        im = Image.new("RGBA", (w, h), (10, 9, 20, 255))
        draw = ImageDraw.Draw(im)
        
        # Subtle vertical dark gradient
        for y in range(h):
            t = y / float(h)
            r = int(10 * (1 - t) + 18 * t)
            g = int(9 * (1 - t) + 14 * t)
            b = int(20 * (1 - t) + 36 * t)
            draw.line([0, y, w, y], fill=(r, g, b, 255))
        
        # Cyber grid pattern in background
        for y in range(0, h, 32):
            draw.line([0, y, w, y], fill=(accent[0]//6, accent[1]//6, accent[2]//6, 40))
        for x in range(0, w, 32):
            draw.line([x, 0, x, h], fill=(accent[0]//6, accent[1]//6, accent[2]//6, 40))
        
        # Outer arcade chassis beveled borders
        draw.rectangle([0, 0, w-1, h-1], outline=(30, 26, 50, 255), width=8)
        draw.rectangle([8, 8, w-9, h-9], outline=(accent[0]//3, accent[1]//3, accent[2]//3, 160), width=2)
        
        # Corner brackets
        corner_len = 40
        for cx, cy, sx, sy in [(12, 12, 1, 1), (w-13, 12, -1, 1), (12, h-13, 1, -1), (w-13, h-13, -1, -1)]:
            draw.line([cx, cy, cx + corner_len * sx, cy], fill=accent, width=3)
            draw.line([cx, cy, cx, cy + corner_len * sy], fill=accent, width=3)
            draw.point([cx + 6 * sx, cy + 6 * sy], fill=C_WHITE)
            
        # Top banner frame
        draw.rectangle([24, 24, w-25, 110], fill=(16, 14, 30, 230), outline=(50, 45, 80, 255), width=2)
        draw.line([26, 108, w-27, 108], fill=accent, width=2)
        
        # Save as RGB as originally formatted
        im.convert("RGB").save(os.path.join(UI_DIR, name))
        print(f"Saved {name}")

# ==========================================
# 2. CORE HUD PANELS
# ==========================================
def build_hud_panels():
    # panel_9slice.png (128x128)
    im_9 = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d_9 = ImageDraw.Draw(im_9)
    round_rect(d_9, [4, 4, 123, 123], radius=14, fill=C_DARK_PANEL, outline=(0, 220, 255, 240), width=3)
    round_rect(d_9, [8, 8, 119, 119], radius=10, fill=None, outline=(30, 45, 75, 180), width=1)
    # 4 corner rivets
    for rx, ry in [(14, 14), (113, 14), (14, 113), (113, 113)]:
        d_9.ellipse([rx-3, ry-3, rx+3, ry+3], fill=(80, 90, 120, 255), outline=C_CYAN)
    im_9.save(os.path.join(UI_DIR, "panel_9slice.png"))
    print("Saved panel_9slice.png")

    # speedo_panel.png (240x130)
    im_sp = Image.new("RGBA", (240, 130), (0, 0, 0, 0))
    dsp = ImageDraw.Draw(im_sp)
    round_rect(dsp, [4, 4, 235, 125], radius=16, fill=(16, 14, 32, 240), outline=(60, 50, 90, 255), width=2)
    round_rect(dsp, [6, 6, 233, 123], radius=14, fill=None, outline=C_CYAN_DIM, width=1)
    # Speed dial arc (semi-circle on left)
    dsp.arc([24, 20, 114, 110], start=140, end=40, fill=(0, 240, 255, 255), width=6)
    dsp.arc([24, 20, 114, 110], start=0, end=40, fill=(255, 0, 140, 255), width=6)
    # Tick marks
    for angle in np.linspace(140, 400, 7):
        rad = np.radians(angle)
        x0 = 69 + int(36 * np.cos(rad))
        y0 = 65 + int(36 * np.sin(rad))
        x1 = 69 + int(44 * np.cos(rad))
        y1 = 65 + int(44 * np.sin(rad))
        dsp.line([x0, y0, x1, y1], fill=C_WHITE, width=2)
    im_sp.save(os.path.join(UI_DIR, "speedo_panel.png"))
    print("Saved speedo_panel.png")

    # speedo_needle.png (12x44)
    im_sn = Image.new("RGBA", (12, 44), (0, 0, 0, 0))
    dsn = ImageDraw.Draw(im_sn)
    dsn.polygon([(6, 2), (10, 36), (6, 42), (2, 36)], fill=(255, 0, 140, 255), outline=C_WHITE)
    dsn.ellipse([4, 34, 8, 38], fill=C_WHITE)
    im_sn.save(os.path.join(UI_DIR, "speedo_needle.png"))
    print("Saved speedo_needle.png")

    # timer_panel.png (260x110)
    im_tp = Image.new("RGBA", (260, 110), (0, 0, 0, 0))
    dtp = ImageDraw.Draw(im_tp)
    round_rect(dtp, [4, 4, 255, 105], radius=16, fill=(16, 14, 32, 240), outline=(60, 50, 90, 255), width=2)
    round_rect(dtp, [6, 6, 253, 103], radius=14, fill=None, outline=C_CYAN_DIM, width=1)
    # Clock icon box
    round_rect(dtp, [18, 22, 68, 88], radius=8, fill=(25, 20, 45, 255), outline=C_CYAN, width=2)
    dtp.ellipse([28, 38, 58, 72], fill=None, outline=C_WHITE, width=2)
    dtp.line([43, 46, 43, 55], fill=C_CYAN, width=2)
    dtp.line([43, 55, 52, 55], fill=C_CYAN, width=2)
    im_tp.save(os.path.join(UI_DIR, "timer_panel.png"))
    print("Saved timer_panel.png")

    # hp_frame.png (500x110), hp_fill.png (376x48), hp_lag.png (376x48)
    im_hf = Image.new("RGBA", (500, 110), (0, 0, 0, 0))
    dhf = ImageDraw.Draw(im_hf)
    round_rect(dhf, [4, 6, 495, 103], radius=18, fill=(16, 14, 32, 240), outline=(60, 50, 90, 255), width=3)
    round_rect(dhf, [8, 10, 491, 99], radius=14, fill=None, outline=C_CYAN_DIM, width=1)
    # Heart icon frame on left
    round_rect(dhf, [20, 20, 85, 89], radius=12, fill=(25, 20, 45, 255), outline=C_MAGENTA, width=2)
    im_hf.save(os.path.join(UI_DIR, "hp_frame.png"))
    print("Saved hp_frame.png")

    # hp_fill (376x48): Emerald cyan energy bar with high-tech angle cuts
    im_hfill = Image.new("RGBA", (376, 48), (0, 0, 0, 0))
    dhfill = ImageDraw.Draw(im_hfill)
    round_rect(dhfill, [2, 2, 373, 45], radius=8, fill=(0, 230, 160, 255), outline=C_WHITE, width=2)
    for sx in range(12, 360, 16):
        dhfill.line([sx, 6, sx + 6, 41], fill=(255, 255, 255, 90), width=3)
    im_hfill.save(os.path.join(UI_DIR, "hp_fill.png"))
    print("Saved hp_fill.png")

    # hp_lag (376x48): Crimson damage indicator
    im_hlag = Image.new("RGBA", (376, 48), (0, 0, 0, 0))
    dhlag = ImageDraw.Draw(im_hlag)
    round_rect(dhlag, [2, 2, 373, 45], radius=8, fill=(255, 30, 80, 255), outline=C_WHITE, width=2)
    im_hlag.save(os.path.join(UI_DIR, "hp_lag.png"))
    print("Saved hp_lag.png")

    # shield_counter_panel.png (380x90), shield_pip_full.png (48x48), shield_pip_empty.png (48x48)
    im_scp = Image.new("RGBA", (380, 90), (0, 0, 0, 0))
    dscp = ImageDraw.Draw(im_scp)
    round_rect(dscp, [4, 4, 375, 85], radius=16, fill=(18, 15, 30, 240), outline=C_AMBER, width=2)
    im_scp.save(os.path.join(UI_DIR, "shield_counter_panel.png"))
    print("Saved shield_counter_panel.png")

    im_spf = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    dspf = ImageDraw.Draw(im_spf)
    dspf.polygon([(24, 4), (43, 14), (43, 34), (24, 44), (5, 34), (5, 14)], fill=C_AMBER, outline=C_WHITE)
    dspf.ellipse([18, 18, 30, 30], fill=C_WHITE)
    im_spf.save(os.path.join(UI_DIR, "shield_pip_full.png"))
    print("Saved shield_pip_full.png")

    im_spe = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    dspe = ImageDraw.Draw(im_spe)
    dspe.polygon([(24, 4), (43, 14), (43, 34), (24, 44), (5, 34), (5, 14)], fill=(35, 28, 45, 255), outline=(100, 80, 110, 255))
    im_spe.save(os.path.join(UI_DIR, "shield_pip_empty.png"))
    print("Saved shield_pip_empty.png")

# ==========================================
# 3. CONTROL BUTTONS (ACCEL, BRAKE, LOCK, PAUSE)
# ==========================================
def build_gameplay_buttons():
    # btn_accel_normal / pressed (320x250) - Magenta arcade trigger
    for state in ["normal", "pressed"]:
        im = Image.new("RGBA", (320, 250), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        dy = 8 if state == "pressed" else 0
        fill_col = (200, 0, 100, 255) if state == "pressed" else (255, 0, 140, 255)
        # Outer chassis base
        round_rect(d, [6, 8, 313, 241], radius=24, fill=(18, 12, 28, 255), outline=(50, 35, 75, 255), width=3)
        # Push block
        round_rect(d, [14, 14 + dy, 305, 233], radius=20, fill=fill_col, outline=C_WHITE, width=3)
        # High-tech chevron arrows
        for ay in [80 + dy, 120 + dy, 160 + dy]:
            d.polygon([(160, ay - 24), (210, ay + 12), (185, ay + 12), (160, ay - 6), (135, ay + 12), (110, ay + 12)], fill=C_WHITE)
        im.save(os.path.join(UI_DIR, f"btn_accel_{state}.png"))
        print(f"Saved btn_accel_{state}.png")

    # btn_brake_normal / pressed (320x250) - Industrial Cyan/Steel Blue pedal
    for state in ["normal", "pressed"]:
        im = Image.new("RGBA", (320, 250), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        dy = 8 if state == "pressed" else 0
        fill_col = (0, 140, 180, 255) if state == "pressed" else (0, 200, 240, 255)
        round_rect(d, [6, 8, 313, 241], radius=24, fill=(12, 18, 28, 255), outline=(35, 50, 75, 255), width=3)
        round_rect(d, [14, 14 + dy, 305, 233], radius=20, fill=fill_col, outline=C_WHITE, width=3)
        # Industrial tread / stop block
        round_rect(d, [110, 80 + dy, 210, 165 + dy], radius=12, fill=(10, 30, 50, 255), outline=C_WHITE, width=3)
        d.rectangle([135, 105 + dy, 185, 140 + dy], fill=C_WHITE)
        im.save(os.path.join(UI_DIR, f"btn_brake_{state}.png"))
        print(f"Saved btn_brake_{state}.png")

    # btn_lock_off / on / pressed (160x130)
    for state in ["off", "on", "pressed"]:
        im = Image.new("RGBA", (160, 130), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        dy = 4 if state == "pressed" else 0
        bg_col = (18, 14, 30, 255) if state == "off" else (35, 25, 10, 255)
        accent = (80, 75, 110, 255) if state == "off" else C_AMBER
        round_rect(d, [4, 4 + dy, 155, 125], radius=16, fill=bg_col, outline=accent, width=3)
        # Lock icon
        d.arc([60, 35 + dy, 100, 75 + dy], start=180, end=0, fill=accent, width=4)
        round_rect(d, [52, 60 + dy, 108, 95 + dy], radius=6, fill=accent, outline=C_WHITE, width=2)
        im.save(os.path.join(UI_DIR, f"btn_lock_{state}.png"))
        print(f"Saved btn_lock_{state}.png")

    # btn_pause_normal / pressed (148x158)
    for state in ["normal", "pressed"]:
        im = Image.new("RGBA", (148, 158), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        dy = 4 if state == "pressed" else 0
        round_rect(d, [4, 4 + dy, 143, 153], radius=16, fill=(20, 16, 36, 255), outline=C_CYAN, width=3)
        # Pause bars
        d.rectangle([46, 42 + dy, 62, 114 + dy], fill=C_WHITE)
        d.rectangle([86, 42 + dy, 102, 114 + dy], fill=C_WHITE)
        im.save(os.path.join(UI_DIR, f"btn_pause_{state}.png"))
        print(f"Saved btn_pause_{state}.png")

# ==========================================
# 4. ACTION & MENU BUTTONS
# ==========================================
def build_action_buttons():
    btn_defs = [
        ("btn_start", 800, 210, C_MAGENTA),
        ("btn_continue", 680, 210, C_CYAN),
        ("btn_restart", 680, 150, (255, 70, 70, 255)),
        ("btn_stage_select", 680, 150, C_AMBER),
        ("btn_retry", 460, 230, (255, 70, 70, 255)),
        ("btn_next", 460, 230, C_CYAN),
        ("btn_back", 160, 150, (140, 130, 170, 255)),
        ("btn_primary", 96, 106, C_CYAN),
        ("btn_secondary", 96, 106, (140, 130, 170, 255)),
        ("btn_small", 320, 80, C_CYAN),
    ]
    for prefix, bw, bh, col in btn_defs:
        for state in ["normal", "pressed", "disabled"]:
            im = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
            d = ImageDraw.Draw(im)
            dy = 4 if state == "pressed" else 0
            
            if state == "disabled":
                bg = (18, 16, 28, 200)
                border = (50, 45, 65, 255)
            elif state == "pressed":
                bg = (col[0]//2, col[1]//2, col[2]//2, 255)
                border = C_WHITE
            else:
                bg = (col[0], col[1], col[2], 255)
                border = C_WHITE
                
            round_rect(d, [4, 4 + dy, bw - 5, bh - 5], radius=min(18, bh // 4), fill=bg, outline=border, width=3)
            # Subtle inner highlight line
            if state != "disabled":
                d.line([16, 12 + dy, bw - 17, 12 + dy], fill=(255, 255, 255, 120), width=2)
            im.save(os.path.join(UI_DIR, f"{prefix}_{state}.png"))
        print(f"Saved {prefix}_*.png")

# ==========================================
# 5. STAGE ROWS & ZONE HEADERS & TABS
# ==========================================
def build_stage_and_tabs():
    # Stage rows (960x180): normal, cleared, boss, locked, selected
    row_styles = {
        "stage_row_normal": ((20, 18, 38, 255), (60, 50, 90, 255), C_CYAN),
        "stage_row_cleared": ((15, 28, 35, 255), (0, 180, 140, 255), C_GREEN),
        "stage_row_boss": ((38, 15, 25, 255), (255, 0, 90, 255), C_MAGENTA),
        "stage_row_locked": ((14, 12, 22, 220), (35, 30, 50, 255), (80, 75, 95, 255)),
        "stage_row_selected": ((30, 24, 55, 255), (0, 240, 255, 255), C_WHITE),
    }
    for name, (bg, border, accent) in row_styles.items():
        im = Image.new("RGBA", (960, 180), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        round_rect(d, [6, 6, 953, 173], radius=18, fill=bg, outline=border, width=3)
        # Left accent banner
        round_rect(d, [12, 12, 34, 167], radius=6, fill=accent)
        # Boss hazard stripes
        if "boss" in name:
            for hx in range(40, 940, 40):
                d.polygon([(hx, 12), (hx + 18, 12), (hx - 8, 38), (hx - 26, 38)], fill=(255, 0, 90, 180))
        im.save(os.path.join(UI_DIR, f"{name}.png"))
        print(f"Saved {name}.png")

    # Zone headers (960x130): 1 to 5 + final
    zone_accents = [C_CYAN, C_GREEN, C_AMBER, C_MAGENTA, (180, 70, 255, 255), (255, 30, 60, 255)]
    for i in range(1, 7):
        zname = f"zone_header_{i}.png" if i <= 5 else "zone_header_final.png"
        accent = zone_accents[i-1]
        im = Image.new("RGBA", (960, 130), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        round_rect(d, [4, 4, 955, 125], radius=16, fill=(15, 12, 28, 255), outline=accent, width=3)
        # Cyber bar on top & bottom
        d.line([16, 12, 943, 12], fill=accent, width=2)
        d.line([16, 117, 943, 117], fill=accent, width=2)
        im.save(os.path.join(UI_DIR, zname))
        print(f"Saved {zname}")

    # Tabs (470x110): tab_active, tab_inactive, tab_locked
    for state in ["active", "inactive", "locked"]:
        im = Image.new("RGBA", (470, 110), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        if state == "active":
            bg, border = (28, 20, 50, 255), C_CYAN
        elif state == "inactive":
            bg, border = (16, 14, 28, 240), (60, 50, 80, 255)
        else:
            bg, border = (12, 10, 20, 200), (35, 30, 48, 255)
        round_rect(d, [4, 4, 465, 105], radius=14, fill=bg, outline=border, width=3)
        if state == "active":
            d.line([16, 102, 453, 102], fill=C_CYAN, width=3)
        im.save(os.path.join(UI_DIR, f"tab_{state}.png"))
        print(f"Saved tab_{state}.png")

# ==========================================
# 6. BADGES, JUDGEMENTS, ICONS
# ==========================================
def build_badges_and_icons():
    # combo_badge.png (260x90)
    im_cb = Image.new("RGBA", (260, 90), (0, 0, 0, 0))
    dcb = ImageDraw.Draw(im_cb)
    round_rect(dcb, [4, 4, 255, 85], radius=16, fill=(35, 20, 10, 255), outline=C_AMBER, width=3)
    dcb.line([12, 10, 247, 10], fill=C_WHITE, width=2)
    im_cb.save(os.path.join(UI_DIR, "combo_badge.png"))
    print("Saved combo_badge.png")

    # badge_new_record.png (180x70)
    im_nr = Image.new("RGBA", (180, 70), (0, 0, 0, 0))
    dnr = ImageDraw.Draw(im_nr)
    round_rect(dnr, [4, 4, 175, 65], radius=14, fill=(45, 0, 25, 255), outline=C_MAGENTA, width=3)
    im_nr.save(os.path.join(UI_DIR, "badge_new_record.png"))
    print("Saved badge_new_record.png")

    # judge_ok (256x256), judge_ng (256x256)
    im_ok = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    dok = ImageDraw.Draw(im_ok)
    dok.ellipse([10, 10, 245, 245], fill=(0, 40, 50, 200), outline=C_CYAN, width=8)
    dok.ellipse([30, 30, 225, 225], fill=None, outline=C_WHITE, width=3)
    im_ok.save(os.path.join(UI_DIR, "judge_ok.png"))
    print("Saved judge_ok.png")

    im_ng = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    dng = ImageDraw.Draw(im_ng)
    dng.ellipse([10, 10, 245, 245], fill=(60, 0, 20, 200), outline=(255, 30, 60, 255), width=8)
    dng.line([60, 60, 196, 196], fill=C_WHITE, width=12)
    dng.line([196, 60, 60, 196], fill=C_WHITE, width=12)
    im_ng.save(os.path.join(UI_DIR, "judge_ng.png"))
    print("Saved judge_ng.png")

if __name__ == "__main__":
    print("=== STARTING 90S ARCADE CYBER UI OVERHAUL ===")
    build_menu_backgrounds()
    build_hud_panels()
    build_gameplay_buttons()
    build_action_buttons()
    build_stage_and_tabs()
    build_badges_and_icons()
    print("=== ALL UI SUITE ASSETS REBUILT SUCCESSFULLY ===")

