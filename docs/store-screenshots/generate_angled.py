#!/usr/bin/env python3
"""
App Store panels from the user's angled 3D phone renders (square 2160x2160,
light-grey bg, app screenshot already composited inside the device).

For each render: flood-fill the light-grey background to transparent, place the
device on a soft per-panel color background, add the matching caption headline
+ subline on top. Output portrait 1290x2796 -> out/appstore/01..06.png.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BASE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(BASE, "out")
OUT = os.path.join(BASE, "out", "appstore")
os.makedirs(OUT, exist_ok=True)

W, H = 1290, 2796
ROUND = "/System/Library/Fonts/SFNSRounded.ttf"
ARIAL = "/System/Library/Fonts/Supplemental/Arial.ttf"
INK = (24, 32, 48)
GREY = (96, 110, 132)

# file, headline, accent_word, subline, (bg_top, bg_bottom)
PANELS = [
 ("200° 15° 15°.png", "Private by default", "Private",
  "End-to-end encrypted. A new key for every message.",
  ((224, 246, 238), (214, 226, 250))),
 ("140° 1° 0°.png", "No servers. Seriously.", "servers.",
  "Every message is an on-chain event - nothing to shut down.",
  ((220, 235, 252), (232, 224, 250))),
 ("215° 20° 0°.png", "Hide who, when, how", "Hide",
  "Stealth addresses and cover traffic mask your metadata.",
  ((236, 228, 250), (224, 240, 244))),
 ("215° 12° -25°.png", "No phone. No email.", "No",
  "Your identity is a key only you hold. Find friends by nickname.",
  ((252, 240, 224), (250, 226, 230))),
 ("135° 0° -25°.png", "Send value in chat", "value",
  "A built-in Solana wallet - pay or gift right inside a chat.",
  ((224, 246, 236), (224, 238, 252))),
 ("140° 0° 0°.png", "Own your identity", "Own",
  "On-chain NFT avatars and nicknames - truly yours.",
  ((250, 230, 244), (232, 228, 250))),
]
ACCENT = (16, 160, 120)


def gradient(top, bot):
    base = Image.new("RGB", (W, H), bot)
    t = Image.new("RGB", (W, H), top)
    m = Image.new("L", (W, H))
    md = m.load()
    for y in range(H):
        v = int(255 * (1 - y / H))
        for x in range(0, W, 4):
            for dx in range(4):
                if x + dx < W:
                    md[x + dx, y] = v
    return Image.composite(t, base, m)


def cut_phone(path):
    """Flood-fill the light-grey background from the corners -> transparent."""
    img = Image.open(path).convert("RGB")
    key = (255, 0, 255)
    w, h = img.width, img.height
    seeds = [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3),   # black border corners
             (w // 2, 4), (w // 2, h - 5), (4, h // 2), (w - 5, h // 2)]  # grey edges
    for c in seeds:
        ImageDraw.floodfill(img, c, key, thresh=30)
    px = img.load()
    alpha = Image.new("L", img.size, 255)
    ap = alpha.load()
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y] == key:
                ap[x, y] = 0
    # density-based bbox: ignore stray shadow specks, crop tight to the device
    ad = alpha.load()
    W0, H0 = alpha.size
    colcnt = [sum(1 for y in range(H0) if ad[x, y] > 40) for x in range(W0)]
    rowcnt = [sum(1 for x in range(W0) if ad[x, y] > 40) for y in range(H0)]
    cx = max(colcnt); cyv = max(rowcnt)
    xs = [x for x, c in enumerate(colcnt) if c > cx * 0.04]
    ys = [y for y, c in enumerate(rowcnt) if c > cyv * 0.04]
    box = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
    alpha = alpha.filter(ImageFilter.GaussianBlur(1.1))
    out = img.convert("RGBA")
    out.putalpha(alpha)
    return out.crop(box)


def build(i, fname, headline, aw, sub, colors):
    img = Image.new("RGB", (W, H), (255, 255, 255)).convert("RGBA")
    d = ImageDraw.Draw(img)
    hf = ImageFont.truetype(ROUND, 104)
    sf = ImageFont.truetype(ARIAL, 46)
    space = d.textlength(" ", font=hf)

    # headline (wrap, one accent word teal)
    parts = [(w, w == aw) for w in headline.split()]
    lines, cur, cw = [], [], 0.0
    for w, acc in parts:
        ww = d.textlength(w, font=hf)
        if cur and cw + space + ww > W - 150:
            lines.append(cur); cur, cw = [], 0.0
        cur.append((w, acc, ww)); cw += (space if len(cur) > 1 else 0) + ww
    if cur:
        lines.append(cur)
    y = 150
    for line in lines:
        tot = sum(w for _, _, w in line) + space * (len(line) - 1)
        x = (W - tot) // 2
        for w, acc, ww in line:
            d.text((x, y), w, font=hf, fill=ACCENT if acc else INK); x += ww + space
        y += 124
    y += 8

    # subline (wrap)
    words, sl, scur = sub.split(), [], ""
    for w in words:
        t = (scur + " " + w).strip()
        if d.textlength(t, font=sf) <= W - 200:
            scur = t
        else:
            sl.append(scur); scur = w
    if scur:
        sl.append(scur)
    for ln in sl:
        d.text((W // 2, y), ln, font=sf, fill=GREY, anchor="ma"); y += 60

    # phone BIG: fill remaining height under caption, clip side-bleed if needed
    ph = cut_phone(os.path.join(SRC, fname))
    top = y + 10
    th = H - top - 10               # fill to near bottom
    r = th / ph.height
    if ph.width * r > 1480:         # cap side-bleed
        r = 1480 / ph.width
    ph = ph.resize((int(ph.width * r), int(ph.height * r)), Image.LANCZOS)
    fx = (W - ph.width) // 2
    fy = top + max(0, (H - top - ph.height) // 2)   # center in space below caption
    img.alpha_composite(ph, (fx, fy))

    out = os.path.join(OUT, f"{i:02d}.png")
    img.convert("RGB").save(out, "PNG")
    return out


if __name__ == "__main__":
    for idx, (fn, hl, aw, sub, cols) in enumerate(PANELS, 1):
        build(idx, fn, hl, aw, sub, cols)
        print(f"-> out/appstore/{idx:02d}.png  ({hl})")
    print("Done.")
