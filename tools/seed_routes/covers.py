"""Cover candidates from Wikimedia Commons ONLY, with licence/author/URL for attribution.
Allowed: CC0, PD, CC BY, CC BY-SA (commercial use OK). Rejected: NC/ND/unknown/non-free."""
import json, re, sys, time, requests, html
UA = {"User-Agent": "NomadSeedRoutes/1.0 (contact: illyakovaliuk@gmail.com)"}
API = "https://commons.wikimedia.org/w/api.php"
OK = re.compile(r"^(cc0|pd|public domain|cc[- ]by(-sa)?[- ]\d|cc[- ]by[- ]\d)", re.I)
QUERIES = {
 "hoverla-zaroslyak": ["Hoverla Zaroslyak trail", "Hoverla summit Carpathians"],
 "pip-ivan-shybene": ["Pip Ivan Chornohirskyi", "Pip Ivan Chornohora"],
 "petros-yasinia": ["Petros mountain Chornohora", "Petros Carpathians summit"],
 "synevyr-lopushne": ["Synevyr lake", "Synevyr Carpathians"],
 "rysy-palenica": ["Rysy summit Tatras", "Rysy Czarny Staw"],
 "odle-munkelweg": ["Adolf Munkel Weg", "Odle Geisler Villnöss Munkelweg"],
 "av1-fanes-nuvolau": ["Rifugio Nuvolau", "Rifugio Averau Nuvolau Dolomites"],
 "ramon-crater": ["Makhtesh Ramon crater", "Ramon crater Mitzpe Ramon view"],
 "sprengisandur-f26": ["Sprengisandur highlands", "Sprengisandur F26 road"],
 "kjolur-f35": ["Kjölur highlands Iceland", "Kjalvegur Langjökull"],
 "donau-moldau-radweg": ["Donau-Moldau-Radweg", "Bavarian Forest cycling Haidmühle"],
 "vltava-krumlov": ["Vltava Český Krumlov canoe", "Vltava river Rožmberk"],
}
def search(q):
    r = requests.get(API, params={"action": "query", "format": "json", "generator": "search", "gsrnamespace": 6, "gsrsearch": q + " filetype:bitmap",
                                  "gsrlimit": 12, "prop": "imageinfo", "iiprop": "url|extmetadata|size|mime", "iiurlwidth": 900}, headers=UA, timeout=60).json()
    time.sleep(1)
    out = []
    for p in (r.get("query", {}).get("pages", {}) or {}).values():
        ii = (p.get("imageinfo") or [{}])[0]; md = ii.get("extmetadata", {})
        lic = md.get("LicenseShortName", {}).get("value", "")
        if not OK.match(lic.strip()) or md.get("NonFree", {}).get("value") == "true": continue
        if ii.get("width", 0) < 1600 or ii.get("height", 0) < 900 or ii.get("mime") not in ("image/jpeg", "image/png"): continue
        author = re.sub(r"<[^>]+>", "", md.get("Artist", {}).get("value", "")).strip()
        out.append({"title": p["title"], "license": lic, "author": html.unescape(author)[:120], "page": ii.get("descriptionurl"),
                    "file": ii.get("url"), "thumb": ii.get("thumburl"), "w": ii["width"], "h": ii["height"], "q": q})
    return out
if __name__ == "__main__":
    res = {}
    for slug, qs in QUERIES.items():
        seen, c = set(), []
        for q in qs:
            for x in search(q):
                if x["title"] not in seen: seen.add(x["title"]); c.append(x)
        res[slug] = c[:6]; print(slug, len(c), [x["title"][:50] for x in c[:3]], flush=True)
    json.dump(res, open("cover_candidates.json", "w"), ensure_ascii=False, indent=1)
