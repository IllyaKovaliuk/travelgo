"""PNG preview: OSM tiles + track coloured by segment transport + numbered pins + legend."""
import io, json, math, os, time, requests
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(__file__)
UA = {"User-Agent": "NomadSeedRoutes/1.0 (preview; contact illyakovaliuk@gmail.com)"}
COL = {"foot": "#2E9E5B", "overland": "#E8743B", "water": "#2F7FC1", "climb": "#7A5FBF", "bike": "#D9A21B"}
PIN = {"water": "#3E92CC", "camp": "#2E9E5B", "viewpoint": "#D9A21B", "vehicle": "#E8743B"}
W = H = 900

def mercator(lat, lon, z):
    n = 2**z; x = (lon+180)/360*n
    y = (1-math.log(math.tan(math.radians(lat))+1/math.cos(math.radians(lat)))/math.pi)/2*n
    return x, y

def tile(z, x, y):
    p = os.path.join(HERE, "cache", f"tile_{z}_{x}_{y}.png")
    if os.path.exists(p): return Image.open(p).convert("RGB")
    r = requests.get(f"https://tile.openstreetmap.org/{z}/{x}/{y}.png", headers=UA, timeout=30)
    r.raise_for_status(); open(p, "wb").write(r.content); time.sleep(0.3)
    return Image.open(io.BytesIO(r.content)).convert("RGB")

def render(res, src, out_path):
    line = src["line_full"]; lats = [p[0] for p in line]; lons = [p[1] for p in line]
    s, n, w, e = min(lats), max(lats), min(lons), max(lons)
    pad = 0.12
    for z in range(16, 2, -1):
        x0, y1 = mercator(s, w, z); x1, y0 = mercator(n, e, z)
        pw, ph = (x1-x0)*256*(1+pad*2), (y1-y0)*256*(1+pad*2)
        if pw <= W and ph <= H: break
    cx, cy = (x0+x1)/2, (y0+y1)/2
    left, top = cx*256 - W/2, cy*256 - H/2
    img = Image.new("RGB", (W, H), "#dddddd")
    for tx in range(int(left//256), int((left+W)//256)+1):
        for ty in range(int(top//256), int((top+H)//256)+1):
            try: img.paste(tile(z, tx, ty), (int(tx*256-left), int(ty*256-top)))
            except Exception: pass
    img = Image.blend(img, Image.new("RGB", img.size, "white"), 0.25)
    d = ImageDraw.Draw(img, "RGBA")
    px = lambda lat, lon: ((mercator(lat, lon, z)[0]*256-left), (mercator(lat, lon, z)[1]*256-top))
    # colour by segment transport via cumulative distance share
    segs = res["segments"]; tr = src["seg_transports"]; total = sum(s_["distance_km"] for s_ in segs) or 1
    cum = [0]; 
    for s_ in segs: cum.append(cum[-1]+s_["distance_km"]/total)
    pts = [px(*p) for p in line]
    for i in range(len(pts)-1):
        f = i/(len(pts)-1)
        k = next((j for j in range(len(segs)) if f <= cum[j+1]), len(segs)-1)
        d.line([pts[i], pts[i+1]], fill="white", width=9)
    for i in range(len(pts)-1):
        f = i/(len(pts)-1)
        k = next((j for j in range(len(segs)) if f <= cum[j+1]), len(segs)-1)
        d.line([pts[i], pts[i+1]], fill=COL[tr[k]], width=5)
    try: font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 15); big = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 22)
    except Exception: font = big = ImageFont.load_default()
    for r_ in (pts[0], pts[-1]):
        d.ellipse([r_[0]-8, r_[1]-8, r_[0]+8, r_[1]+8], fill="black", outline="white", width=3)
    d.text((pts[0][0]+11, pts[0][1]-8), "START", fill="black", font=font, stroke_width=3, stroke_fill="white")
    d.text((pts[-1][0]+11, pts[-1][1]-8), "END", fill="black", font=font, stroke_width=3, stroke_fill="white")
    for i, p in enumerate(res["pois"], 1):
        x, y = px(p["lat"], p["lng"])
        d.ellipse([x-12, y-12, x+12, y+12], fill=PIN.get(p["category"], "#888"), outline="white", width=3)
        d.text((x-4*len(str(i))+1, y-8), str(i), fill="white", font=font)
    r = res["route"]
    d.rectangle([0, 0, W, 62], fill=(20, 28, 24, 230))
    d.text((14, 8), r["title"].replace("\n", " "), fill="white", font=big)
    d.text((14, 36), f'{r["place"]} · {r["distance_km"]} km · +{r["ascent_m"]} m · max {r["high_point_m"]} m · {r["difficulty"].upper()} · {r["transport_label"]}', fill=(220, 230, 220), font=font)
    ly = H-24*(len(res["pois"])+1)-8
    d.rectangle([0, ly-4, 430, H], fill=(255, 255, 255, 215))
    d.text((10, ly), "PINS (real OSM features ≤150 m from track)" if res["pois"] else "no pins (no matching OSM feature near track)", fill="black", font=font)
    for i, p in enumerate(res["pois"], 1):
        d.text((10, ly+24*i), f'{i}. [{p["category"]}] {p["title"]}' + (f' — {p["note"]}' if p["note"] else ""), fill="black", font=font)
    d.text((W-300, H-20), "Map © OpenStreetMap contributors", fill="black", font=font, stroke_width=2, stroke_fill="white")
    img.save(out_path)
