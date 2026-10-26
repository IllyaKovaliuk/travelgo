import sys, osmapi
from geo import stitch, length, StitchError
from build import SKIP_ROLES
for rid in map(int, sys.argv[1:]):
    try:
        t, ways = osmapi.relation_full(rid, SKIP_ROLES)
        try:
            line, _ = stitch(ways, 30); km = length(line)/1000; note = "ok"
        except StitchError as e: km, note = 0, "STITCH FAIL: "+str(e)[:70]
        sac = sorted({w["tags"].get("sac_scale","-") for w in ways})
        print(rid, "|", (t.get("name") or "")[:55], "|", t.get("ref",""), "|", f"{km:.1f} km", "|", len(ways), "ways", "|", sac, "|", note, flush=True)
    except Exception as e: print(rid, "ERR", str(e)[:100], flush=True)
