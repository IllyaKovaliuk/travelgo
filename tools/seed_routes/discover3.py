import sys
from osm import query
def show(label, ql):
    print("==", label, flush=True)
    try:
        for r in query(ql)["elements"]:
            t=r.get("tags",{})
            print(" ",r["type"][0],r["id"],"|",t.get("route") or t.get("highway"),"|",t.get("name"),"|",t.get("ref",""),"|",t.get("distance",""),"|",t.get("sac_scale",""),t.get("tracktype",""),flush=True)
    except Exception as e: print("  ERR",e,flush=True)
Q=lambda body: '[out:json][timeout:90];'+body
which=sys.argv[1:]
J={
"canoe_de": lambda: show("canoe DE/AT/CZ", Q('relation["type"="route"]["route"="canoe"](47,8,51,15);out tags;')),
"canoe_fr": lambda: show("canoe FR/ES/UK", Q('relation["type"="route"]["route"="canoe"](42,-5,51,8);out tags;')),
"canoe_n": lambda: show("canoe Nordic/PL/UA", Q('relation["type"="route"]["route"="canoe"](50,14,62,35);out tags;')),
"canoe_us": lambda: show("canoe US/CA", Q('relation["type"="route"]["route"="canoe"](25,-125,50,-65);out tags;')),
"ridge": lambda: show("chornohora names", Q('relation["type"="route"]["route"="hiking"]["name"~"хребет|Піп Іван|Бребенескул|Шпиці|Смотрич|Чорногір|Брескул|Козьмещик",i](47.9,24.2,48.3,24.9);out tags;')),
"tatra2": lambda: show("tatras more", Q('relation["type"="route"]["route"="hiking"]["name"~"Palenica|Rysy|Morskie|Giewont|Strążysk|Hala Gąsienicowa|Kuźnice",i](49.1,19.7,49.35,20.2);out tags;')),
"dolo2": lambda: show("tre cime", Q('relation["type"="route"]["route"="hiking"]["ref"~"^(101|102|104|105|106|107|108)$"](46.55,12.1,46.7,12.4);out tags;')),
"dolo3": lambda: show("dolo names", Q('relation["type"="route"]["route"="hiking"]["name"~"Tre Cime|Drei Zinnen|Lavaredo|Seceda|Puez|Lagazuoi|Cinque Torri|Pale di San Martino|Brenta",i](46.2,10.7,46.9,12.5);out tags;')),
"jordan": lambda: show("jordan", Q('relation["type"="route"]["route"="hiking"]["name"~"Jordan Trail|Wadi Rum|Rum",i](29,34.8,31.5,36.6);out tags;')),
"bard": lambda: show("bardenas", Q('relation["type"="route"]["route"~"hiking|bicycle|mtb|foot"]["name"~"Bardenas|Vía Verde|Camino Natural",i](41.8,-2,42.5,-1);out tags;')),
"ice": lambda: show("iceland F", Q('way["highway"="track"]["ref"~"^F"](63,-25,67,-12);out tags 60;')),
"ice2": lambda: show("iceland rel", Q('relation["type"="route"]["route"~"hiking|bicycle|mtb|4wd_only|road"]["name"~"Laugavegur|F26|Sprengisandur|Kjölur|F35|Fjallabak",i](63,-25,67,-12);out tags;')),
"karp4": lambda: show("karp 4wd", Q('way["highway"="track"]["4wd_only"~"yes|recommended"](47.5,22,49.2,26);out tags 40;')),
"balk": lambda: show("balkan routes", Q('relation["type"="route"]["route"~"hiking|mtb|bicycle"]["name"~"Via Dinarica|Dinarica|Transbalkan|Peaks of the Balkans|Durmitor|Prokletije",i](41,17,45,22);out tags;')),
}
for k in (which or J): J[k]()
