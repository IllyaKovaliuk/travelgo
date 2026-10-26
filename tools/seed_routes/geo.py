"""Pure-python geodesy + stitching of OSM ways into one ordered line.
No invented geometry: every output vertex is a vertex of a real OSM way."""
import math

R = 6371008.8

def hav(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    d = math.sin((la2-la1)/2)**2 + math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2
    return 2*R*math.asin(math.sqrt(d))

def length(line):
    return sum(hav(line[i], line[i+1]) for i in range(len(line)-1))

def cumdist(line):
    out = [0.0]
    for i in range(1, len(line)):
        out.append(out[-1] + hav(line[i-1], line[i]))
    return out

def key(p):
    return (round(p[0], 6), round(p[1], 6))

class StitchError(Exception):
    pass

def stitch(ways, tol_m=25.0):
    """ways: list of dicts {id, geom:[(lat,lon)...], tags}. Returns
    (line, owners) where owners[i] = way dict that vertex i came from.
    Strategy 1: chain in member order (flipping as needed).
    Strategy 2: graph walk (double-sweep shortest path) for unordered relations.
    Raises StitchError loudly if a gap > tol_m or the chain drops >15% of ways."""
    ways = [w for w in ways if len(w["geom"]) >= 2]
    if not ways:
        raise StitchError("no way geometry")
    chain = _chain_in_order(ways, tol_m)
    if chain is not None:
        return chain
    return _graph_path(ways, tol_m)

def _chain_in_order(ways, tol):
    line, owners = [], []
    first = ways[0]
    # orient first way toward second
    if len(ways) > 1:
        a, b = ways[0]["geom"], ways[1]["geom"]
        best = min(((hav(x, y), i, j) for i, x in enumerate((a[0], a[-1])) for j, y in enumerate((b[0], b[-1]))))
        g = a if best[1] == 1 else a[::-1]
    else:
        g = first["geom"]
    line.extend(g); owners.extend([first]*len(g))
    for w in ways[1:]:
        g = w["geom"]
        d0, d1 = hav(line[-1], g[0]), hav(line[-1], g[-1])
        if min(d0, d1) > tol:
            return None
        if d1 < d0:
            g = g[::-1]
        start = 1 if hav(line[-1], g[0]) < 1.0 else 0
        line.extend(g[start:]); owners.extend([w]*len(g[start:]))
    return line, owners

def _graph_path(ways, tol):
    # nodes = snapped endpoints; edges = ways. Find the longest shortest-path
    # (double sweep) and require it to cover most of the total length.
    import heapq
    snap = {}
    def nid(p):
        return snap.setdefault(key(p), len(snap))      # OSM ways share exact node coordinates
    adj = {}
    for idx, w in enumerate(ways):
        a, b = nid(w["geom"][0]), nid(w["geom"][-1])
        L = length(w["geom"])
        adj.setdefault(a, []).append((b, L, idx, False))
        adj.setdefault(b, []).append((a, L, idx, True))
    def dijkstra(src):
        dist = {src: 0.0}; prev = {}; pq = [(0.0, src)]
        while pq:
            d, u = heapq.heappop(pq)
            if d > dist[u]: continue
            for v, L, idx, rev in adj.get(u, []):
                nd = d + L
                if nd < dist.get(v, 1e18):
                    dist[v] = nd; prev[v] = (u, idx, rev); heapq.heappush(pq, (nd, v))
        return dist, prev
    start = next(iter(adj))
    d, _ = dijkstra(start); a = max(d, key=d.get)
    d, prev = dijkstra(a); b = max(d, key=d.get)
    path, cur = [], b
    while cur != a:
        u, idx, rev = prev[cur]; path.append((idx, rev)); cur = u
    path.reverse()
    line, owners = [], []
    for idx, rev in path:
        g = ways[idx]["geom"]
        if rev: g = g[::-1]
        s = 1 if line else 0
        line.extend(g[s:]); owners.extend([ways[idx]]*len(g[s:]))
    total = sum(length(w["geom"]) for w in ways)
    cover = length(line) / total if total else 0
    if cover < 0.85:
        raise StitchError(f"graph path covers only {cover:.0%} of the relation's ways (branches/loops); needs manual member selection")
    return line, owners

def simplify(line, eps_m=4.0, keep_max=700):
    """Douglas–Peucker in local metres (subset of real vertices only)."""
    if len(line) < 3: return list(range(len(line)))
    lat0 = line[0][0]; kx = math.cos(math.radians(lat0)) * 111320; ky = 110540
    pts = [((p[1])*kx, p[0]*ky) for p in line]
    def dp(lo, hi, eps, out):
        stack = [(lo, hi)]
        while stack:
            lo, hi = stack.pop()
            ax, ay = pts[lo]; bx, by = pts[hi]
            dx, dy = bx-ax, by-ay; n = math.hypot(dx, dy) or 1e-9
            md, mi = -1, -1
            for i in range(lo+1, hi):
                px, py = pts[i]
                d = abs(dy*(px-ax) - dx*(py-ay)) / n if n > 1e-6 else math.hypot(px-ax, py-ay)
                if d > md: md, mi = d, i
            if md > eps:
                out.add(mi); stack += [(lo, mi), (mi, hi)]
    eps = eps_m
    while True:
        keep = {0, len(line)-1}; dp(0, len(line)-1, eps, keep)
        if len(keep) <= keep_max: return sorted(keep)
        eps *= 1.4

def resample(line, step_m):
    cd = cumdist(line); total = cd[-1]
    n = max(2, int(total // step_m) + 1)
    out, j = [], 0
    for k in range(n):
        d = min(total, k*step_m)
        while j < len(cd)-2 and cd[j+1] < d: j += 1
        seg = cd[j+1]-cd[j] or 1e-9
        t = (d-cd[j])/seg
        out.append((line[j][0]+t*(line[j+1][0]-line[j][0]), line[j][1]+t*(line[j+1][1]-line[j][1])))
    if out[-1] != line[-1]: out.append(line[-1])
    return out

def dist_point_to_line_m(p, line_xy, kx, ky):
    px, py = p[1]*kx, p[0]*ky
    best = 1e18
    for i in range(len(line_xy)-1):
        ax, ay = line_xy[i]; bx, by = line_xy[i+1]
        dx, dy = bx-ax, by-ay; L2 = dx*dx+dy*dy
        t = 0 if L2 == 0 else max(0, min(1, ((px-ax)*dx+(py-ay)*dy)/L2))
        d = math.hypot(px-(ax+t*dx), py-(ay+t*dy))
        if d < best: best = d
    return best

def project(line):
    lat0 = sum(p[0] for p in line)/len(line)
    kx = math.cos(math.radians(lat0))*111320; ky = 110540
    return [(p[1]*kx, p[0]*ky) for p in line], kx, ky
