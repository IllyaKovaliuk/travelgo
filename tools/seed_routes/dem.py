"""Elevation from a real DEM: Open-Meteo elevation API (Copernicus GLO-90,
~90 m resolution). Samples every ~step_m along the track, caches results."""
import json, os, hashlib, time, requests
from geo import resample, cumdist, hav

CACHE = os.path.join(os.path.dirname(__file__), "cache")

def elevations(points):
    out = []
    for i in range(0, len(points), 100):
        chunk = points[i:i+100]
        lat = ",".join(f"{p[0]:.5f}" for p in chunk); lon = ",".join(f"{p[1]:.5f}" for p in chunk)
        key = hashlib.sha1((lat+"|"+lon).encode()).hexdigest()
        path = os.path.join(CACHE, "dem_"+key+".json")
        if os.path.exists(path):
            vals = json.load(open(path))
        else:
            for attempt in range(8):
                r = requests.get("https://api.open-meteo.com/v1/elevation", params={"latitude": lat, "longitude": lon},
                                 headers={"User-Agent": "NomadSeedRoutes/1.0"}, timeout=60)
                if r.status_code == 200:
                    vals = r.json()["elevation"]; json.dump(vals, open(path, "w")); break
                time.sleep(65 if r.status_code == 429 else 3*(attempt+1))
            else:
                raise RuntimeError(f"elevation API failed: {r.status_code} {r.text[:200]}")
            time.sleep(0.4)
        out.extend(vals)
    return out

def profile(line, step_m=100.0):
    from geo import length
    step_m = max(step_m, length(line)/600)      # <=600 samples per route (API rate limit)
    pts = resample(line, step_m)
    el = elevations(pts)
    # light smoothing (3-pt moving avg) — DEM is 90 m grid, so single-sample noise is expected
    sm = [el[0]] + [(el[i-1]+el[i]+el[i+1])/3 for i in range(1, len(el)-1)] + [el[-1]]
    asc = desc = 0.0; ref = sm[0]
    TH = 8.0   # hysteresis (m): ignore wiggles below DEM noise
    for e in sm[1:]:
        if e - ref >= TH: asc += e - ref; ref = e
        elif ref - e >= TH: desc += ref - e; ref = e
    return {"pts": pts, "elev": sm, "ascent": asc, "descent": desc, "high": max(sm), "low": min(sm)}
