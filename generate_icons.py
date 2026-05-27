#!/usr/bin/env python3
"""
Generate GlucoGlance app icons for iOS, watchOS, and the widget.

Design:
- Dark background (matches the app's dark theme)
- Circular progress-ring motif (mirrors the dashboard's hero element)
- Green→cyan gradient stroke (matches the in-app "normal glucose" colors)
- Bright endpoint dot (visual reference to the "current reading" marker)
- Tinted variant: white silhouette on transparent for iOS 18+ tinted appearance
"""

import math
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024

# Color palette — matches the in-app theme
BG_TOP    = (24, 32, 50)       # #182032 - top of background gradient
BG_BOTTOM = (10, 13, 20)       # #0A0D14 - bottom of background gradient
GREEN     = (38, 173, 95)      # #26AD5F - normal glucose color
CYAN      = (45, 174, 220)     # #2DAEDC - secondary accent
WHITE     = (245, 250, 255)

# Project paths — script is committed inside the Xcode project root.
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
IOS_ICON_DIR    = os.path.join(PROJECT_ROOT, "LibreGlucoseWatch/Assets.xcassets/AppIcon.appiconset")
WATCH_ICON_DIR  = os.path.join(PROJECT_ROOT, "LibreGlucoseWatch Watch App/Assets.xcassets/AppIcon.appiconset")
WIDGET_ICON_DIR = os.path.join(PROJECT_ROOT, "GlucoseWidget/Assets.xcassets/AppIcon.appiconset")


def lerp(a, b, t):
    return int(a + (b - a) * t)


def lerp_color(c1, c2, t):
    return (lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t))


def vertical_gradient_bg(size, top, bottom):
    """Subtle vertical gradient background."""
    img = Image.new("RGB", (size, size), bottom)
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        # ease-in-out so the middle has more even tone
        t = 0.5 - 0.5 * math.cos(math.pi * t)
        color = lerp_color(top, bottom, t)
        for x in range(size):
            px[x, y] = color
    return img


def draw_gradient_arc(img, cx, cy, radius, stroke_w, start_deg, end_deg, color_start, color_end):
    """
    Sweep small filled circles along an arc, interpolating color along the way.
    Produces a smooth gradient stroke that PIL can't do natively.
    """
    draw = ImageDraw.Draw(img, "RGBA")
    angle_range = end_deg - start_deg
    # Step ~0.2 degree for very smooth coverage at this radius
    steps = max(360, int(abs(angle_range) * 6))
    for i in range(steps + 1):
        t = i / steps
        angle = start_deg + angle_range * t
        rad = math.radians(angle)
        x = cx + radius * math.cos(rad)
        y = cy + radius * math.sin(rad)
        color = lerp_color(color_start, color_end, t)
        r = stroke_w / 2
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color + (255,))


def draw_glow(img, cx, cy, radius, color, alpha_peak=120, layers=8):
    """Soft glow around a point. Stack of low-opacity larger circles."""
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    for i in range(layers, 0, -1):
        r = radius * (1.0 + i * 0.5)
        a = int(alpha_peak * (i / layers) ** 2 * 0.35)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (a,))
    glow = glow.filter(ImageFilter.GaussianBlur(radius * 0.3))
    img.alpha_composite(glow)


def make_main_icon():
    """The default/light/dark full-color icon.

    The outline itself spells "G":
      - A C-shaped arc (open on the right) forms the outer curve
      - A horizontal bar at middle height forms the G's tongue
    """
    img = vertical_gradient_bg(SIZE, BG_TOP, BG_BOTTOM).convert("RGBA")

    cx = cy = SIZE / 2
    main_radius = SIZE * 0.34
    main_stroke = SIZE * 0.092  # ~94px — slightly thicker to read as a letterform

    # The C-arc — opens on the right side of the G.
    # Sweep CCW from upper-right (-30°) the long way around to lower-right (+30° ≡ -330°).
    # The 60° gap from -30° to +30° (through 0°) is the G's right opening.
    start_deg = -30
    end_deg = -330  # equivalent to +30°, but reached by sweeping CCW
    draw_gradient_arc(img, cx, cy, main_radius, main_stroke, start_deg, end_deg, GREEN, CYAN)

    # The horizontal tongue is also a RIGHT-pointing arrow — visual shorthand for
    # "stable glucose" trend (matches the app's TrendArrow.stable = "arrow.right").
    # The icon now means both "G for Glucose" AND "stable trend" in a single glyph.
    draw_right_arrow(img, cx, cy, main_radius, main_stroke, CYAN)

    return img.convert("RGB")


def draw_right_arrow(img, cx, cy, main_radius, main_stroke, color):
    """
    Draw a horizontal arrow pointing right — shaft + chevron tip, all rounded.
    Modeled on SF Symbol "arrow.right" style: thin chevron, not a filled wedge.
    The arrow occupies the same horizontal slot as the G's tongue.
    """
    d = ImageDraw.Draw(img, "RGBA")
    half = main_stroke / 2
    fill = color + (255,)

    arrow_y = cy
    # Shaft extends from past-center (left) up to where the ring's right edge would be.
    # Stop the shaft slightly before the chevron so the join is clean.
    shaft_left_x = cx - main_stroke * 0.4
    chevron_back_dist = main_stroke * 1.25
    chevron_height = main_stroke * 1.0
    arrow_tip_x = cx + main_radius * 0.866    # aligns with C's right edge (cos 30°)
    shaft_right_x = arrow_tip_x - chevron_back_dist + half * 0.3

    # Shaft body + rounded caps
    d.rectangle([shaft_left_x, arrow_y - half, shaft_right_x, arrow_y + half], fill=fill)
    d.ellipse([shaft_left_x - half, arrow_y - half, shaft_left_x + half, arrow_y + half], fill=fill)
    d.ellipse([shaft_right_x - half, arrow_y - half, shaft_right_x + half, arrow_y + half], fill=fill)

    # Chevron: two thick diagonal lines meeting at the tip.
    tip = (arrow_tip_x, arrow_y)
    upper_back = (arrow_tip_x - chevron_back_dist, arrow_y - chevron_height)
    lower_back = (arrow_tip_x - chevron_back_dist, arrow_y + chevron_height)

    d.line([upper_back, tip], fill=fill, width=int(main_stroke))
    d.line([lower_back, tip], fill=fill, width=int(main_stroke))
    # Rounded caps at each chevron endpoint (back + tip)
    for (x, y) in (upper_back, lower_back, tip):
        d.ellipse([x - half, y - half, x + half, y + half], fill=fill)


# ----- typography helpers -----

# Fonts to try in order. SFNSRounded matches SwiftUI's design:.rounded.
_FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNSRounded.ttf",
    "/System/Library/Fonts/SFCompactRounded.ttf",
    "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
    "/System/Library/Fonts/SFNS.ttf",
]


def load_bold_font(px):
    """Load a heavy/bold rounded font at the requested pixel size, with fallbacks."""
    from PIL import ImageFont
    for path in _FONT_CANDIDATES:
        if not os.path.exists(path):
            continue
        try:
            font = ImageFont.truetype(path, px)
            # Variable fonts (SFNSRounded) — pick the heaviest weight available
            for axis in ("Black", "Heavy", "Bold"):
                try:
                    font.set_variation_by_name(axis)
                    break
                except (OSError, AttributeError, ValueError):
                    continue
            return font
        except OSError:
            continue
    return ImageFont.load_default()


def draw_centered_letter(img, letter, cx, cy, font_px, fill):
    """Draw a single letter precisely centered on (cx, cy)."""
    d = ImageDraw.Draw(img, "RGBA")
    font = load_bold_font(font_px)
    # textbbox gives us the actual rendered glyph bounds so we can center properly
    bbox = d.textbbox((0, 0), letter, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = cx - text_w / 2 - bbox[0]
    y = cy - text_h / 2 - bbox[1]
    d.text((x, y), letter, font=font, fill=fill)


def make_tinted_icon():
    """
    Tinted variant for iOS 18+: white silhouette on transparent.
    iOS recolors this based on the user's tint setting.
    """
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    cx = cy = SIZE / 2

    main_radius = SIZE * 0.34
    main_stroke = SIZE * 0.092

    # C-arc, same geometry as main icon
    bbox = [cx - main_radius, cy - main_radius, cx + main_radius, cy + main_radius]
    # PIL's draw.arc uses clockwise angles. To draw the long-way CCW from -30° to +30°,
    # we draw clockwise from +30° to -30° (going through 90, 180, 270 → 330 ≡ -30).
    d.arc(bbox, 30, 330, fill=(255, 255, 255, 255), width=int(main_stroke))

    # Right-pointing arrow (the G's tongue + stable-trend symbol)
    draw_right_arrow(img, cx, cy, main_radius, main_stroke, (255, 255, 255))
    return img


def save_png(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG", optimize=True)
    print(f"  wrote {os.path.relpath(path, os.path.dirname(os.path.abspath(__file__)))}")


def main():
    print("Generating GlucoGlance app icons...")
    main_icon = make_main_icon()
    tinted_icon = make_tinted_icon()

    # iOS — three variants
    save_png(main_icon, os.path.join(IOS_ICON_DIR, "AppIcon.png"))
    save_png(main_icon, os.path.join(IOS_ICON_DIR, "AppIcon-Dark.png"))
    save_png(tinted_icon, os.path.join(IOS_ICON_DIR, "AppIcon-Tinted.png"))

    # Watch — single icon
    save_png(main_icon, os.path.join(WATCH_ICON_DIR, "AppIcon.png"))

    # Widget — single icon (used during install on watch)
    save_png(main_icon, os.path.join(WIDGET_ICON_DIR, "AppIcon.png"))

    print("Done.")


if __name__ == "__main__":
    main()
