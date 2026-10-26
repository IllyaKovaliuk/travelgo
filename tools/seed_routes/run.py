import sys, json, traceback
from build import build
from preview import render
from routes import SPECS
only = sys.argv[1:]
for spec in SPECS:
    if only and spec["slug"] not in only: continue
    print("▶", spec["slug"], flush=True)
    try:
        res, src = build(spec)
        render(res, src, f"previews/{spec['slug']}.png")
        r = res["route"]
        print(f'   OK {r["distance_km"]} km +{r["ascent_m"]} m max {r["high_point_m"]} {r["difficulty"]} pins={len(res["pois"])} segs={len(res["segments"])} warn={src["warnings"]}', flush=True)
    except Exception as e:
        print("   FAIL:", type(e).__name__, str(e)[:300], flush=True)
