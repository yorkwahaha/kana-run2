"""Process 90s Cyber Shibuya pixel art assets into res://art/ format."""
import os, sys
from PIL import Image, ImageOps, ImageFilter
import numpy as np

BRAIN_DIR = r"C:\Users\York\.gemini\antigravity\brain\ffac2da6-5838-475f-8815-ccaa0e071612"
ART_DIR = "art"

def make_seamless_y(im):
    """Make an image seamlessly tileable vertically by blend-wrapping top and bottom 20%."""
    w, h = im.size
    arr = np.array(im, dtype=np.float32)
    blend_h = int(h * 0.2)
    for y in range(blend_h):
        t = y / float(blend_h)
        # smoothstep
        t = t * t * (3 - 2 * t)
        blended = (1.0 - t) * arr[h - blend_h + y] + t * arr[y]
        arr[y] = blended
        arr[h - blend_h + y] = blended
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))

def process_track():
    src = os.path.join(BRAIN_DIR, "track_cyber_asphalt_1793980651124.jpg")
    im = Image.open(src).convert("RGB")
    im = im.resize((512, 512), Image.LANCZOS)
    im = make_seamless_y(im)
    out_path = os.path.join(ART_DIR, "stage", "track_tile.png")
    im.save(out_path)
    print("Saved track_tile.png:", im.size)

def process_sidewalk():
    src = os.path.join(BRAIN_DIR, "sidewalk_cyber_tile_1793980670292.jpg")
    im = Image.open(src).convert("RGBA")
    im = im.resize((512, 512), Image.LANCZOS)
    im = make_seamless_y(im)
    out_path = os.path.join(ART_DIR, "stage", "sidewalk_tile.png")
    im.save(out_path)
    print("Saved sidewalk_tile.png:", im.size)

def process_tablet():
    src = os.path.join(BRAIN_DIR, "tablet_cyber_glass_1793980645369.jpg")
    im = Image.open(src).convert("RGB")
    # center crop 80% to get the monolith
    w, h = im.size
    crop_box = (int(w * 0.15), int(h * 0.1), int(w * 0.85), int(h * 0.9))
    im = im.crop(crop_box)
    im = im.resize((256, 288), Image.LANCZOS)
    
    # remove dark background: convert to RGBA
    arr = np.array(im, dtype=np.float32)
    # background is dark purple (around 18, 16, 30)
    brightness = np.maximum(arr[:, :, 0], np.maximum(arr[:, :, 1], arr[:, :, 2]))
    alpha = np.clip((brightness - 25.0) * (255.0 / 40.0), 0, 255)
    
    # Glass center should be semi-transparent neon (alpha around 180..220)
    rgba = np.zeros((288, 256, 4), dtype=np.uint8)
    rgba[:, :, :3] = np.clip(arr, 0, 255).astype(np.uint8)
    rgba[:, :, 3] = alpha.astype(np.uint8)
    
    out_im = Image.fromarray(rgba, "RGBA")
    out_path = os.path.join(ART_DIR, "tablet", "tablet_normal.png")
    out_im.save(out_path)
    print("Saved tablet_normal.png:", out_im.size)

def process_shatter():
    src = os.path.join(BRAIN_DIR, "tablet_glass_shatter_strip_1793980698099.jpg")
    im = Image.open(src).convert("RGB")
    w, h = im.size
    
    # 8 frames strip: target 1536 x 192 (8 frames of 192x192)
    target_fw = 192
    target_fh = 192
    strip = Image.new("RGBA", (target_fw * 8, target_fh), (0, 0, 0, 0))
    
    frame_w = w / 8.0
    for i in range(8):
        box = (int(i * frame_w), 0, int((i + 1) * frame_w), h)
        frame = im.crop(box).resize((target_fw, target_fh), Image.LANCZOS)
        f_arr = np.array(frame, dtype=np.float32)
        
        # Black background removal: alpha based on max RGB brightness
        brightness = np.maximum(f_arr[:, :, 0], np.maximum(f_arr[:, :, 1], f_arr[:, :, 2]))
        alpha = np.clip(brightness * 2.5, 0, 255)
        
        f_rgba = np.zeros((target_fh, target_fw, 4), dtype=np.uint8)
        f_rgba[:, :, :3] = np.clip(f_arr, 0, 255).astype(np.uint8)
        f_rgba[:, :, 3] = alpha.astype(np.uint8)
        
        strip.paste(Image.fromarray(f_rgba, "RGBA"), (i * target_fw, 0))
        
    out_path = os.path.join(ART_DIR, "tablet", "tablet_shatter.png")
    strip.save(out_path)
    print("Saved tablet_shatter.png:", strip.size)

def process_sky_and_skyline():
    src = os.path.join(BRAIN_DIR, "concept_B_shibuya.jpg")
    im = Image.open(src).convert("RGB")
    w, h = im.size
    
    # 1. Sky: top half of concept_B (smooth purple-cyan gradient night sky)
    sky_crop = im.crop((0, 0, w, int(h * 0.45)))
    sky_im = sky_crop.resize((1080, 1200), Image.LANCZOS)
    sky_im.save(os.path.join(ART_DIR, "stage", "sky.png"))
    print("Saved sky.png:", sky_im.size)
    
    # 2. Skyline: mid-section with neon skyscrapers and signs
    skyline_crop = im.crop((0, int(h * 0.15), w, int(h * 0.55)))
    # Resize to 2160 x 420
    skyline_im = skyline_crop.resize((2160, 420), Image.LANCZOS).convert("RGBA")
    
    # Make dark upper sky transparent in the skyline
    arr = np.array(skyline_im, dtype=np.float32)
    # Upper region sky transparency fade
    for y in range(int(420 * 0.4)):
        t = y / float(420 * 0.4)
        arr[y, :, 3] = np.clip(arr[y, :, 3] * t, 0, 255)
        
    skyline_out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    skyline_out.save(os.path.join(ART_DIR, "stage", "far_skyline.png"))
    print("Saved far_skyline.png:", skyline_out.size)

def make_pixel_shadow():
    # 128x64 pixel contact shadow with crisp stepped edges
    w, h = 128, 64
    arr = np.zeros((h, w, 4), dtype=np.uint8)
    cx, cy = w / 2.0, h / 2.0
    rx, ry = w * 0.45, h * 0.45
    
    # Cyber ambient purple shadow (35, 15, 60)
    for y in range(h):
        for x in range(w):
            dx = (x - cx) / rx
            dy = (y - cy) / ry
            d = dx * dx + dy * dy
            if d <= 1.0:
                # Stepped pixel alpha (3 color levels: 140, 90, 40)
                if d < 0.4:
                    a = 150
                elif d < 0.75:
                    a = 100
                else:
                    a = 50
                arr[y, x] = [35, 15, 60, a]
                
    im = Image.fromarray(arr, "RGBA")
    os.makedirs(os.path.join(ART_DIR, "runner"), exist_ok=True)
    out_path = os.path.join(ART_DIR, "runner", "pixel_shadow.png")
    im.save(out_path)
    print("Saved pixel_shadow.png:", im.size)

if __name__ == "__main__":
    process_track()
    process_sidewalk()
    process_tablet()
    process_shatter()
    process_sky_and_skyline()
    make_pixel_shadow()
    print("All 90s cyber assets processed successfully!")

