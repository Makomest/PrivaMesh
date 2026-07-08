#!/usr/bin/env python3
"""
Onboarding-style App Store panels (light pastel + glass card + mesh icon + bullets),
focused on: serverless, decentralized, messages through the blockchain.
Fully generated (no device screenshot). Output -> out/1-1.png, 1-2.png, ...
"""
import os, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(BASE, "out"); os.makedirs(OUT, exist_ok=True)

W, H = 1290, 2796
ROUND  = "/System/Library/Fonts/SFNSRounded.ttf"
ARIAL  = "/System/Library/Fonts/Supplemental/Arial.ttf"
ARIALB = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

INK   = (30, 41, 59)
GREY  = (90, 105, 130)
TEAL  = (16, 160, 120)
# light pastel stops (like the app onboarding background)
C_TL  = (210, 245, 232)   # mint
C_BR  = (224, 214, 250)   # lavender

PANELS = [
    ("1-1", "No servers.\nBy design.",
     "PrivaMesh has no backend. It speaks only to the blockchain.",
     [("No central server", "nothing to hack, log, or shut down"),
      ("Fully decentralized", "runs on Solana, not on our servers"),
      ("No account database", "you are just a key on your device")]),
    ("1-2", "Messages\nthrough the chain",
     "Every message is an encrypted event on the Solana blockchain.",
     [("Encrypted memo", "your message rides inside a normal transaction"),
      ("Immutable ledger", "no relay, no middleman, no message server"),
      ("Anyone can verify", "delivery is a public, auditable on-chain record")]),
    ("1-3", "Censorship-\nresistant",
     "To silence you, they would have to block the entire blockchain.",
     [("No node to pressure", "there is no operator to coerce or seize"),
      ("Always reachable", "as long as Solana lives, so does your chat"),
      ("Trustless by default", "math and a public ledger, not a company")]),
]

def gradient():
    base = Image.new("RGB", (W, H), C_TL)
    top = Image.new("RGB", (W, H), C_BR)
    mask = Image.new("L", (W, H))
    md = mask.load()
    for y in range(H):
        for x in range(0, W, 3):
            v = int(((x / W) + (y / H)) / 2 * 255)
            for dx in range(3):
                if x+dx < W: md[x+dx, y] = v
    return Image.composite(top, base, mask)

def mesh_icon(d, cx, cy, R):
    # brand mesh: 5 outer nodes + center, connected
    pts = [(cx, cy)]
    for k in range(5):
        a = -math.pi/2 + k*2*math.pi/5
        pts.append((cx + R*0.62*math.cos(a), cy + R*0.62*math.sin(a)))
    for i in range(1, 6):
        d.line([pts[0], pts[i]], fill=TEAL+(255,), width=6)
        nxt = 1 + (i % 5)
        d.line([pts[i], pts[nxt]], fill=TEAL+(180,), width=5)
    for (x, y) in pts:
        r = 16 if (x, y) == (cx, cy) else 13
        d.ellipse([x-r, y-r, x+r, y+r], fill=(255,255,255,255), outline=TEAL+(255,), width=5)

def build(name, title, sub, bullets):
    img = gradient().convert("RGBA")
    d = ImageDraw.Draw(img)
    tf = ImageFont.truetype(ROUND, 116)
    sf = ImageFont.truetype(ARIAL, 46)
    bl = ImageFont.truetype(ARIALB, 40)
    bt = ImageFont.truetype(ARIAL, 38)

    # icon halo + glass circle + dashed ring + mesh
    cx, cy, R = W//2, 470, 150
    halo = Image.new("RGBA", img.size, (0,0,0,0))
    ImageDraw.Draw(halo).ellipse([cx-R, cy-R, cx+R, cy+R], fill=(16,160,120,90))
    halo = halo.filter(ImageFilter.GaussianBlur(60))
    img.alpha_composite(halo)
    d.ellipse([cx-R*0.86, cy-R*0.86, cx+R*0.86, cy+R*0.86], fill=(255,255,255,150))
    # dashed ring
    for k in range(40):
        a0 = k*2*math.pi/40
        if k % 2 == 0:
            x1, y1 = cx+R*math.cos(a0), cy+R*math.sin(a0)
            x2, y2 = cx+R*math.cos(a0+0.11), cy+R*math.sin(a0+0.11)
            d.line([(x1,y1),(x2,y2)], fill=TEAL+(220,), width=6)
    mesh_icon(d, cx, cy, R*0.7)

    # title (centered, 2 lines)
    y = 700
    for ln in title.split("\n"):
        d.text((W//2, y), ln, font=tf, fill=INK, anchor="ma"); y += 132
    y += 6
    # sub (wrap)
    words, lines, cur = sub.split(), [], ""
    for w in words:
        t = (cur+" "+w).strip()
        if d.textlength(t, font=sf) <= W-200: cur = t
        else: lines.append(cur); cur = w
    if cur: lines.append(cur)
    for ln in lines:
        d.text((W//2, y), ln, font=sf, fill=GREY, anchor="ma"); y += 62

    # glass bullet card
    cardx, cardw = 90, W-180
    cy0 = y + 60
    rows = []
    for lead, rest in bullets:
        rows.append((lead, rest))
    rowh = 168
    cardh = 60 + rowh*len(rows)
    card = Image.new("RGBA", (cardw, cardh), (255,255,255,150))
    ImageDraw.Draw(card).rounded_rectangle([0,0,cardw,cardh], 46, fill=(255,255,255,150),
                                           outline=(255,255,255,200), width=2)
    cd = ImageDraw.Draw(card)
    ry = 44
    for lead, rest in rows:
        # node dot
        cd.ellipse([40, ry+8, 70, ry+38], fill=TEAL+(255,))
        # lead bold + rest, wrapped under
        cd.text((104, ry), lead, font=bl, fill=INK)
        lx = 104 + cd.textlength(lead, font=bl) + 16
        # rest on same line if fits else next line
        if lx + cd.textlength(rest, font=bt) <= cardw-50:
            cd.text((lx, ry+4), rest, font=bt, fill=GREY)
        else:
            cd.text((104, ry+52), rest, font=bt, fill=GREY)
        ry += rowh
    img.alpha_composite(card, (cardx, cy0))

    out = os.path.join(OUT, f"{name}.png")
    img.convert("RGB").save(out, "PNG")
    return out

if __name__ == "__main__":
    for name, title, sub, bullets in PANELS:
        build(name, title, sub, bullets)
        print(f"-> out/{name}.png")
    print("Done.")
