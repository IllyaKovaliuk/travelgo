"""Fetch -> stitch -> (clip) -> DEM -> classify -> POIs -> JSON for one route spec."""
import json, math, os, sys, datetime
import osmapi
from osm import query
from geo import stitch, StitchError, length, cumdist, simplify, hav, project, dist_point_to_line_m
import dem, classify, pois

OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)
SKIP_ROLES = {"alternative", "alternate", "excursion", "approach", "variant"}
HIKE_SPEED_KMH, CLIMB_M_H = 4.5, 500.0

def fetch_relation(rid):
    return osmapi.relation_full(rid, SKIP_ROLES)

def fetch_ways(way_ids):
    return [osmapi.way_full(i) for i in way_ids]

def nearest_idx(line, pt):
    return min(range(len(line)), key=lambda i: hav(line[i], pt))

def find_named(name_re, bbox):
    import re
    s_, w, n, e = bbox
    rx = re.compile(name_re, re.I)
    els = osmapi.map_bbox(s_, w, n, e)
    nodes = {x["id"]: (x["lat"], x["lon"]) for x in els if x["type"] == "node"}
    for el in els:
        t = el.get("tags", {})
        if not (rx.search(t.get("name", "") or "") or rx.search(t.get("name:en", "") or "")): continue
        if not (t.get("tourism") or t.get("natural") or t.get("place") or t.get("amenity")): continue
        if el["type"] == "node": return (el["lat"], el["lon"]), t.get("name")
        if el["type"] == "way":
            pts = [nodes[i] for i in el.get("nodes", []) if i in nodes]
            if pts: return (sum(p[0] for p in pts)/len(pts), sum(p[1] for p in pts)/len(pts)), t.get("name")
    raise RuntimeError(f"anchor '{name_re}' not found in OSM bbox")

def protected_area(line):
    """is_in needs Overpass; try it, but never block the build on it."""
    mid = line[len(line)//2]
    try:
        els = query(f'[out:json][timeout:40];is_in({mid[0]},{mid[1]})->.a;(rel(pivot.a)["boundary"~"^(national_park|protected_area)$"];way(pivot.a)["boundary"~"^(national_park|protected_area)$"];);out tags;', retries=1, timeout=15)["elements"]
    except Exception:
        return None
    names = []
    for e in els:
        t = e.get("tags", {}); nm = t.get("name:en") or t.get("name")
        if nm and nm not in names: names.append(nm)
    return names

def fmt_duration(h):
    hh = max(1, round(h*2)/2)
    return "HALF DAY" if hh <= 5 and h >= 3 else (f"{hh:g} H" if hh < 3 else (f"{hh:g} H" if hh <= 9 else f"{math.ceil(hh/8)} DAYS"))

def build(spec):
    warnings = []
    ways = []; rel_tags_all = []
    if spec.get("relations"):
        for rid in spec["relations"]:
            t, w = fetch_relation(rid); rel_tags_all.append(t); ways += w
    if spec.get("way_ids"): ways += fetch_ways(spec["way_ids"])
    if spec.get("scan"):
        ref = spec["scan"]["ref"]
        ways += osmapi.ways_by_tag(spec["scan"]["bbox"], lambda t: t.get("highway") and ref in t.get("ref", "").split(";") and (not spec["scan"].get("name") or t.get("name") == spec["scan"]["name"]))
    if spec.get("use_ways"):
        ways = [w for w in ways if w["id"] in spec["use_ways"]]
        if not ways: raise RuntimeError("use_ways ids not found among relation members")
    if spec.get("way_bbox"):
        s_, w_, n_, e_ = spec["way_bbox"]
        ways = [w for w in ways if any(s_ <= p[0] <= n_ and w_ <= p[1] <= e_ for p in w["geom"])
                and (not spec.get("only_tags") or all(w["tags"].get(k) == v for k, v in spec["only_tags"].items()))]
    line, owners = stitch(ways, tol_m=spec.get("tol_m", 25))
    if spec.get("clip"):
        a, an = find_named(*spec["clip"][0]); b, bn = find_named(*spec["clip"][1])
        tol = spec.get("anchor_tol_m", 250)
        ia, ib = nearest_idx(line, a), nearest_idx(line, b)
        for nm_, pt_, ix_ in ((an, a, ia), (bn, b, ib)):
            if hav(line[ix_], pt_) > tol: raise classify.ValidationError(f"clip anchor '{nm_}' is {hav(line[ix_], pt_):.0f} m from the track (> {tol} m)")
        i, j = sorted((ia, ib))
        if i == j: raise RuntimeError("clip anchors resolve to the same vertex")
        line, owners = line[i:j+1], owners[i:j+1]
        if ia > ib: line, owners = line[::-1], owners[::-1]      # keep anchor order A -> B
        warnings.append(f"clipped between OSM features '{an}' and '{bn}'")
    if spec.get("reverse"): line, owners = line[::-1], owners[::-1]
    # Orientation: one-way mountain routes start at the LOW end (so ascent/descent read right),
    # rivers/downhill routes start at the HIGH end (downstream). Loops (ends <300 m apart) untouched.
    orient = spec.get("orient", "low" if spec["mode"] == "foot" else "none")
    if orient != "none" and hav(line[0], line[-1]) > 300:
        e0, e1 = dem.elevations([line[0], line[-1]])
        if (orient == "low" and e0 > e1 + 40) or (orient == "high" and e1 > e0 + 40):
            line, owners = line[::-1], owners[::-1]; warnings.append(f"reversed to start at the {orient} end ({e0:.0f} m / {e1:.0f} m)")
    km = length(line)/1000
    mode = spec["mode"]
    for t_ in rel_tags_all:
        try:
            dtag = float(str(t_.get("distance", "")).replace(",", ".").split()[0])
        except Exception: dtag = None
        if dtag and not spec.get("clip") and not (0.75 <= km/dtag <= 1.35):
            if spec.get("accept_distance_mismatch"): warnings.append(f"OSM distance tag {dtag} km vs geometry {km:.1f} km")
            else: raise classify.ValidationError(f"geometry {km:.1f} km vs OSM distance tag {dtag} km — mismatch, refusing")
    prof = dem.profile(line)
    # -- segments (validated against way tags)
    segs = []
    for k in range(len(line)-1):
        w = owners[k+1]; tr, label = classify.classify_way(w["tags"], mode)
        d = hav(line[k], line[k+1])
        if segs and segs[-1]["transport"] == tr and segs[-1]["label"] == label: segs[-1]["m"] += d
        else: segs.append({"transport": tr, "label": label, "m": d, "names": {}})
        nm = w["tags"].get("name") or w["tags"].get("ref")
        if nm: segs[-1]["names"][nm] = segs[-1]["names"].get(nm, 0) + d
    merged = []
    for s in segs:                       # absorb <250 m slivers into neighbour
        if merged and s["m"] < 250: merged[-1]["m"] += s["m"]
        else: merged.append(s)
    while len(merged) > 12:
        i = min(range(len(merged)), key=lambda x: merged[x]["m"])
        j = i-1 if i else 1
        merged[j]["m"] += merged[i]["m"]; merged.pop(i)
    seg_rows = []
    T = {"foot": ("figure.hiking", "#5FA777"), "overland": ("car.side", "#E8743B"), "water": ("water.waves", "#3E92CC"),
         "climb": ("mountain.2.fill", "#7A5FBF"), "bike": ("bicycle", "#E0A458")}
    for s in merged:
        nm = max(s["names"], key=s["names"].get) if s["names"] else None
        name = f'{s["label"]} · {nm}' if nm and s["names"][nm] > 0.5*s["m"] else s["label"]
        seg_rows.append({"icon": T[s["transport"]][0], "name": name[:60], "distance_km": round(s["m"]/1000, 2), "tint": T[s["transport"]][1], "_transport": s["transport"]})
    # distance consistency check
    dsum = sum(r["distance_km"] for r in seg_rows)
    if abs(dsum - km) > max(0.3, 0.02*km): raise classify.ValidationError(f"segment sum {dsum:.2f} != track {km:.2f}")
    tags_list = [w["tags"] for w in {id(o): o for o in owners}.values()]
    has_vf = any(r["_transport"] == "climb" for r in seg_rows)
    diff, reason = classify.difficulty(mode, tags_list, km, prof["ascent"], has_vf)
    # -- pins
    cands = pois.find(line); picks = pois.select(cands, line)
    pin_rows = [pois.to_row(c) for c in picks]
    # -- track points (real vertices only, simplified), with a hard check that start/end are preserved
    idx = simplify(line, 4.0, 700)
    track = [{"lat": round(line[i][0], 6), "lng": round(line[i][1], 6)} for i in idx]
    # -- elevation profile: 40 normalized samples + peak label
    el = prof["elev"]; n = 40
    samp = [el[min(len(el)-1, round(i*(len(el)-1)/(n-1)))] for i in range(n)]
    lo, hi = min(samp), max(samp)
    norm = [round((v-lo)/(hi-lo), 3) if hi > lo else 0.5 for v in samp]
    prot = protected_area(line)
    if prot is None: prot = []; warnings.append("protected-area lookup unavailable (Overpass down) — check manually")
    speed = spec.get("speed_kmh") or {"foot": 0, "bike": 15, "overland": 25, "water": 4}[mode]
    hours = (km/HIKE_SPEED_KMH + prof["ascent"]/CLIMB_M_H) if mode == "foot" else km/speed
    ids = [f"relation/{r}" for r in spec.get("relations", [])] + [f"way/{w}" for w in spec.get("way_ids", [])]
    used_ways = sorted({o["id"] for o in owners})
    if spec.get("scan"): ids += [f"way/{w}" for w in used_ways]
    if spec.get("use_ways"): ids = [f"relation/{r}" for r in spec["relations"]] + [f"way/{w}" for w in used_ways]
    if spec.get("scan"): foot = f'OSM ways with ref {spec["scan"]["ref"]} ({len(used_ways)} ways; ids in Nomad sources file)'
    else: foot = "OSM " + ", ".join(i for i in ids if i.startswith("relation/")) + (" (" + ", ".join(i for i in ids if i.startswith("way/")) + ")" if spec.get("use_ways") else "")
    desc_full = (spec.get("description", "").strip() + "\n\nRoute data © OpenStreetMap contributors (ODbL). " + foot + ".").strip()
    # OSM peak/pin elevations are surveyed values; the 90 m DEM smooths summits down.
    pin_el = []
    for c in picks:
        try: pin_el.append(float(str(c["tags"].get("ele", "")).replace(",", ".").split()[0]))
        except Exception: pass
    high = max([prof["high"]] + [e for e in pin_el if e <= prof["high"] + 120])
    route = {
        "title": spec["title"], "place": spec["place"], "difficulty": diff, "transport": ("climb" if has_vf and mode == "foot" and all(r["_transport"] == "climb" for r in seg_rows) else mode),
        "transport_label": spec["transport_label"], "distance_km": round(km, 2),
        "ascent_m": 0 if mode == "water" else int(round(prof["ascent"])), "high_point_m": int(round(high)),
        "duration": fmt_duration(hours), "season": spec.get("season"),
        "elevation_profile": norm, "elevation_peak_label": f'{int(round(high))} M',
        "coordinates": f'{line[0][0]:.4f}° N, {line[0][1]:.4f}° E' if line[0][0] >= 0 else f'{abs(line[0][0]):.4f}° S, {line[0][1]:.4f}° E',
        "track_points": track,
        "description": desc_full,
        "visibility": "public", "status": "published",
    }
    reqs = []
    if mode == "foot":
        sac = max((classify.SAC.get(t.get("sac_scale"), -1) for t in tags_list), default=-1)
        if sac >= 1: reqs.append({"icon": "shoeprints.fill", "title": "Sturdy hiking boots", "subtitle": "OSM rates part of this trail mountain hiking (SAC T2+) — steep, partly exposed ground.", "tint": "#5FA777"})
        if any(p["category"] == "water" for p in pin_rows): reqs.append({"icon": "drop.fill", "title": "Water on route", "subtitle": f'{sum(1 for p in pin_rows if p["category"]=="water")} mapped water point(s) near the track — treat before drinking.', "tint": "#3E92CC"})
        else: reqs.append({"icon": "drop.fill", "title": "Carry your water", "subtitle": "No mapped spring or drinking water within 150 m of the track.", "tint": "#3E92CC"})
    if mode == "overland": reqs.append({"icon": "car.side", "title": "High-clearance vehicle", "subtitle": "Unpaved track. Check current road/track conditions locally before driving.", "tint": "#E8743B"})
    if prot: reqs.append({"icon": "leaf.fill", "title": f"Protected area: {prot[0]}", "subtitle": "Route lies inside a mapped protected area — check local access rules and permits.", "tint": "#5FA777"})
    result = {"slug": spec["slug"], "route": route, "segments": [{k: v for k, v in r.items() if not k.startswith("_")} for r in seg_rows],
              "pois": [{k: v for k, v in p.items() if not k.startswith("_")} for p in pin_rows], "requirements": reqs}
    sources = {"slug": spec["slug"], "osm": ids, "osm_relation_names": [t.get("name") for t in rel_tags_all],
               "pins_osm": [p["_osm"] for p in pin_rows], "difficulty_reason": reason, "warnings": warnings,
               "dem": "Open-Meteo elevation API (Copernicus GLO-90), 100 m sampling, 3-pt smoothing, 8 m hysteresis",
               "duration_formula": "Naismith (4.5 km/h + 500 m/h ascent)" if mode == "foot" else f"{speed} km/h average",
               "protected": prot, "full_len_m": round(length(line)), "vertices_raw": len(line), "vertices_stored": len(track),
               "min_elev": round(prof["low"]), "cover": spec.get("cover"), "line_full": [[round(p[0], 6), round(p[1], 6)] for p in line[::max(1, len(line)//1500)]],
               "pin_osm_names": {p["_osm"]: p["title"] for p in pin_rows}, "seg_transports": [r["_transport"] for r in seg_rows]}
    json.dump(result, open(os.path.join(OUT, spec["slug"] + ".json"), "w"), ensure_ascii=False, indent=1)
    json.dump(sources, open(os.path.join(OUT, spec["slug"] + ".sources.json"), "w"), ensure_ascii=False, indent=1)
    return result, sources
