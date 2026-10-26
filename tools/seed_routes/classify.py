"""Segment transport classification + validation against OSM way tags, and
difficulty from data. Fails LOUDLY (ValidationError) on terrain mismatches."""

class ValidationError(Exception):
    pass

FOOT_OK   = {"path","footway","track","steps","pedestrian","bridleway","cycleway","service","unclassified","residential","living_street","tertiary","via_ferrata","bridge","platform"}
FOOT_BAD  = {"motorway","trunk","primary","secondary","motorway_link","trunk_link","primary_link","secondary_link"}
DRIVE_OK  = {"track","unclassified","service","residential","tertiary","secondary","primary","trunk","living_street","tertiary_link","secondary_link","road"}
DRIVE_BAD = {"path","footway","steps","pedestrian","cycleway","bridleway","via_ferrata","corridor"}
BIKE_OK   = {"cycleway","track","path","residential","service","unclassified","tertiary","secondary","living_street","pedestrian","footway","primary","tertiary_link","secondary_link","bridleway","road"}
BIKE_BAD  = {"motorway","trunk","steps","motorway_link","trunk_link","via_ferrata"}

def classify_way(tags, mode):
    """Returns (transport, label). mode = relation-level intent: foot|bike|overland|water."""
    hw = tags.get("highway"); ww = tags.get("waterway"); nat = tags.get("natural")
    if mode == "water":
        if ww in {"river","canal","stream","riverbank","drain","ditch"} or nat == "water" or tags.get("route") == "ferry":
            return "water", {"river":"River","canal":"Canal","stream":"Stream"}.get(ww, "Open water" if nat=="water" else "Waterway")
        raise ValidationError(f"water segment on non-water way: {tags}")
    if hw is None and tags.get("route") == "ferry":
        return "overland" if mode=="overland" else mode, "Ferry crossing"
    if hw is None:
        raise ValidationError(f"way without highway tag in {mode} route: {tags}")
    if mode == "foot":
        if hw in FOOT_BAD: raise ValidationError(f"foot segment on highway={hw}: {tags}")
        if hw == "via_ferrata" or tags.get("via_ferrata_scale"): return "climb", "Via ferrata"
        if hw not in FOOT_OK: raise ValidationError(f"foot segment on unexpected highway={hw}")
        label = {"path":"Footpath","footway":"Footway","track":"Track","steps":"Steps","pedestrian":"Pedestrian way","bridleway":"Bridleway"}.get(hw, "Minor road")
        if hw in {"track"} and tags.get("tracktype"): label = "Track"
        return "foot", label
    if mode == "overland":
        if hw in DRIVE_BAD: raise ValidationError(f"overland segment on highway={hw} (not drivable): {tags}")
        if hw not in DRIVE_OK: raise ValidationError(f"overland segment on unexpected highway={hw}")
        s = tags.get("surface", "")
        if hw == "track": label = "4×4 track" if tags.get("tracktype") in {"grade3","grade4","grade5"} or tags.get("4wd_only") in {"yes","recommended"} else "Gravel track"
        else: label = "Gravel road" if s in {"gravel","unpaved","dirt","compacted","ground","sand"} else "Road"
        return "overland", label
    if mode == "bike":
        if hw in BIKE_BAD: raise ValidationError(f"bike segment on highway={hw}: {tags}")
        if hw not in BIKE_OK: raise ValidationError(f"bike segment on unexpected highway={hw}")
        return "bike", {"cycleway":"Cycle path","track":"Track","path":"Path"}.get(hw, "Quiet road")
    raise ValidationError(f"unknown mode {mode}")

SAC = {"hiking":0,"mountain_hiking":1,"demanding_mountain_hiking":2,"alpine_hiking":3,"demanding_alpine_hiking":4,"difficult_alpine_hiking":5}

def difficulty(mode, owners_tags, km, ascent_m, has_via_ferrata=False):
    """Data-driven, returns (difficulty, reason)."""
    pts = 0; parts = []
    if mode == "foot":
        sac = max((SAC.get(t.get("sac_scale"), -1) for t in owners_tags), default=-1)
        names = [k for k,v in SAC.items() if v == sac]
        if sac < 0: parts.append("sac_scale untagged in OSM"); s = 0
        else:
            s = 0 if sac == 0 else (1 if sac == 1 else 2 if sac == 2 else 3)
            parts.append(f"max sac_scale={names[0]}")
        pts += s
        a = 0 if ascent_m < 500 else 1 if ascent_m < 1000 else 2 if ascent_m < 1700 else 3
        d = 0 if km < 12 else 1 if km < 22 else 2 if km < 35 else 3
        g = 1 if km > 0 and ascent_m/km > 120 else 0
        pts += a + d + g
        parts.append(f"{km:.1f} km, +{ascent_m:.0f} m" + (", steep (>120 m/km)" if g else ""))
        if has_via_ferrata: pts += 2; parts.append("via ferrata sections")
        lvl = "easy" if pts <= 1 else "moderate" if pts <= 4 else "hard"
        if sac >= 2: lvl = "hard" if pts >= 4 else "moderate"
    elif mode == "bike":
        m = max((int(t["mtb:scale"]) for t in owners_tags if str(t.get("mtb:scale","")).isdigit()), default=-1)
        if m >= 0: parts.append(f"max mtb:scale={m}")
        else: parts.append("mtb:scale untagged")
        pts = (m if m >= 0 else 0) + (0 if ascent_m/km < 8 else 1 if ascent_m/km < 15 else 2) + (0 if km < 40 else 1 if km < 90 else 2)
        parts.append(f"{km:.0f} km, +{ascent_m:.0f} m")
        lvl = "easy" if pts <= 1 else "moderate" if pts <= 3 else "hard"
    elif mode == "overland":
        tt = [t.get("tracktype") for t in owners_tags if t.get("tracktype")]
        rough = sum(1 for t in tt if t in {"grade3","grade4","grade5"})
        fwd = any(t.get("4wd_only") in {"yes","recommended"} for t in owners_tags)
        ford = any(t.get("ford") == "yes" for t in owners_tags)
        pts = (2 if fwd else 0) + (1 if ford else 0) + (1 if tt and rough/len(tt) > .3 else 0) + (1 if km > 80 else 0)
        parts += [f"tracktype grade3-5 on {rough}/{len(tt)} tagged ways" if tt else "tracktype untagged", "4wd_only" if fwd else "no 4wd_only tag", "ford present" if ford else "no ford tagged", f"{km:.0f} km"]
        lvl = "easy" if pts == 0 else "moderate" if pts <= 2 else "hard"
    else:  # water
        g = [t.get("canoe:grade") or t.get("whitewater:section_grade") for t in owners_tags]
        g = [x for x in g if x]
        parts += [f"canoe grade {max(g)}" if g else "no rapids/grade tagged", f"{km:.0f} km"]
        lvl = "easy" if not g and km < 25 else "moderate" if not g else "hard"
    return lvl, "; ".join(parts)
