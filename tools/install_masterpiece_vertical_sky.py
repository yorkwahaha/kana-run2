"""Install the 9:16 vertical masterpiece into art/stage/sky.png and clear far_skyline overlay."""
import os
from PIL import Image

src_p = r"C:\Users\York\.gemini\antigravity\brain\ffac2da6-5838-475f-8815-ccaa0e071612\shibuya_vertical_sky_1793986461809.jpg"
im = Image.open(src_p).convert("RGB")

# Target vertical resolution: 1080 x 1920
sky_target = im.resize((1080, 1920), Image.LANCZOS)
sky_path = os.path.join("art", "stage", "sky.png")
sky_target.save(sky_path)
print(f"Saved masterpiece vertical background to sky.png: {sky_target.size}")

# Clear far_skyline to completely transparent (2160 x 420) so it doesn't create cut seams over the masterpiece
blank_skyline = Image.new("RGBA", (2160, 420), (0, 0, 0, 0))
skyline_path = os.path.join("art", "stage", "far_skyline.png")
blank_skyline.save(skyline_path)
print("Cleared far_skyline to transparent (no more cutting seams over the street!)")

