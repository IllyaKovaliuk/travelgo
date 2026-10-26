"""Merge out/*.json + cover choices -> final/<slug>.json, sources.json, summary.md."""
import json, os
from routes import SPECS
CHOICE = {"hoverla-zaroslyak":1,"pip-ivan-shybene":0,"petros-yasinia":0,"synevyr-lopushne":1,"rysy-palenica":5,"odle-munkelweg":0,
          "av1-fanes-nuvolau":3,"ramon-crater":0,"sprengisandur-f26":3,"kjolur-f35":3,"vltava-krumlov":3}   # donau-moldau-radweg: none
cands = json.load(open("cover_candidates.json"))
allsrc, rows = {}, []
for sp in SPECS:
    slug = sp["slug"]; res = json.load(open(f"out/{slug}.json")); src = json.load(open(f"out/{slug}.sources.json"))
    cover = None
    if slug in CHOICE:
        x = cands[slug][CHOICE[slug]]
        cover = {"title": x["title"], "author": x["author"], "license": x["license"], "page": x["page"], "file": x["file"]}
        res["route"]["description"] += f'\nCover photo: {x["author"]} / {x["license"]} / Wikimedia Commons.'
    res["cover"] = cover
    json.dump(res, open(f"final/{slug}.json", "w"), ensure_ascii=False, indent=1)
    s2 = {k: v for k, v in src.items() if k != "line_full"}; s2["cover"] = cover; allsrc[slug] = s2
    rt = res["route"]
    rows.append(f'| {slug} | {rt["place"].title()} | {rt["transport_label"]} | {rt["distance_km"]} | +{rt["ascent_m"]} | {rt["high_point_m"]} | **{rt["difficulty"].upper()}** — {src["difficulty_reason"]} | {", ".join(src["osm"][:2]) + (" …" if len(src["osm"])>2 else "")} | {len(res["pois"])} | {"; ".join(w for w in src["warnings"] if "protected" not in w) or "—"} | {"✓" if cover else "**none**"} |')
json.dump(allsrc, open("sources.json", "w"), ensure_ascii=False, indent=1)
hdr = "| route | region | mode | km | ascent m | high m | difficulty (reason) | OSM ids | pins | warnings | cover |\n|---|---|---|---|---|---|---|---|---|---|---|\n"
open("summary.md", "w").write("# Nomad Curated — candidate routes\n\n" + hdr + "\n".join(rows) + "\n\nProtected-area lookup (Overpass) was unavailable: permits/protected-area requirements NOT added yet.\n")
print(open("summary.md").read())
