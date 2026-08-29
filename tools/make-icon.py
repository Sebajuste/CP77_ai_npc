# -*- coding: utf-8 -*-
"""Draws the AGENT LINK app icon and the AI NPC Nexus image.

Two different names on purpose. AGENT LINK is what the app is called in Night City -- it is
what the player reads under the icon of a terminal. AI NPC is what the mod is called on
Nexus, where the reader is a modder choosing a download. The two never meet.

The plate, the palette and the 4x supersampling are the same as NightCityAgenda's icon, so
the two apps read as siblings if they end up in the same browser's site list.
"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "branding")
S = 4
U = 1024

YELLOW = (252, 238, 10)
CYAN   = (0, 240, 255)
RED    = (255, 50, 60)
INK    = (10, 12, 15)
PLATE  = (16, 19, 24)

def px(v):
    return int(round(v * S))

def chamfer(x0, y0, x1, y1, c):
    return [(x0 + c, y0), (x1, y0), (x1, y1 - c), (x1 - c, y1), (x0, y1), (x0, y0 + c)]

def scaled(pts):
    return [(px(x), px(y)) for x, y in pts]

def draw_logo(d, mono=None):
    """AGENT LINK: the Agent, and what it is linked to. mono=colour -> flat silhouette."""
    def col(c):
        return mono if mono else c

    if not mono:
        d.polygon(scaled(chamfer(40, 40, 984, 984, 150)), fill=PLATE)
        d.polygon(scaled(chamfer(40, 40, 984, 984, 150)), outline=YELLOW, width=px(10))

    # --- the Agent: a handset, chamfered like everything else in this city ------
    body = chamfer(196, 176, 604, 856, 72)
    if not mono:
        d.polygon(scaled(body), fill=INK)
    d.polygon(scaled(body), outline=col(YELLOW), width=px(24))

    # speaker slot
    d.rectangle([px(340), px(232), px(460), px(252)], fill=col(YELLOW))

    # --- the conversation on it: two bubbles, one each way ---------------------
    d.rectangle([px(248), px(330), px(470), px(430)], fill=col(YELLOW))
    d.rectangle([px(330), px(470), px(552), px(570)], fill=col(CYAN))
    d.rectangle([px(248), px(610), px(422), px(710)], fill=col(YELLOW))

    # --- the link: what the desk hears ----------------------------------------
    cx, cy = 604, 516
    for r, w in ((150, 22), (250, 22), (350, 22)):
        d.arc([px(cx - r), px(cy - r), px(cx + r), px(cy + r)],
              start=-52, end=52, fill=col(CYAN), width=px(w))

    # --- one unread ------------------------------------------------------------
    # On the handset's corner, where a badge goes, and not out in the arcs: at 128 px the
    # arcs are three thin strokes and a dot among them reads as a fourth.
    if not mono:
        d.ellipse([px(536), px(108), px(672), px(244)], fill=INK)
    d.ellipse([px(552), px(124), px(656), px(228)], fill=col(RED))

def render(size, mono=None):
    img = Image.new("RGBA", (px(U), px(U)), (0, 0, 0, 0))
    draw_logo(ImageDraw.Draw(img), mono=mono)
    return img.resize((size, size), Image.LANCZOS)

def font(path, size):
    return ImageFont.truetype(os.path.join(r"C:\Windows\Fonts", path), size)

def thumbnail(w=1280, h=720):
    """The Nexus image. This one says AI NPC: its reader is a modder, not a citizen."""
    W, H = w * 2, h * 2
    img = Image.new("RGB", (W, H), INK)
    d = ImageDraw.Draw(img)
    for y in range(0, H, 8):
        d.line([(0, y), (W, y)], fill=(20, 24, 30), width=2)

    logo = render(int(H * 0.62))
    lx, ly = int(W * 0.075), (H - logo.size[1]) // 2
    img.paste(logo, (lx, ly), logo)

    tx = lx + logo.size[0] + int(W * 0.05)
    f1 = font("bahnschrift.ttf", int(H * 0.155))
    f2 = font("consola.ttf", int(H * 0.040))
    # One line, two colours. "AI NPC" is short enough that stacking it left a hole where
    # NightCityAgenda's two long words filled the block.
    ty = int(H * 0.335)
    d.text((tx, ty), "AI", font=f1, fill=YELLOW)
    d.text((tx + d.textlength("AI ", font=f1), ty), "NPC", font=f1, fill=CYAN)
    # Shrunk to fit rather than sized by eye: the first value that looked right in the
    # designer's head ran off the right edge of the image.
    sub = "UNSCRIPTED CONVERSATION"
    room = int(W * 0.93) - tx
    f3 = font("bahnschrift.ttf", int(H * 0.062))
    while d.textlength(sub, font=f3) > room and f3.size > 8:
        f3 = font("bahnschrift.ttf", f3.size - 2)
    d.text((tx + 6, ty + int(H * 0.175)), sub, font=f3, fill=(210, 216, 224))
    d.line([(tx, int(H * 0.665)), (int(W * 0.93), int(H * 0.665))], fill=YELLOW, width=6)
    d.text((tx, int(H * 0.695)), "night city texts back // agentlink.nc", font=f2, fill=(150, 160, 172))
    return img.resize((w, h), Image.LANCZOS)

os.makedirs(OUT, exist_ok=True)
for size in (1024, 512, 256, 128):
    render(size).save(os.path.join(OUT, f"agentlink_logo_{size}.png"))
for size in (256, 128):
    render(size, mono=(255, 255, 255, 255)).save(os.path.join(OUT, f"agentlink_icon_mono_{size}.png"))
thumbnail().save(os.path.join(OUT, "ainpc_nexus_thumb_1280x720.png"))
print("written to", OUT)
