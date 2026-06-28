#!/usr/bin/env python3
"""
Connected App Store ribbon: one continuous pastel background + flowing mesh wave
spanning all 6 panels, sliced into 6 portrait frames so their edges line up
(the gallery reads as a single ribbon). Each panel keeps its own angled device,
allowed to bleed past the panel edge so the "tips" carry into the neighbour.

out/appstore/01..06.png  (1290x2796 each).
"""
import os, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BASE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(BASE, "out")
OUT = os.path.join(BASE, "out", "appstore")
os.makedirs(OUT, exist_ok=True)

W, H = 1290, 2796
N = 6
BIGW = W * N
ROUND = "/System/Library/Fonts/SFNSRounded.ttf"
ARIAL = "/System/Library/Fonts/Supplemental/Arial.ttf"
INK = (24, 32, 48)
GREY = (96, 110, 132)
ACCENT = (16, 160, 120)

# file, headline, accent_word, subline
PANELS = [
 ("200° 15° 15°.png", "Private by default", "Private",
  "End-to-end encrypted. A new key for every message."),
 ("140° 1° 0°.png", "No servers. Seriously.", "servers.",
  "Every message is an on-chain event - nothing to shut down."),
 ("215° 20° 0°.png", "Hide who, when, how", "Hide",
  "Stealth addresses and cover traffic mask your metadata."),
 ("215° 12° -25°.png", "No phone. No email.", "No",
  "Your identity is a key only you hold. Find friends by nickname."),
 ("135° 0° -25°.png", "Send value in chat", "value",
  "A built-in Solana wallet - pay or gift right inside a chat."),
 ("140° 0° 0°.png", "Own your identity", "Own",
  "On-chain NFT avatars and nicknames - truly yours."),
]

# pastel colour anchors across the ribbon (wraps so the loop feels continuous)
STOPS = [
 (214, 246, 236), (224, 216, 250), (212, 232, 250),
 (252, 238, 222), (216, 246, 234), (250, 228, 242), (214, 246, 236),
]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def ribbon_bg():
    """Continuous horizontal pastel gradient + vertical lift + flowing mesh wave."""
    img = Image.new("RGB", (BIGW, H))
    px = img.load()
    seg = BIGW / (len(STOPS) - 1)
    # precompute per-column top colour
    cols = []
    for x in range(BIGW):
        k = x / seg
        i = min(int(k), len(STOPS) - 2)
        cols.append(lerp(STOPS[i], STOPS[i + 1], k - i))
    for y in range(H):
        vt = y / H  # 0 top -> 1 bottom ; lighten toward top
        for x in range(0, BIGW, 2):
            c = cols[x]
            lift = 1.0 - 0.10 * vt
            v = (min(255, int(c[0] * lift) + int(14 * (1 - vt))),
                 min(255, int(c[1] * lift) + int(14 * (1 - vt))),
                 min(255, int(c[2] * lift) + int(14 * (1 - vt))))
            px[x, y] = v
            if x + 1 < BIGW:
                px[x + 1, y] = v
    # flowing mesh wave across the whole ribbon
    layer = Image.new("RGBA", (BIGW, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    waves = [(H * 0.30, 150, 1600, 0.0), (H * 0.62, 210, 2100, 1.5)]
    for midy, amp, period, ph in waves:
        pts = [(x, midy + amp * math.sin(x / period * 2 * math.pi + ph))
               for x in range(0, BIGW, 26)]
        ld.line(pts, fill=(*ACCENT, 46), width=3, joint="curve")
        for i in range(0, len(pts), 4):
            x, y = pts[i]
            ld.ellipse([x - 6, y - 6, x + 6, y + 6], fill=(*ACCENT, 70))
            # short connector to the other wave for a "mesh" feel
            if i + 2 < len(pts):
                ld.line([pts[i], pts[i + 2]], fill=(*ACCENT, 26), width=2)
    layer = layer.filter(ImageFilter.GaussianBlur(0.6))
    return Image.alpha_composite(img.convert("RGBA"), layer)


def cut_phone(path):
    img = Image.open(path).convert("RGB")
    key = (255, 0, 255)
    w, h = img.size
    seeds = [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3),
             (w // 2, 4), (w // 2, h - 5), (4, h // 2), (w - 5, h // 2)]
    for c in seeds:
        ImageDraw.floodfill(img, c, key, thresh=30)
    px = img.load()
    alpha = Image.new("L", img.size, 255)
    ap = alpha.load()
    for y in range(h):
        for x in range(w):
            if px[x, y] == key:
                ap[x, y] = 0
    ad = alpha.load()
    W0, H0 = alpha.size
    colcnt = [sum(1 for y in range(H0) if ad[x, y] > 40) for x in range(W0)]
    rowcnt = [sum(1 for x in range(W0) if ad[x, y] > 40) for y in range(H0)]
    cx, cyv = max(colcnt), max(rowcnt)
    xs = [x for x, c in enumerate(colcnt) if c > cx * 0.04]
    ys = [y for y, c in enumerate(rowcnt) if c > cyv * 0.04]
    box = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
    alpha = alpha.filter(ImageFilter.GaussianBlur(1.1))
    out = img.convert("RGBA")
    out.putalpha(alpha)
    return out.crop(box)


def draw_panel(i, bg, fname, headline, aw, sub):
    img = bg.copy()
    d = ImageDraw.Draw(img)
    hf = ImageFont.truetype(ROUND, 104)
    sf = ImageFont.truetype(ARIAL, 46)
    space = d.textlength(" ", font=hf)

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

    # phone: big, biased so tips bleed off the panel edges into the neighbour
    ph = cut_phone(os.path.join(SRC, fname))
    top = y + 10
    th = H - top - 10
    r = th / ph.height
    if ph.width * r > 1560:          # allow more side-bleed for the "tips" effect
        r = 1560 / ph.width
    ph = ph.resize((int(ph.width * r), int(ph.height * r)), Image.LANCZOS)
    # alternate horizontal bias: odd panels lean left, even lean right -> tips cross
    bias = -70 if i % 2 == 0 else 70
    fx = (W - ph.width) // 2 + bias
    fy = top + max(0, (H - top - ph.height) // 2)
    img.alpha_composite(ph, (fx, fy))
    img.convert("RGB").save(os.path.join(OUT, f"{i + 1:02d}.png"), "PNG")


if __name__ == "__main__":
    print("building ribbon background...")
    big = ribbon_bg()
    for i, (fn, hl, aw, sub) in enumerate(PANELS):
        slc = big.crop((i * W, 0, (i + 1) * W, H))
        draw_panel(i, slc, fn, hl, aw, sub)
        print(f"-> out/appstore/{i + 1:02d}.png  ({hl})")
    print("Done.")
