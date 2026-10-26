"""Official OSM API v0.6 client (api.openstreetmap.org) — used because public
Overpass instances were down. Same OpenStreetMap data, different door.
Cached on disk. Polite: 1 req/s, real User-Agent."""
import hashlib, json, os, time, requests

UA = {"User-Agent": "NomadSeedRoutes/1.0 (contact: illyakovaliuk@gmail.com)"}
CACHE = os.path.join(os.path.dirname(__file__), "cache")
BASE = "https://api.openstreetmap.org/api/0.6"

def _get(url, params=None, retries=8):
    key = hashlib.sha1((url + json.dumps(params or {}, sort_keys=True)).encode()).hexdigest()
    path = os.path.join(CACHE, "api_" + key + ".json")
    if os.path.exists(path): return json.load(open(path))
    for i in range(retries):
        r = requests.get(url, params=params, headers=UA, timeout=120)
        if r.status_code == 200:
            data = r.json(); json.dump(data, open(path, "w")); time.sleep(1.0); return data
        if r.status_code == 400 and "too many nodes" in r.text.lower() or r.status_code == 400:
            raise ValueError(f"400 {r.text[:120]}")
        time.sleep(90 if r.status_code in (429, 509, 503) else 4*(i+1))
    raise RuntimeError(f"OSM API {url} -> {r.status_code}")

def relation_full(rid, skip_roles=(), depth=0):
    d = _get(f"{BASE}/relation/{rid}/full.json")["elements"]
    nodes = {e["id"]: (e["lat"], e["lon"]) for e in d if e["type"] == "node"}
    ways = {e["id"]: e for e in d if e["type"] == "way"}
    rel = next(e for e in d if e["type"] == "relation" and e["id"] == rid)
    out = []
    for m in rel["members"]:
        if m["type"] == "relation" and depth < 2 and m.get("role", "") not in skip_roles:
            _, sub = relation_full(m["ref"], skip_roles, depth+1); out += sub; continue
        if m["type"] != "way" or m["ref"] not in ways: continue
        if m.get("role", "") in skip_roles: continue
        w = ways[m["ref"]]
        out.append({"id": w["id"], "geom": [nodes[n] for n in w["nodes"] if n in nodes], "tags": w.get("tags", {})})
    return rel.get("tags", {}), out

def way_full(wid):
    d = _get(f"{BASE}/way/{wid}/full.json")["elements"]
    nodes = {e["id"]: (e["lat"], e["lon"]) for e in d if e["type"] == "node"}
    w = next(e for e in d if e["type"] == "way")
    return {"id": w["id"], "geom": [nodes[n] for n in w["nodes"]], "tags": w.get("tags", {})}

def map_bbox(s, w, n, e, depth=0):
    """All elements in bbox; subdivides if the API refuses (>50k nodes / >0.25 deg²)."""
    try:
        return _get(f"{BASE}/map.json", {"bbox": f"{w:.5f},{s:.5f},{e:.5f},{n:.5f}"})["elements"]
    except ValueError:
        if depth > 3: raise
        ms, mw = (s+n)/2, (w+e)/2
        out = []
        for a in ((s, w, ms, mw), (s, mw, ms, e), (ms, w, n, mw), (ms, mw, n, e)):
            out += map_bbox(*a, depth=depth+1)
        return out

def search_relations(query):
    r = requests.get("https://hiking.waymarkedtrails.org/api/v1/list/search", params={"query": query}, headers=UA, timeout=60)
    return r.json().get("results", [])

def ways_by_tag(bbox, tag_pred, tile=(0.25, 0.5)):
    """Scan a large bbox in API-sized tiles and return ways whose tags satisfy
    tag_pred(tags), with geometry (used when Overpass is unavailable)."""
    s, w, n, e = bbox; out = {}
    la = s
    while la < n:
        lo = w
        while lo < e:
            els = map_bbox(la, lo, min(la+tile[0], n), min(lo+tile[1], e))
            nodes = {x["id"]: (x["lat"], x["lon"]) for x in els if x["type"] == "node"}
            for x in els:
                if x["type"] == "way" and tag_pred(x.get("tags", {})):
                    if x["id"] not in out:
                        out[x["id"]] = {"id": x["id"], "tags": x["tags"], "nids": x["nodes"]}
                    out[x["id"]].setdefault("nodes_geo", {}).update({i: nodes[i] for i in x["nodes"] if i in nodes})
            lo += tile[1]
        la += tile[0]
    res = []
    for w_ in out.values():
        geom = [w_["nodes_geo"][i] for i in w_["nids"] if i in w_["nodes_geo"]]
        if len(geom) >= 2: res.append({"id": w_["id"], "geom": geom, "tags": w_["tags"]})
    return res
