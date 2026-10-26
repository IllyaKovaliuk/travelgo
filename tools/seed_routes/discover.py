"""Step 0: find REAL candidate OSM relations/ways per idea (no geometry yet)."""
import sys, json
from osm import query

def rels(name_re, bbox, kinds="hiking|bicycle|mtb|canoe|foot|horse|4wd_only|mtb"):
    s,w,n,e = bbox
    ql = f'''[out:json][timeout:120];
relation["type"="route"]["route"~"^({kinds})$"]["name"~"{name_re}",i]({s},{w},{n},{e});
out tags;'''
    return query(ql)["elements"]

IDEAS = {
 "hoverla":  ("Говерл|Hoverla|Заросляк", (48.0,24.3,48.3,24.7)),
 "chornohora":("Чорногір|Chornohora|Піп Іван", (48.0,24.3,48.3,24.8)),
 "petros":   ("Петрос|Petros", (48.0,24.3,48.3,24.8)),
 "gorgany":  ("Горгани|Gorgany|Синевир|Synevyr|Сивуля|Syvulia|Довбушанка", (48.2,23.7,48.8,24.7)),
 "tatras":   ("Rysy|Orla|Morskie|Zawrat|Kasprowy|Giewont|Kościeliska|Dolina", (49.0,19.6,49.4,20.4)),
 "dolomites":("Alta Via|Tre Cime|Drei Zinnen|Lavaredo|Seceda|Odle|Sella|Lagazuoi", (46.2,11.5,46.8,12.5)),
 "desert":   ("Wadi Rum|Jordan Trail|Bardenas", (29.3,35.2,30.0,35.8)),
 "bike":     ("EuroVelo|Donauradweg|Danube|Eurovelo", (47.5,9.0,49.5,14.0)),
 "canoe":    ("canoe|kayak|Kanu|Paddel|Sava|Ticino|Lot|Vltava|Moldau", (48.0,13.0,49.5,15.5)),
}
if __name__ == "__main__":
    for k,(re_,bb) in IDEAS.items():
        if len(sys.argv)>1 and k not in sys.argv[1:]: continue
        print("==",k)
        try:
            for r in rels(re_,bb):
                t=r["tags"]
                print(" ",r["id"],t.get("route"),"|",t.get("name"),"|",t.get("ref",""),"|",t.get("sac_scale",""),t.get("distance",""),t.get("network",""))
        except Exception as ex: print("  ERR",ex)
