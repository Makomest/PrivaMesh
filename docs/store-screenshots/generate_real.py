#!/usr/bin/env python3
"""
App Store panels using a REAL photoreal iPhone mockup (phone.png, green screen).
Detects the green screen, drops the app screenshot in, cuts the grey background,
and places the device on the dark brand mesh background with headline + pill.

raw/1.png..6.png -> out/r1.png..r6.png  (1290x2796).
"""
import os, math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BASE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(BASE, "raw"); OUT = os.path.join(BASE, "out")
PHONE = os.path.join(BASE, "phone.png")
os.makedirs(OUT, exist_ok=True)

W, H = 1290, 2796
ROUND="/System/Library/Fonts/SFNSRounded.ttf"
ARIAL="/System/Library/Fonts/Supplemental/Arial.ttf"
ARIALB="/System/Library/Fonts/Supplemental/Arial Bold.ttf"
BG=(8,12,24); TEAL=(34,197,150); INK=(226,232,240); GREY=(130,146,170)

PANELS=[
 ("Private by default","default","End-to-end encrypted. A new key for every message.","End-to-end encrypted",TEAL),
 ("No servers. Seriously.","servers.","Your messages live on the blockchain - nothing to shut down.","Zero backend",(56,189,248)),
 ("Hide who, when, how","Hide","Stealth addresses and cover traffic mask your metadata.","Metadata hidden",(139,122,246)),
 ("No phone. No email.","No phone.","Your identity is a key only you hold. Find friends by nickname.","No tracking",(245,158,11)),
 ("Send value in chat","value","A built-in Solana wallet - pay or gift right inside a conversation.","Built-in wallet",TEAL),
 ("Own your identity","Own","On-chain NFT avatars and nicknames - truly yours.","On-chain NFTs",(236,110,180)),
]

# wider green-dominant test -> catches anti-aliased green rim (no green fringe)
def isgreen(c): r,g,b=c[0],c[1],c[2]; return g>90 and g>r+18 and g>b+5
def isbg(c): r,g,b=c[0],c[1],c[2]; return r>=205 and g>=205 and b>=205 and max(r,g,b)-min(r,g,b)<22

def make_phone(shot):
    ph=Image.open(PHONE).convert("RGB"); pw,phh=ph.size; px=ph.load()
    minx,miny,maxx,maxy=pw,phh,0,0
    for y in range(phh):
        for x in range(pw):
            if isgreen(px[x,y]):
                if x<minx:minx=x
                if x>maxx:maxx=x
                if y<miny:miny=y
                if y>maxy:maxy=y
    bw,bh=maxx-minx+1,maxy-miny+1
    s=shot.convert("RGB"); r=bw/s.width; s=s.resize((bw,int(s.height*r)),Image.LANCZOS)
    if s.height>bh: s=s.crop((0,0,bw,bh))
    elif s.height<bh:
        c=Image.new("RGB",(bw,bh),BG); c.paste(s,(0,0)); s=c
    sp=s.load()
    alpha=Image.new("L",(pw,phh),255); ap=alpha.load()
    for y in range(phh):
        for x in range(pw):
            c=px[x,y]
            if isgreen(c):
                px[x,y]=sp[x-minx,y-miny]      # RGB: screenshot
            elif isbg(c):
                ap[x,y]=0                       # transparent bg
    alpha=alpha.filter(ImageFilter.GaussianBlur(0.9))   # anti-alias the cut
    out=ph.convert("RGBA"); out.putalpha(alpha)
    return out

def mesh_bg(accent):
    img=Image.new("RGB",(W,H),BG)
    glow=Image.new("RGB",(W,H),BG); gd=ImageDraw.Draw(glow)
    gd.ellipse([W//2-700,-500,W//2+700,900],fill=tuple(min(255,int(BG[i]+(accent[i]-BG[i])*0.5)) for i in range(3)))
    glow=glow.filter(ImageFilter.GaussianBlur(260)); img=Image.blend(img,glow,0.6)
    rnd=random.Random(7); nodes=[(rnd.randint(40,W-40),rnd.randint(40,H-40)) for _ in range(46)]
    layer=Image.new("RGBA",(W,H),(0,0,0,0)); ld=ImageDraw.Draw(layer)
    for i,a in enumerate(nodes):
        for b in nodes[i+1:]:
            d=math.dist(a,b)
            if d<330: ld.line([a,b],fill=(*accent,int(38*(1-d/330))),width=2)
    for (x,y) in nodes:
        r=rnd.choice([4,5,7]); ld.ellipse([x-r,y-r,x+r,y+r],fill=(*accent,90))
    img=Image.alpha_composite(img.convert("RGBA"),layer)
    vg=Image.new("L",(W,H),0); ImageDraw.Draw(vg).rectangle([0,int(H*0.55),W,H],fill=120)
    vg=vg.filter(ImageFilter.GaussianBlur(200)); dark=Image.new("RGBA",(W,H),(4,7,16,255))
    return Image.composite(dark,img,vg)

def build(i,headline,aw,sub,pill,accent):
    img=mesh_bg(accent).convert("RGBA"); d=ImageDraw.Draw(img)
    hf=ImageFont.truetype(ROUND,100); sf=ImageFont.truetype(ARIAL,46); pf=ImageFont.truetype(ARIALB,34)
    space=d.textlength(" ",font=hf)
    parts=[(w,(w==aw)) for w in headline.split()]
    lines,cur,cw=[],[],0.0
    for w,acc in parts:
        ww=d.textlength(w,font=hf)
        if cur and cw+space+ww>W-150: lines.append(cur); cur,cw=[],0.0
        cur.append((w,acc,ww)); cw+=(space if len(cur)>1 else 0)+ww
    if cur: lines.append(cur)
    y=205
    for line in lines:
        tot=sum(w for _,_,w in line)+space*(len(line)-1); x=(W-tot)//2
        for w,acc,ww in line:
            d.text((x,y),w,font=hf,fill=accent if acc else INK); x+=ww+space
        y+=118
    y+=14
    words,sl,scur=sub.split(),[],""
    for w in words:
        t=(scur+" "+w).strip()
        if d.textlength(t,font=sf)<=W-220: scur=t
        else: sl.append(scur); scur=w
    if scur: sl.append(scur)
    for ln in sl: d.text((W//2,y),ln,font=sf,fill=GREY,anchor="ma"); y+=62
    # real phone
    shot=Image.open(os.path.join(RAW,f"{i}.png"))
    ph=make_phone(shot)
    TW=940; r=TW/ph.width; ph=ph.resize((TW,int(ph.height*r)),Image.LANCZOS)
    fx=(W-ph.width)//2; fy=y+70
    # neon glow behind
    glow=Image.new("RGBA",img.size,(0,0,0,0))
    ImageDraw.Draw(glow).rounded_rectangle([fx+40,fy+40,fx+ph.width-40,fy+ph.height-40],110,fill=(*accent,120))
    glow=glow.filter(ImageFilter.GaussianBlur(80)); img.alpha_composite(glow)
    img.alpha_composite(ph,(fx,fy))
    # pill over top
    ph2=70; pw=int(d.textlength(pill,font=pf))+52+38; px_=(W-pw)//2; py=fy+30
    pi=Image.new("RGBA",(pw,ph2),(0,0,0,0)); pd=ImageDraw.Draw(pi)
    pd.rounded_rectangle([0,0,pw,ph2],ph2//2,fill=(15,22,38,255),outline=(*accent,255),width=2)
    pd.ellipse([24,ph2//2-9,42,ph2//2+9],fill=accent); pd.text((56,ph2//2),pill,font=pf,fill=INK,anchor="lm")
    img.alpha_composite(pi,(px_,py))
    out=os.path.join(OUT,f"r{i}.png"); img.convert("RGB").save(out,"PNG"); return out

if __name__=="__main__":
    for idx,(hl,aw,sub,pill,acc) in enumerate(PANELS,1):
        build(idx,hl,aw,sub,pill,acc); print(f"-> out/r{idx}.png")
    print("Done.")
