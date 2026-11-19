"""Generates the original app icon / splash artwork for IELTS Vocabulary Master.
Usage: python tools/branding/make_icons.py assets/images
Design: indigo -> teal diagonal gradient, white open book with a teal bookmark and a small spark."""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

INDIGO = (67, 56, 202)
BLUE = (79, 70, 229)
TEAL = (20, 184, 166)
WHITE = (255, 255, 255)
AMBER = (251, 191, 36)
S = 4  # supersampling


def gradient(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size)
            c = tuple(int(INDIGO[i] * (1 - t) + TEAL[i] * t) for i in range(3))
            px[x, y] = c
    return img


def draw_book(draw, cx, cy, w, color=WHITE, accent=TEAL):
    """Open book centred at (cx, cy) with total width w."""
    h = w * 0.62
    half = w / 2
    sag = w * 0.06
    # left page
    left = [(cx, cy - h / 2 + sag), (cx - half, cy - h / 2), (cx - half, cy + h / 2), (cx, cy + h / 2 + sag)]
    right = [(cx, cy - h / 2 + sag), (cx + half, cy - h / 2), (cx + half, cy + h / 2), (cx, cy + h / 2 + sag)]
    draw.polygon(left, fill=color)
    draw.polygon(right, fill=color)
    # spine gap
    gap = w * 0.018
    draw.line([(cx, cy - h / 2 + sag), (cx, cy + h / 2 + sag)], fill=(220, 224, 245), width=int(gap * 2))
    # text lines
    lw = max(2, int(w * 0.022))
    for i in range(4):
        yy = cy - h / 2 + h * (0.22 + i * 0.17)
        draw.line([(cx - half * 0.82, yy), (cx - half * 0.18, yy + sag * 0.35)], fill=(199, 204, 238), width=lw)
        if i < 3:
            draw.line([(cx + half * 0.18, yy + sag * 0.35), (cx + half * 0.82, yy)], fill=(199, 204, 238), width=lw)
    # bookmark ribbon
    bx = cx + half * 0.55
    bw = w * 0.09
    top = cy - h / 2 - w * 0.02
    draw.polygon([(bx - bw / 2, top), (bx + bw / 2, top), (bx + bw / 2, top + h * 0.42),
                  (bx, top + h * 0.34), (bx - bw / 2, top + h * 0.42)], fill=accent)


def spark(draw, cx, cy, r, color=AMBER):
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.38
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    draw.polygon(pts, fill=color)


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def full_icon(size=1024):
    big = size * S
    bg = gradient(big // 8).resize((big, big), Image.BICUBIC)
    d = ImageDraw.Draw(bg)
    draw_book(d, big / 2, big * 0.54, big * 0.62)
    spark(d, big * 0.27, big * 0.25, big * 0.07)
    img = bg.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), rounded_mask(size, int(size * 0.22)))
    return out


def foreground(size=1024):
    """Adaptive icon foreground: content inside the central 66% safe zone, transparent elsewhere."""
    big = size * S
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_book(d, big / 2, big * 0.53, big * 0.42)
    spark(d, big * 0.33, big * 0.33, big * 0.05)
    return img.resize((size, size), Image.LANCZOS)


def splash(size, content_ratio):
    """Square splash logo: rounded gradient tile scaled to content_ratio of the canvas."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tile = full_icon(int(size * content_ratio))
    off = (size - tile.size[0]) // 2
    canvas.paste(tile, (off, off), tile)
    return canvas


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    full_icon().save(os.path.join(out, "app_icon.png"))
    foreground().save(os.path.join(out, "app_icon_foreground.png"))
    splash(768, 0.62).save(os.path.join(out, "splash_logo.png"))
    # Android 12 splash: icon must fit in a 640px circle inside 960px canvas
    splash(960, 0.42).save(os.path.join(out, "splash_logo_android12.png"))
    full_icon(256).save(os.path.join(out, "logo_small.png"))
    print("icons written to", out)


if __name__ == "__main__":
    main()
