"""The 12 candidate routes. Every geometry comes from OSM ids listed here."""
CARP_BB = (47.9, 24.2, 48.9, 24.9)
from descriptions import D
SPECS = [
 # ── Ukrainian Carpathians ──
 {"slug": "hoverla-zaroslyak", "title": "Hoverla\nfrom Zaroslyak", "place": "CARPATHIANS, UKRAINE", "mode": "foot", "relations": [10330801], "transport_label": "FOOT"},
 {"slug": "pip-ivan-shybene", "title": "Pip Ivan\nfrom Shybene", "place": "CHORNOHORA, UKRAINE", "mode": "foot", "relations": [10355026], "transport_label": "FOOT"},
 {"slug": "petros-yasinia", "title": "Petros ridge\nLazeshchyna to Yasinia", "place": "CHORNOHORA, UKRAINE", "mode": "foot", "relations": [8613349], "transport_label": "FOOT", "orient": "none"},
 {"slug": "synevyr-lopushne", "title": "Lopushne to\nSynevyr", "place": "SYNEVYR, UKRAINE", "mode": "foot", "relations": [7622529], "transport_label": "FOOT", "orient": "none"},
 # ── Tatras ──
 {"slug": "rysy-palenica", "title": "Rysy\nfrom Palenica Białczańska", "place": "TATRAS, POLAND", "mode": "foot", "relations": [1594931], "transport_label": "FOOT"},
 # ── Dolomites ──
 {"slug": "odle-munkelweg", "title": "Adolf Munkel Weg\nunder the Odle", "place": "DOLOMITES, ITALY", "mode": "foot", "relations": [2442695], "transport_label": "FOOT"},
 {"slug": "av1-fanes-nuvolau", "title": "Alta Via 1\nFanes to Nuvolau", "place": "DOLOMITES, ITALY", "mode": "foot", "relations": [177743],
  "orient": "none", "clip": [("Rifugio Fanes", (46.5, 11.9, 46.7, 12.1)), ("Rifugio Nuvolau", (46.45, 12.0, 46.6, 12.15))], "transport_label": "FOOT"},
 # ── Desert ──
 {"slug": "ramon-crater", "title": "Makhtesh Ramon\nKarne Ramon to Arod", "place": "NEGEV DESERT, ISRAEL", "mode": "foot", "relations": [6148296],
  "orient": "none", "clip": [("Karne Ramon", (30.3, 34.5, 30.9, 35.1)), ("Arod", (30.3, 34.5, 30.9, 35.1))], "transport_label": "FOOT"},
 # ── 4x4 / overland ──
 {"slug": "sprengisandur-f26", "title": "Sprengisandur\nF26 across the highlands", "place": "ICELAND", "mode": "overland", "scan": {"ref": "F26", "bbox": (63.9, -19.6, 65.5, -17.2)}, "transport_label": "4×4", "speed_kmh": 25},
 {"slug": "kjolur-f35", "title": "Kjölur\nF35 between the glaciers", "place": "ICELAND", "mode": "overland", "scan": {"ref": "35", "name": "Kjalvegur", "bbox": (63.8, -20.6, 65.0, -19.0)}, "transport_label": "4×4", "speed_kmh": 25},
 # ── Bike ──
 {"slug": "donau-moldau-radweg", "title": "Danube–Moldau\ncycle route", "place": "BAVARIAN FOREST, GERMANY", "mode": "bike", "relations": [273702], "transport_label": "BIKE", "orient": "high"},
 # ── Water ──
 {"slug": "vltava-krumlov", "title": "Vltava\nVyšší Brod to Český Krumlov", "place": "SOUTH BOHEMIA, CZECHIA", "mode": "water", "relations": [1730536],
  "orient": "none", "clip": [("^Vyšší Brod$", (48.55, 14.2, 48.7, 14.4)), ("^Český Krumlov$", (48.75, 14.2, 48.9, 14.45))], "anchor_tol_m": 1500, "use_ways": [123694304], "transport_label": "KAYAK", "speed_kmh": 5},
]
for _s in SPECS: _s['description'] = D[_s['slug']]
