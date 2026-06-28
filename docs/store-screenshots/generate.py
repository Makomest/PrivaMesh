#!/usr/bin/env python3
"""
Unique PrivaMesh App Store screenshots: dark brand aesthetic with a mesh-network
motif (nodes + edges, like the logo), a neon glow behind the device, a bold
headline with one accent word, and a feature pill.

Usage: put raw app screenshots in raw/1.png..6.png, then `python3 generate.py`.
Output -> out/1.png.. (1290x2796, ready for App Store Connect).
"""
import os, math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BASE = os.path.dirname(os.path.abspath(__file__))
RAW_DIR = os.path.join(BASE, "raw")
OUT_DIR = os.path.join(BASE, "out")
os.makedirs(RAW_DIR, exist_ok=True); os.makedirs(OUT_DIR, exist_ok=True)

W, H = 1290, 2796
ROUND   = "/System/Library/Fonts/SFNSRounded.ttf"
ARIAL   = "/System/Library/Fonts/Supplemental/Arial.ttf"
ARIALB  = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

BG       = (8, 12, 24)        # deep navy base
TEAL     = (34, 197, 150)     # brand accent
INK      = (226, 232, 240)
GREY     = (130, 146, 170)

# headline, accent_word (colored teal), subheadline, pill text, glow accent rgb
PANELS = [
    ("Private by default", "default",
     "End-to-end encrypted. A new key for every message.",
     "End-to-end encrypted", TEAL),
    ("No servers. Seriously.", "servers.",
     "Your messages live on the blockchain - nothing to shut down.",
     "Zero backend", (56, 189, 248)),
    ("Hide who, when, how", "Hide",
     "Stealth addresses and cover traffic mask your metadata.",
     "Metadata hidden", (139, 122, 246)),
    ("No phone. No email.", "No phone.",
     "Your identity is a key only you hold. Find friends by nickname.",
     "No tracking", (245, 158, 11)),
    ("Send value in chat", "value",
     "A built-in Solana wallet - pay or gift right inside a conversation.",
     "Built-in wallet", TEAL),
    ("Own your identity", "Own",
     "On-chain NFT avatars and nicknames - truly yours.",
     "On-chain NFTs", (236, 110, 180)),
]

def mesh_bg(accent):
    img = Image.new("RGB", (W, H), BG)
    glow = Image.new("RGB", (W, H), BG)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([W//2-700, -500, W//2+700, 900],
               fill=tuple(min(255, int(BG[i] + (accent[i]-BG[i])*0.5)) for i in range(3)))
    glow = glow.filter(ImageFilter.GaussianBlur(260))
    img = Image.blend(img, glow, 0.6)
    rnd = random.Random(7)
    nodes = [(rnd.randint(40, W-40), rnd.randint(40, H-40)) for _ in range(46)]
    layer = Image.new("RGBA", (W, H), (0,0,0,0))
    ld = ImageDraw.Draw(layer)
    for i, a in enumerate(nodes):
        for b in nodes[i+1:]:
            d = math.dist(a, b)
            if d < 330:
                al = int(38 * (1 - d/330))
                ld.line([a, b], fill=(accent[0], accent[1], accent[2], al), width=2)
    for (x, y) in nodes:
        r = rnd.choice([4, 5, 7])
        ld.ellipse([x-r, y-r, x+r, y+r], fill=(accent[0], accent[1], accent[2], 90))
    img = Image.alpha_composite(img.convert("RGBA"), layer)
    vg = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vg).rectangle([0, int(H*0.55), W, H], fill=120)
    vg = vg.filter(ImageFilter.GaussianBlur(200))
    dark = Image.new("RGBA", (W, H), (4, 7, 16, 255))
    img = Image.composite(dark, img, vg)
    return img

def rounded(img, rad):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0,0,*img.size], rad, fill=255)
    o = img.convert("RGBA"); o.putalpha(m); return o

def phone(shot, accent):
    PW = 900; PH = int(PW * (2796/1290)); B = 18
    bez = Image.new("RGBA", (PW, PH), (0,0,0,0))
    ImageDraw.Draw(bez).rounded_rectangle([0,0,PW,PH], 100, fill=(15,20,34,255))
    iw, ih = PW-2*B, PH-2*B
    if shot:
        s = shot.convert("RGB"); r = iw/s.width
        s = s.resize((iw, int(s.height*r)))
        if s.height > ih: s = s.crop((0,0,iw,ih))
        scr = Image.new("RGB", (iw, ih), BG); scr.paste(s, (0,0))
    else:
        scr = Image.new("RGB", (iw, ih), (20,28,48))
    bez.alpha_composite(rounded(scr, 84), (B, B))
    return bez

def build(i, headline, accent_word, sub, pill, accent):
    img = mesh_bg(accent).convert("RGBA")
    d = ImageDraw.Draw(img)
    hf = ImageFont.truetype(ROUND, 100)
    sf = ImageFont.truetype(ARIAL, 46)
    pf = ImageFont.truetype(ARIALB, 34)
    space = d.textlength(" ", font=hf)
    parts = [(w, (w == accent_word)) for w in headline.split()]
    # wrap headline
    lines, cur, curw = [], [], 0.0
    for word, acc in parts:
        ww = d.textlength(word, font=hf)
        if cur and curw + space + ww > W-150:
            lines.append(cur); cur, curw = [], 0.0
        cur.append((word, acc, ww)); curw += (space if len(cur) > 1 else 0) + ww
    if cur: lines.append(cur)
    y = 210
    for line in lines:
        total = sum(w for _,_,w in line) + space*(len(line)-1)
        x = (W-total)//2
        for word, acc, ww in line:
            d.text((x, y), word, font=hf, fill=accent if acc else INK)
            x += ww + space
        y += 118
    y += 14
    words, slines, scur = sub.split(), [], ""
    for w in words:
        t = (scur+" "+w).strip()
        if d.textlength(t, font=sf) <= W-220: scur = t
        else: slines.append(scur); scur = w
    if scur: slines.append(scur)
    for ln in slines:
        d.text((W//2, y), ln, font=sf, fill=GREY, anchor="ma"); y += 62
    # phone + neon glow
    sp = os.path.join(RAW_DIR, f"{i}.png")
    fr = phone(Image.open(sp) if os.path.exists(sp) else None, accent)
    fx = (W-fr.width)//2; fy = y + 90
    glow = Image.new("RGBA", img.size, (0,0,0,0))
    ImageDraw.Draw(glow).rounded_rectangle([fx-10, fy-10, fx+fr.width+10, fy+fr.height+10], 110,
                                           fill=(accent[0], accent[1], accent[2], 130))
    glow = glow.filter(ImageFilter.GaussianBlur(70))
    img.alpha_composite(glow)
    img.alpha_composite(fr, (fx, fy))
    # feature pill over top of phone
    ph = 70
    pw = int(d.textlength(pill, font=pf)) + 52 + 38
    px = (W-pw)//2; py = fy - ph//2
    pi = Image.new("RGBA", (pw, ph), (0,0,0,0))
    pd = ImageDraw.Draw(pi)
    pd.rounded_rectangle([0,0,pw,ph], ph//2, fill=(15,22,38,255),
                         outline=(accent[0],accent[1],accent[2],255), width=2)
    pd.ellipse([24, ph//2-9, 42, ph//2+9], fill=accent)
    pd.text((56, ph//2), pill, font=pf, fill=INK, anchor="lm")
    img.alpha_composite(pi, (px, py))
    out = os.path.join(OUT_DIR, f"{i}.png")
    img.convert("RGB").save(out, "PNG")
    return out

if __name__ == "__main__":
    for idx, (hl, aw, sub, pill, acc) in enumerate(PANELS, start=1):
        has = os.path.exists(os.path.join(RAW_DIR, f"{idx}.png"))
        build(idx, hl, aw, sub, pill, acc)
        print(f"panel {idx}: {'shot' if has else 'PLACEHOLDER'} -> out/{idx}.png")
    print("Done.")
