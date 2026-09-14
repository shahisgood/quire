"""Generate PWA icons and iOS splash screens. Pure geometry, no fonts needed."""
from PIL import Image, ImageDraw
import os

BG = (14, 16, 19)        # --c-base dark
INK = (232, 230, 225)    # --c-ink
ACCENT = (154, 168, 255) # --c-accent
OUT = os.path.join(os.path.dirname(__file__), '..', 'public', 'icons')
os.makedirs(OUT, exist_ok=True)

def mark(size, scale=1.0):
    """The Quire mark: three lines of text and a streaming cursor, drawn at 4x for smooth edges."""
    S = size * 4
    im = Image.new('RGBA', (S, S), BG + (255,))
    d = ImageDraw.Draw(im)
    u = S / 512 * scale
    cx, cy = S / 2, S / 2
    widths = [300, 240, 150]
    h, gap, r = 30 * u, 42 * u, 15 * u
    total_h = 3 * h + 2 * gap
    top = cy - total_h / 2
    left = cx - 150 * u
    for i, w in enumerate(widths):
        y = top + i * (h + gap)
        d.rounded_rectangle([left, y, left + w * u, y + h], radius=r, fill=INK)
    # cursor after the last line
    y = top + 2 * (h + gap)
    cx2 = left + widths[2] * u + 20 * u
    d.rounded_rectangle([cx2, y - 8 * u, cx2 + 26 * u, y + h + 8 * u], radius=6 * u, fill=ACCENT)
    return im.resize((size, size), Image.LANCZOS)

mark(192).convert('RGB').save(os.path.join(OUT, 'icon-192.png'))
mark(512).convert('RGB').save(os.path.join(OUT, 'icon-512.png'))
mark(512, 0.62).convert('RGB').save(os.path.join(OUT, 'icon-512-maskable.png'))
mark(180).convert('RGB').save(os.path.join(OUT, 'apple-touch-icon-180.png'))  # opaque, square: iOS masks it

# Splash screens: background + small centred mark
for w, h in [(1179, 2556), (1170, 2532), (1290, 2796), (1206, 2622), (1320, 2868), (1125, 2436)]:
    im = Image.new('RGB', (w, h), BG)
    m = mark(240).convert('RGB')
    im.paste(m, ((w - 240) // 2, (h - 240) // 2))
    im.save(os.path.join(OUT, f'splash-{w}x{h}.png'), optimize=True)
print('icons written to', os.path.abspath(OUT))
