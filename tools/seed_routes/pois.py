"""POIs: ONLY real OSM features within 150 m of the track (rule 3)."""
import math
import osmapi
from geo import project, dist_point_to_line_m, cumdist

MAX_DIST = 150.0

def _cat(t):
    n, a, tr = t.get("natural"), t.get("amenity"), t.get("tourism")
    if n == "spring" or a == "drinking_water": return "water", "Spring" if n == "spring" else "Drinking water"
    if tr in {"alpine_hut", "wilderness_hut"}: return "camp", "Mountain hut"
    if tr == "camp_site": return "camp", "Campsite"
    if tr == "viewpoint": return "viewpoint", "Viewpoint"
    if n == "peak": return "viewpoint", "Peak"
    if n == "water": return "water", "Lake"
    if a == "parking": return "vehicle", "Parking"
    return None, None

def _chunks(line, km=8.0):
    cd = cumdist(line); out, start = [], 0
    for i, d in enumerate(cd):
        if d - cd[start] >= km*1000 or i == len(line)-1:
            seg = line[start:i+1]
            if len(seg) > 1: out.append(seg)
            start = i
    return out or [line]

def find(line):
    xy, kx, ky = project(line)
    found = {}
    for seg in _chunks(line):
        pad = 0.0025
        s, w = min(p[0] for p in seg)-pad, min(p[1] for p in seg)-pad
        n, e = max(p[0] for p in seg)+pad, max(p[1] for p in seg)+pad
        bb = f"({s:.5f},{w:.5f},{n:.5f},{e:.5f})"
        els = osmapi.map_bbox(s, w, n, e)
        nodes = {x["id"]: (x["lat"], x["lon"]) for x in els if x["type"] == "node"}
        for el in els:
            t = el.get("tags", {})
            if not t or el["type"] == "relation": continue
            cat, kind = _cat(t)
            if not cat: continue
            if el["type"] == "node": lat, lon = el["lat"], el["lon"]
            else:
                pts = [nodes[i] for i in el.get("nodes", []) if i in nodes]
                if not pts: continue
                lat = sum(q[0] for q in pts)/len(pts); lon = sum(q[1] for q in pts)/len(pts)
            if kind == "Lake" and not t.get("name"): continue
            d = dist_point_to_line_m((lat, lon), xy, kx, ky)
            if d <= MAX_DIST:
                found[(el["type"], el["id"])] = {"osm": f'{el["type"]}/{el["id"]}', "lat": lat, "lon": lon, "cat": cat, "kind": kind, "tags": t, "off_m": d}
    return list(found.values())

def select(cands, line, max_pins=9):
    """Pick a useful, spaced subset (<= max_pins), ordered along the track."""
    xy, kx, ky = project(line); cd = cumdist(line)
    def along(c):
        px, py = c["lon"]*kx, c["lat"]*ky
        best, bi = 1e18, 0
        for i, (x, y) in enumerate(xy):
            d = (x-px)**2 + (y-py)**2
            if d < best: best, bi = d, i
        return cd[bi]
    for c in cands: c["along"] = along(c)
    start_pt = line[0]
    def prio(c):
        named = 1 if c["tags"].get("name") else 0
        base = {"Peak": 5, "Mountain hut": 5, "Campsite": 4, "Lake": 3, "Viewpoint": 3, "Spring": 2, "Drinking water": 2, "Parking": 1}[c["kind"]]
        return (named*10 + base, -c["off_m"])
    picked = []
    quota = {"Peak": 3, "Mountain hut": 3, "Campsite": 2, "Lake": 2, "Viewpoint": 2, "Spring": 2, "Drinking water": 1, "Parking": 1}
    used = {}
    for c in sorted(cands, key=prio, reverse=True):
        k = c["kind"]
        if used.get(k, 0) >= quota[k]: continue
        if k == "Parking" and c["along"] > 300: continue            # parking only as the START pin
        if k in {"Spring", "Drinking water", "Viewpoint"} and not True: continue
        if any(abs(c["along"] - p["along"]) < 300 and c["kind"] == p["kind"] for p in picked): continue
        if any(abs(c["along"] - p["along"]) < 80 for p in picked): continue
        # same-place duplicates (e.g. a hut mapped as both a camp_site and an alpine_hut)
        if k in {"Mountain hut", "Campsite"} and any(p["kind"] in {"Mountain hut", "Campsite"} and abs(c["along"] - p["along"]) < 800 for p in picked): continue
        picked.append(c); used[k] = used.get(k, 0) + 1
        if len(picked) >= max_pins: break
    return sorted(picked, key=lambda c: c["along"])

def to_row(c):
    t = c["tags"]; name = t.get("name:en") or t.get("name")
    title = name or c["kind"]
    if c["kind"] == "Parking" and name: title = f"Parking · {name}"
    note = None
    if t.get("ele"):
        try: note = f"{int(float(str(t['ele']).replace(',', '.').split()[0])):,} m".replace(",", " ")
        except Exception: pass
    return {"lat": round(c["lat"], 6), "lng": round(c["lon"], 6), "category": c["cat"], "title": title, "note": note, "_osm": c["osm"]}
