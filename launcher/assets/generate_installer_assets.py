"""
Generate installer assets for SpaceGame Launcher NSIS installer.
- icon.ico (256x256, 128, 64, 48, 32, 16)
- installerSidebar.bmp (164x314)
- installerHeader.bmp (150x57)
"""
from PIL import Image, ImageDraw, ImageFont
import math, struct, io, os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Colors
BG_DARK = (10, 14, 20)
CYAN = (0, 200, 255)
CYAN_DIM = (0, 80, 120)
CYAN_BRIGHT = (100, 220, 255)
WHITE = (220, 240, 255)
STAR_COLOR = (200, 220, 255)

def draw_stars(draw, w, h, count=60, seed=42):
    """Draw random stars on the image."""
    import random
    rng = random.Random(seed)
    for _ in range(count):
        x = rng.randint(0, w - 1)
        y = rng.randint(0, h - 1)
        brightness = rng.randint(80, 255)
        size = rng.choice([1, 1, 1, 1, 2])
        color = (brightness, brightness, min(255, brightness + 30))
        if size == 1:
            draw.point((x, y), fill=color)
        else:
            draw.ellipse([x-1, y-1, x+1, y+1], fill=color)

def draw_gradient_bg(draw, w, h):
    """Draw a dark space gradient background."""
    for y in range(h):
        t = y / h
        r = int(BG_DARK[0] * (1 - t * 0.3))
        g = int(BG_DARK[1] + t * 8)
        b = int(BG_DARK[2] + t * 15)
        draw.line([(0, y), (w, y)], fill=(r, g, b))

def draw_planet(draw, cx, cy, radius):
    """Draw a stylized planet."""
    # Planet body
    for r in range(radius, 0, -1):
        t = r / radius
        color = (int(0 + (1-t)*10), int(40 + (1-t)*80), int(80 + (1-t)*120))
        draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=color)
    # Highlight
    hr = radius // 3
    hx, hy = cx - radius // 4, cy - radius // 4
    for r in range(hr, 0, -1):
        t = r / hr
        a = int((1-t) * 60)
        color = (a, 100 + a, 150 + min(a, 105))
        draw.ellipse([hx-r, hy-r, hx+r, hy+r], fill=color)

def draw_ring(draw, cx, cy, inner_r, outer_r, color):
    """Draw a ring (like Saturn's ring) as an ellipse."""
    draw.ellipse([cx-outer_r, cy-outer_r//3, cx+outer_r, cy+outer_r//3], outline=color, width=2)

def draw_ship_icon(draw, cx, cy, size):
    """Draw a simple spaceship silhouette."""
    s = size
    # Main body (triangle pointing up)
    points = [
        (cx, cy - s),           # nose
        (cx - s*0.6, cy + s*0.7), # left
        (cx - s*0.15, cy + s*0.4),
        (cx + s*0.15, cy + s*0.4),
        (cx + s*0.6, cy + s*0.7),  # right
    ]
    draw.polygon(points, fill=CYAN_DIM, outline=CYAN)
    # Engine glow
    draw.ellipse([cx-s*0.2, cy+s*0.5, cx+s*0.2, cy+s*0.9], fill=(0, 150, 255))
    # Cockpit
    draw.ellipse([cx-s*0.12, cy-s*0.4, cx+s*0.12, cy-s*0.05], fill=CYAN_BRIGHT)

def create_icon():
    """Create a multi-size .ico file with a spaceship icon."""
    sizes = [256, 128, 64, 48, 32, 16]
    images = []
    for sz in sizes:
        img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        # Circle background
        margin = sz // 8
        draw.ellipse([margin, margin, sz-margin, sz-margin], fill=(10, 20, 35, 255), outline=CYAN + (200,), width=max(1, sz//32))
        # Ship
        draw_ship_icon(draw, sz//2, sz//2, sz//3.5)
        images.append(img)

    ico_path = os.path.join(SCRIPT_DIR, "icon.ico")
    images[0].save(ico_path, format="ICO", sizes=[(s, s) for s in sizes], append_images=images[1:])
    print(f"Created {ico_path}")

def create_sidebar():
    """Create NSIS installer sidebar bitmap (164x314)."""
    w, h = 164, 314
    img = Image.new("RGB", (w, h), BG_DARK)
    draw = ImageDraw.Draw(img)

    # Gradient background
    draw_gradient_bg(draw, w, h)

    # Stars
    draw_stars(draw, w, h, count=40, seed=123)

    # Planet at bottom
    draw_planet(draw, w//2 + 20, h - 40, 50)

    # Vertical cyan accent line on the right
    draw.line([(w-2, 0), (w-2, h)], fill=CYAN_DIM, width=2)

    # Title text area at top
    # "SPACE" in dim
    try:
        font_large = ImageFont.truetype("arial.ttf", 22)
        font_small = ImageFont.truetype("arial.ttf", 10)
    except:
        font_large = ImageFont.load_default()
        font_small = ImageFont.load_default()

    # SPACE
    draw.text((15, 30), "SPACE", fill=(0, 80, 120), font=font_large)
    # GAME in bright
    draw.text((15, 55), "GAME", fill=CYAN, font=font_large)

    # Decorative line
    draw.line([(15, 90), (w-20, 90)], fill=CYAN_DIM, width=1)

    # Small text
    draw.text((15, 100), "LAUNCHER", fill=(0, 100, 140), font=font_small)

    # Ship silhouette in middle
    draw_ship_icon(draw, w//2 - 10, h//2 - 20, 25)

    bmp_path = os.path.join(SCRIPT_DIR, "installerSidebar.bmp")
    img.save(bmp_path, format="BMP")
    print(f"Created {bmp_path}")

def create_header():
    """Create NSIS installer header bitmap (150x57)."""
    w, h = 150, 57
    img = Image.new("RGB", (w, h), BG_DARK)
    draw = ImageDraw.Draw(img)

    # Gradient
    for y in range(h):
        t = y / h
        draw.line([(0, y), (w, y)], fill=(
            int(10 + t * 5),
            int(14 + t * 10),
            int(20 + t * 20)
        ))

    # Stars
    draw_stars(draw, w, h, count=15, seed=456)

    # Small ship
    draw_ship_icon(draw, w - 30, h//2, 12)

    # Text
    try:
        font = ImageFont.truetype("arial.ttf", 14)
        font_sm = ImageFont.truetype("arial.ttf", 9)
    except:
        font = ImageFont.load_default()
        font_sm = ImageFont.load_default()

    draw.text((8, 10), "SPACEGAME", fill=CYAN, font=font)
    draw.text((8, 30), "INSTALLATION", fill=CYAN_DIM, font=font_sm)

    # Bottom accent line
    draw.line([(0, h-1), (w, h-1)], fill=CYAN_DIM, width=1)

    bmp_path = os.path.join(SCRIPT_DIR, "installerHeader.bmp")
    img.save(bmp_path, format="BMP")
    print(f"Created {bmp_path}")

def create_uninstaller_sidebar():
    """Create uninstaller sidebar (same size, red tint)."""
    w, h = 164, 314
    img = Image.new("RGB", (w, h), BG_DARK)
    draw = ImageDraw.Draw(img)

    # Gradient with slight red tint
    for y in range(h):
        t = y / h
        draw.line([(0, y), (w, y)], fill=(
            int(15 + t * 10),
            int(10 + t * 5),
            int(18 + t * 8)
        ))

    draw_stars(draw, w, h, count=30, seed=789)

    # Red accent line
    draw.line([(w-2, 0), (w-2, h)], fill=(120, 40, 40), width=2)

    try:
        font_large = ImageFont.truetype("arial.ttf", 22)
        font_small = ImageFont.truetype("arial.ttf", 10)
    except:
        font_large = ImageFont.load_default()
        font_small = ImageFont.load_default()

    draw.text((15, 30), "SPACE", fill=(80, 30, 30), font=font_large)
    draw.text((15, 55), "GAME", fill=(200, 60, 60), font=font_large)
    draw.line([(15, 90), (w-20, 90)], fill=(120, 40, 40), width=1)
    draw.text((15, 100), "DESINSTALLATION", fill=(140, 50, 50), font=font_small)

    bmp_path = os.path.join(SCRIPT_DIR, "uninstallerSidebar.bmp")
    img.save(bmp_path, format="BMP")
    print(f"Created {bmp_path}")

if __name__ == "__main__":
    create_icon()
    create_sidebar()
    create_header()
    create_uninstaller_sidebar()
    print("All assets generated!")
