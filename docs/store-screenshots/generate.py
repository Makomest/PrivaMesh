#!/usr/bin/env python3
"""
Telegram-style App Store screenshots for PrivaMesh.

Usage:
  - Put your raw app screenshots (from the iPhone 16 Plus simulator, Cmd+S)
    into RAW_DIR named 1.png, 2.png, ... matching the PANELS order below.
  - Run: python3 store_shots.py
  - Output framed panels -> OUT_DIR (1290x2796, ready for App Store Connect).
A screenshot may be missing; that panel is rendered with a placeholder.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

RAW_DIR = "/Users/roni/Documents/PrivaMesh-Release/docs/store-screenshots/raw"
OUT_DIR = "/Users/roni/Documents/PrivaMesh-Release/docs/store-screenshots/out"
os.makedirs(RAW_DIR, exist_ok=True)
os.makedirs(OUT_DIR, exist_ok=True)

W, H = 1290, 2796                      # 6.7" App Store size
HEAD_F = "/System/Library/Fonts/SFNSRounded.ttf"
SUB_F  = "/System/Library/Fonts/Supplemental/Arial.ttf"
BOLD_F = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

# headline, subheadline, gradient (top-left rgb, bottom-right rgb)
PANELS = [
    ("Private by default",
     "End-to-end encrypted. A new key for every message.",
     (34, 197, 150), (16, 138, 110)),
    ("No servers. Seriously.",
     "Your messages live on the blockchain - nothing to hack or shut down.",
     (99, 102, 241), (139, 92, 246)),
    ("Hide who, when, how",
     "Stealth addresses and cover traffic mask your metadata.",
     (20, 184, 166), (14, 165, 233)),
    ("No phone. No email.",
     "Your identity is a key only you hold. Find friends by nickname.",
     (245, 158, 11), (234, 88, 12)),
    ("Send value in chat",
     "A built-in Solana wallet - pay or gift right inside a conversation.",
     (56, 189, 248), (37, 99, 235)),
    ("Own your identity",
     "On-chain NFT avatars and nicknames - truly yours.",
     (168, 85, 247), (236, 72, 153)),
]

def gradient(c1, c2):
    base = Image.new("RGB", (W, H), c1)
    top = Image.new("RGB", (W, H), c2)
    mask = Image.new("L", (W, H))
    md = mask.load()
    for y in range(H):
        for x in range(0, W, 4):
            v = int(((x / W) + (y / H)) / 2 * 255)
            md[x, y] = v
            for dx in range(1, 4):
                if x + dx < W: md[x + dx, y] = v
    return Image.composite(top, base, mask)

def rounded(img, rad):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0], img.size[1]], rad, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out

def wrap(draw, text, font, maxw):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=font) <= maxw:
            cur = t
        else:
            if cur: lines.append(cur)
            cur = w
    if cur: lines.append(cur)
    return lines

def phone_frame(shot):
    # device: width PW, bezel ~ B, screen rounded
    PW = 880
    ratio = 2796 / 1290
    PH = int(PW * ratio)
    B = 18
    bezel = Image.new("RGBA", (PW, PH), (0, 0, 0, 0))
    ImageDraw.Draw(bezel).rounded_rectangle([0, 0, PW, PH], 96, fill=(17, 24, 39, 255))
    inner_w, inner_h = PW - 2 * B, PH - 2 * B
    if shot is not None:
        s = shot.convert("RGB")
        # cover-fit to inner, top-aligned
        sr = inner_w / s.width
        s = s.resize((inner_w, int(s.height * sr)))
        if s.height > inner_h: s = s.crop((0, 0, inner_w, inner_h))
        screen = Image.new("RGB", (inner_w, inner_h), (11, 16, 32))
        screen.paste(s, (0, 0))
    else:
        screen = Image.new("RGB", (inner_w, inner_h), (24, 33, 56))
        ImageDraw.Draw(screen).text((inner_w//2, inner_h//2), "screenshot",
                                     font=ImageFont.truetype(SUB_F, 40), fill=(120,140,170), anchor="mm")
    bezel.paste(rounded(screen, 80), (B, B), rounded(screen, 80))
    return bezel

def build(i, headline, sub, c1, c2, shot):
    img = gradient(c1, c2).convert("RGBA")
    d = ImageDraw.Draw(img)
    # headline
    hf = ImageFont.truetype(HEAD_F, 104)
    sf = ImageFont.truetype(SUB_F, 50)
    y = 230
    for ln in wrap(d, headline, hf, W - 160):
        d.text((W//2, y), ln, font=hf, fill=(255,255,255), anchor="ma")
        y += 120
    y += 18
    for ln in wrap(d, sub, sf, W - 220):
        d.text((W//2, y), ln, font=sf, fill=(255,255,255,225), anchor="ma")
        y += 66
    # phone, bottom, partly cut off
    frame = phone_frame(shot)
    fx = (W - frame.width)//2
    fy = y + 70
    # soft shadow
    sh = Image.new("RGBA", img.size, (0,0,0,0))
    ImageDraw.Draw(sh).rounded_rectangle([fx, fy, fx+frame.width, fy+frame.height], 96, fill=(0,0,0,90))
    sh = sh.filter(ImageFilter.GaussianBlur(40))
    img.alpha_composite(sh)
    img.alpha_composite(frame, (fx, fy))
    out = os.path.join(OUT_DIR, f"{i}.png")
    img.convert("RGB").save(out, "PNG")
    return out

if __name__ == "__main__":
    for idx, (hl, sub, c1, c2) in enumerate(PANELS, start=1):
        p = os.path.join(RAW_DIR, f"{idx}.png")
        shot = Image.open(p) if os.path.exists(p) else None
        out = build(idx, hl, sub, c1, c2, shot)
        print(f"panel {idx}: {'shot' if shot else 'PLACEHOLDER'} -> {out}")
    print("\nDone. Put raw screenshots in:", RAW_DIR)
