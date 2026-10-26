from osm import query
def show(ql, label):
    print("==", label)
    try:
        for r in query(ql)["elements"]:
            t=r.get("tags",{})
            print(" ",r["type"][0],r["id"],"|",t.get("route") or t.get("highway"),"|",t.get("name"),"|",t.get("ref",""),"|",t.get("distance",""),t.get("tracktype",""),t.get("4wd_only",""))
    except Exception as e: print("  ERR",e)

show('[out:json][timeout:120];relation["type"="route"]["route"="canoe"]["name"](44,-10,60,30);out tags;', "canoe Europe")
show('[out:json][timeout:120];relation["type"="route"]["route"~"hiking|foot"]["name"~"Bardenas|Wadi|Rum|Jordan Trail"](29,35,31,36);out tags;', "Wadi Rum area")
show('[out:json][timeout:120];relation["type"="route"]["route"~"hiking|bicycle|mtb|foot"]["name"~"Bardenas"](41.5,-2,42.5,-1);out tags;', "Bardenas")
show('[out:json][timeout:120];relation["type"="route"]["route"~"hiking|foot"]["name"~"Jordan Trail|Wadi Rum|Petra"](29,34.5,31.5,36.5);out tags;', "Jordan")
show('[out:json][timeout:120];way["highway"="track"]["ref"~"^F(26|35|88|910|208)$"](63,-25,67,-12);out tags;', "Iceland F")
