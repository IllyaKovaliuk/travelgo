import json, glob, os
from routes import SPECS
rows=[]; allsrc={}
for sp in SPECS:
    r=json.load(open(f"out/{sp['slug']}.json")); s=json.load(open(f"out/{sp['slug']}.sources.json")); rt=r["route"]
    allsrc[sp["slug"]]={k:v for k,v in s.items() if k not in("line_full",)}
    rows.append((sp,r,s))
    print(f'\n## {sp["slug"]} — {rt["title"]!r} | {rt["place"]}')
    print(f'  {rt["distance_km"]} km, +{rt["ascent_m"]} m, high {rt["high_point_m"]} m (min {s["min_elev"]}), {rt["difficulty"].upper()} — {s["difficulty_reason"]}, duration {rt["duration"]}')
    print("  OSM:", ", ".join(s["osm"]), "| pins:", len(r["pois"]), "| segs:", [(g["name"],g["distance_km"]) for g in r["segments"]][:6])
    print("  pins:", [(p["category"],p["title"],p["note"]) for p in r["pois"]])
    print("  warn:", [w for w in s["warnings"] if "protected" not in w])
json.dump(allsrc,open("sources.json","w"),ensure_ascii=False,indent=1)
