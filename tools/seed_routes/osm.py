"""Overpass client with on-disk cache and a real User-Agent (the public
instances return 406 without one). Every query result is cached by hash so
re-runs don't hammer the server and results stay reproducible for audit."""
import hashlib, json, os, time, requests

ENDPOINTS = ["https://overpass-api.de/api/interpreter",
             "https://overpass.private.coffee/api/interpreter",
             "https://overpass.kumi.systems/api/interpreter",
             "https://maps.mail.ru/osm/tools/overpass/api/interpreter"]
UA = {"User-Agent": "NomadSeedRoutes/1.0 (contact: illyakovaliuk@gmail.com)"}
CACHE = os.path.join(os.path.dirname(__file__), "cache")

def query(ql: str, retries: int = 8, timeout: int = 100):
    key = hashlib.sha1(ql.encode()).hexdigest()
    path = os.path.join(CACHE, key + ".json")
    if os.path.exists(path):
        return json.load(open(path))
    last = None
    for i in range(retries):
        ep = ENDPOINTS[i % len(ENDPOINTS)]
        try:
            r = requests.post(ep, data={"data": ql}, headers=UA, timeout=timeout)
            if r.status_code == 200:
                data = r.json()
                json.dump(data, open(path, "w"))
                time.sleep(1.5)
                return data
            last = f"{ep} -> {r.status_code}"
        except Exception as e:
            last = f"{ep} -> {e}"
        time.sleep(3)
    raise RuntimeError(f"Overpass failed: {last}")
