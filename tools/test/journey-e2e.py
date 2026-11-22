#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
# SPDX-License-Identifier: BSD-3-Clause
"""End-to-end journey search test on an Android device or emulator.

Picks random pairs of places about a given distance apart within a region (Germany by default),
snaps them to nearby addresses with Photon reverse geocoding, and for each pair lets the app search
public transport connections between them through a page:///map URL. It waits for the app to log the
result of the search, takes screenshots of the best connection on the map and of the result list,
and writes an HTML report.

A pair passes when at least one connection was found.

Example:
    tools/test/journey-e2e.py --serial emulator-5554 --pairs 10 --seed 1 --out /tmp/e2e-report

See docs/testing.md for details.
"""

import argparse
import datetime
import html
import json
import math
import os
import random
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

PACKAGE = "at.blechert.trinity"
ACTIVITY = "org.kde.itinerary.Activity"
USER_AGENT = "journey-e2e-test/1.0"
EARTH_RADIUS = 6371000.0

# Regions to pick places in: polygons as (longitude, latitude) rings, and the countries
# (ISO 3166-1 alpha-2, as reported by Photon) places must be in. No countries means any.
# The polygons are coarse; the country check catches places just outside.
REGIONS = {
    "germany": {
        "countries": ["DE"],
        "polygons": [[
            (7.0, 53.3), (7.2, 53.7), (8.5, 53.9), (8.6, 54.9), (9.4, 54.85), (10.0, 54.5),
            (10.9, 54.4), (11.0, 54.0), (12.0, 54.2), (13.0, 54.6), (14.2, 53.9), (14.4, 53.3),
            (14.6, 52.6), (14.7, 51.6), (15.0, 51.1), (14.3, 50.9), (12.9, 50.4), (12.1, 50.3),
            (12.4, 49.7), (13.0, 49.3), (13.8, 48.8), (13.4, 48.6), (13.0, 48.2), (12.8, 47.7),
            (13.0, 47.5), (12.2, 47.6), (11.0, 47.4), (10.2, 47.3), (9.6, 47.55), (8.6, 47.65),
            (7.6, 47.6), (7.5, 48.0), (8.2, 48.95), (6.4, 49.2), (6.4, 49.8), (6.1, 50.3),
            (6.0, 50.75), (5.9, 51.0), (6.2, 51.5), (5.95, 51.8), (6.8, 52.1), (7.0, 52.4),
            (7.2, 53.0),
        ]],
    },
    # land masses, very coarse; pairs on water or across borders are rejected by geocoding and distance
    "world": {
        "countries": [],
        "polygons": [
            # Europe
            [(-10.0, 36.0), (-10.0, 44.0), (-5.0, 48.5), (-5.5, 58.5), (5.0, 62.0), (10.0, 71.0), (30.0, 71.0),
             (40.0, 67.0), (45.0, 55.0), (45.0, 42.0), (28.0, 41.0), (26.0, 35.5), (12.0, 37.5), (-6.0, 36.0)],
            # North America
            [(-125.0, 49.0), (-124.0, 40.0), (-117.0, 32.5), (-97.0, 26.0), (-81.0, 25.0), (-80.0, 32.0),
             (-70.0, 42.0), (-65.0, 45.0), (-60.0, 47.0), (-80.0, 52.0), (-95.0, 58.0), (-125.0, 55.0)],
            # East Asia
            [(100.0, 22.0), (108.0, 21.5), (121.0, 30.0), (122.0, 40.0), (129.0, 42.0), (130.0, 35.0),
             (141.0, 45.5), (142.0, 35.0), (130.0, 31.0), (126.0, 34.0), (117.0, 23.0), (110.0, 18.0),
             (100.0, 18.0)],
            # Australia, south east
            [(138.0, -35.0), (141.0, -38.5), (150.0, -38.0), (153.5, -28.0), (150.0, -26.0), (141.0, -30.0)],
        ],
    },
}


def log(*args):
    print(*args, file=sys.stderr, flush=True)


# --- geometry -------------------------------------------------------------------------------------

def haversine(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS * math.asin(math.sqrt(a))


def destination(lat, lon, bearing, distance):
    """The point @p distance metres from (lat, lon) in direction @p bearing (degrees)."""
    d = distance / EARTH_RADIUS
    b = math.radians(bearing)
    p1, l1 = math.radians(lat), math.radians(lon)
    p2 = math.asin(math.sin(p1) * math.cos(d) + math.cos(p1) * math.sin(d) * math.cos(b))
    l2 = l1 + math.atan2(math.sin(b) * math.sin(d) * math.cos(p1), math.cos(d) - math.sin(p1) * math.sin(p2))
    return math.degrees(p2), (math.degrees(l2) + 540) % 360 - 180


def in_polygon(lon, lat, ring):
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


class Region:
    def __init__(self, name, polygons, countries):
        self.name = name
        self.polygons = polygons
        self.countries = [c.upper() for c in countries]
        # the bounding box for sampling, as one polygon at a time weighted by its bounding box area
        self.boxes = []
        for ring in polygons:
            lons = [p[0] for p in ring]
            lats = [p[1] for p in ring]
            box = (min(lons), min(lats), max(lons), max(lats))
            area = (box[2] - box[0]) * (math.sin(math.radians(box[3])) - math.sin(math.radians(box[1])))
            self.boxes.append((box, area))

    @staticmethod
    def parse(spec):
        if spec in REGIONS:
            r = REGIONS[spec]
            return Region(spec, r["polygons"], r["countries"])
        if spec.startswith("bbox:"):
            min_lon, min_lat, max_lon, max_lat = (float(v) for v in spec[5:].split(","))
            ring = [(min_lon, min_lat), (max_lon, min_lat), (max_lon, max_lat), (min_lon, max_lat)]
            return Region(spec, [ring], [])
        if os.path.isfile(spec):
            # {"name": ..., "countries": ["DE", ...], "polygons": [[[lon, lat], ...], ...]}
            with open(spec) as f:
                r = json.load(f)
            return Region(r.get("name", spec), [[tuple(p) for p in ring] for ring in r["polygons"]], r.get("countries", []))
        raise SystemExit(f"Unknown region {spec!r}: use one of {', '.join(REGIONS)}, bbox:minlon,minlat,maxlon,maxlat or a JSON file")

    def contains(self, lat, lon):
        return any(in_polygon(lon, lat, ring) for ring in self.polygons)

    def accepts_country(self, country):
        return not self.countries or (country or "").upper() in self.countries

    def random_point(self, rng):
        total = sum(area for _, area in self.boxes)
        while True:
            pick = rng.uniform(0, total)
            for (box, area), ring in zip(self.boxes, self.polygons):
                pick -= area
                if pick <= 0:
                    break
            # uniform on the sphere within the box
            lat = math.degrees(math.asin(rng.uniform(math.sin(math.radians(box[1])), math.sin(math.radians(box[3])))))
            lon = rng.uniform(box[0], box[2])
            if in_polygon(lon, lat, ring):
                return lat, lon


# --- geocoding ------------------------------------------------------------------------------------

class Photon:
    def __init__(self, url, delay):
        self.url = url.rstrip("/")
        self.delay = delay
        self.last = 0.0

    def reverse(self, lat, lon, layers=(), radius=None):
        params = [("lat", f"{lat:.6f}"), ("lon", f"{lon:.6f}"), ("limit", "1"), ("lang", "de")]
        params += [("layer", layer) for layer in layers]
        if radius:
            params.append(("radius", str(radius)))
        url = f"{self.url}/reverse?{urllib.parse.urlencode(params)}"
        wait = self.last + self.delay - time.monotonic()
        if wait > 0:
            time.sleep(wait)
        for attempt in range(3):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
                with urllib.request.urlopen(req, timeout=20) as reply:
                    data = json.load(reply)
                break
            except Exception as e:
                log(f"  Photon request failed ({e}), retrying")
                time.sleep(2 + attempt * 3)
        else:
            return None
        self.last = time.monotonic()
        features = data.get("features", [])
        return features[0] if features else None

    def snap(self, lat, lon):
        """The address or place closest to (lat, lon), as a dict with name, lat, lon, country, or None."""
        for layers, radius in ((("house",), 1), (("street",), 2), (("locality", "district", "city"), 5)):
            feature = self.reverse(lat, lon, layers, radius)
            if feature:
                return place_from_feature(feature)
        return None


def place_from_feature(feature):
    p = feature["properties"]
    lon, lat = feature["geometry"]["coordinates"]
    town = p.get("city") or p.get("locality") or p.get("district") or p.get("county") or ""
    town = " ".join(v for v in (p.get("postcode"), town) if v)
    if p.get("housenumber") and p.get("street"):
        first = f"{p['street']} {p['housenumber']}"
    else:
        first = p.get("name") or p.get("street") or ""
    if first and town.endswith(first):
        # a village or town itself
        first = ""
    name = ", ".join(v for v in (first, town) if v) or f"{lat:.5f}, {lon:.5f}"
    return {
        "name": name,
        "lat": round(lat, 6),
        "lon": round(lon, 6),
        "country": p.get("countrycode", ""),
        "type": p.get("type", ""),
        "osm": f"{p.get('osm_type', '')}{p.get('osm_id', '')}",
    }


def make_pairs(count, region, rng, photon, distance, tolerance):
    pairs = []
    attempts = 0
    while len(pairs) < count:
        attempts += 1
        if attempts > count * 40:
            raise SystemExit("Could not find enough pairs, is the region or distance plausible?")
        lat, lon = region.random_point(rng)
        a = photon.snap(lat, lon)
        if not a or not region.accepts_country(a["country"]):
            log(f"  start {lat:.4f},{lon:.4f}: no address in the region, retrying")
            continue
        for _ in range(6):
            blat, blon = destination(a["lat"], a["lon"], rng.uniform(0, 360), rng.uniform(distance - tolerance / 2, distance + tolerance / 2))
            if region.contains(blat, blon):
                break
        else:
            continue
        b = photon.snap(blat, blon)
        if not b or not region.accepts_country(b["country"]):
            log(f"  destination {blat:.4f},{blon:.4f}: no address in the region, retrying")
            continue
        actual = haversine(a["lat"], a["lon"], b["lat"], b["lon"])
        if abs(actual - distance) > tolerance:
            log(f"  {a['name']} -> {b['name']}: {actual / 1000:.0f} km, out of range, retrying")
            continue
        pairs.append({"from": a, "to": b, "distance": round(actual)})
        log(f"pair {len(pairs)}: {a['name']} -> {b['name']} ({actual / 1000:.0f} km)")
    return pairs


# --- device ---------------------------------------------------------------------------------------

class Device:
    def __init__(self, serial, package):
        self.serial = serial
        self.package = package

    def adb(self, *args, check=True, capture=True, binary=False):
        cmd = ["adb", "-s", self.serial, *args]
        r = subprocess.run(cmd, check=check, capture_output=capture, text=not binary, timeout=60)
        return r.stdout

    def screenshot(self, path):
        data = self.adb("exec-out", "screencap", "-p", binary=True)
        with open(path, "wb") as f:
            f.write(data)

    def pid(self):
        return self.adb("shell", "pidof", self.package, check=False).strip()

    def open_url(self, url):
        # the URL is percent-encoded, so single quotes protect it from the device's shell
        self.adb("shell", f"am start -a android.intent.action.VIEW -n {self.package}/{ACTIVITY} -d '{url}'")

    def wait_for_log(self, pattern, timeout, since_pid=None):
        """Poll the log until a line matches @p pattern, return the match or None on timeout."""
        regex = re.compile(pattern)
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            out = self.adb("logcat", "-d", "-v", "brief", check=False)
            for line in out.splitlines():
                m = regex.search(line)
                if m:
                    return m
            time.sleep(2)
        return None


FINISHED = r"journey search finished: results=(\d+) shown=(\d+) error=(\"(?:[^\"\\]|\\.)*\") best: (.*)$"


def parse_best(summary):
    if summary.strip() == "none":
        return None
    best = {}
    for key, value in re.findall(r'(\w+)=("(?:[^"\\]|\\.)*"|\S+)', summary):
        best[key] = json.loads(value) if value.startswith('"') else value
    for key in ("duration", "changes"):
        if key in best:
            best[key] = int(best[key])
    return best


def default_time():
    """The next weekday at 9:00, so results don't depend on when the test runs."""
    day = datetime.date.today() + datetime.timedelta(days=1)
    while day.weekday() >= 5:
        day += datetime.timedelta(days=1)
    return f"{day.isoformat()}T09:00"


def page_url(pair, search_time):
    query = urllib.parse.urlencode({
        "from": f"{pair['from']['lat']},{pair['from']['lon']}",
        "fromName": pair["from"]["name"],
        "to": f"{pair['to']['lat']},{pair['to']['lon']}",
        "toName": pair["to"]["name"],
        "search": "transit",
        "time": search_time,
        "show": "best",
    }, quote_via=urllib.parse.quote, safe="")
    return f"page:///map?{query}"


def run_pair(device, index, pair, search_time, out, timeout, settle, slow_hours):
    result = {"index": index, **pair, "time": search_time, "screenshots": {}}
    device.adb("logcat", "-c", check=False)
    started = time.monotonic()
    device.open_url(page_url(pair, search_time))
    m = device.wait_for_log(FINISHED, timeout)
    result["searchSeconds"] = round(time.monotonic() - started, 1)
    prefix = f"pair-{index:02d}"
    if not m:
        result.update(status="timeout", results=None)
        device.screenshot(os.path.join(out, f"{prefix}-results.png"))
        result["screenshots"]["results"] = f"{prefix}-results.png"
    else:
        result["results"] = int(m.group(1))
        result["shown"] = int(m.group(2))
        result["error"] = json.loads(m.group(3))
        result["best"] = parse_best(m.group(4))
        result["status"] = "pass" if result["results"] > 0 else "fail"
        best = result["best"]
        if best and best.get("duration", 0) > slow_hours * 3600:
            # passes, but worth a look: often a missing service, or a data source not used
            result["note"] = f"slow: the best connection takes more than {slow_hours:g} hours"
        if result["best"] and device.wait_for_log(r"map: showing a journey with (\d+) sections", 20):
            # let the map load its tiles
            time.sleep(settle)
            device.screenshot(os.path.join(out, f"{prefix}-map.png"))
            result["screenshots"]["map"] = f"{prefix}-map.png"
            # back to the results the journey was picked from
            device.adb("shell", "input", "keyevent", "KEYCODE_BACK")
            time.sleep(2.5)
        else:
            time.sleep(2)
        device.screenshot(os.path.join(out, f"{prefix}-results.png"))
        result["screenshots"]["results"] = f"{prefix}-results.png"
    # the app's log of this search, to see what went wrong
    pid = device.pid()
    if pid:
        log_text = device.adb("logcat", "-d", "-v", "time", f"--pid={pid}", check=False)
        with open(os.path.join(out, f"{prefix}.log"), "w") as f:
            f.write(log_text)
        result["log"] = f"{prefix}.log"
    return result


# --- report ---------------------------------------------------------------------------------------

def fmt_duration(seconds):
    if seconds is None:
        return ""
    return f"{seconds // 3600}:{seconds % 3600 // 60:02d} h"


def osm_link(place):
    return (f'<a href="https://www.openstreetmap.org/?mlat={place["lat"]}&amp;mlon={place["lon"]}#map=15/{place["lat"]}/{place["lon"]}">'
            f'{html.escape(place["name"])}</a><br><small>{place["lat"]:.5f}, {place["lon"]:.5f}</small>')


def write_report(out, meta, results):
    passed = sum(1 for r in results if r["status"] == "pass")
    rows = []
    for r in results:
        best = r.get("best") or {}
        details = ""
        if best:
            details = (f'{html.escape(best.get("departure", "")[11:])} → {html.escape(best.get("arrival", "")[11:])}, '
                       f'{fmt_duration(best.get("duration"))}, {best.get("changes", "?")} changes<br>'
                       f'<small>{html.escape(best.get("sections", ""))}</small>')
        if r.get("error"):
            details += f'<br><small class="error">{html.escape(r["error"])}</small>'
        if r.get("note"):
            details += f'<br><small>{html.escape(r["note"])}</small>'
        shots = "".join(
            f'<a href="{html.escape(path)}"><img src="{html.escape(path)}" alt="{kind}" title="{kind}"></a>'
            for kind, path in (("map", r["screenshots"].get("map")), ("results", r["screenshots"].get("results"))) if path)
        log_link = f'<br><a href="{html.escape(r["log"])}">log</a>' if r.get("log") else ""
        rows.append(f"""<tr class="{r['status']}">
<td>{r['index']}</td><td>{osm_link(r['from'])}</td><td>{osm_link(r['to'])}</td>
<td>{r['distance'] / 1000:.0f} km</td>
<td class="status">{r['status']}{log_link}</td>
<td>{'' if r.get('results') is None else r['results']}</td><td>{details}</td><td>{r['searchSeconds']} s</td>
<td class="shots">{shots}</td></tr>""")
    meta_items = "".join(f"<li>{html.escape(k)}: {html.escape(str(v))}</li>" for k, v in meta.items())
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Journey E2E Report</title>
<style>
body {{ font-family: system-ui, sans-serif; margin: 16px; background: #fff; color: #222; }}
table {{ border-collapse: collapse; width: 100%; }}
th, td {{ border-bottom: 1px solid #ccc; padding: 6px; text-align: left; vertical-align: top; font-size: 14px; }}
tr.pass .status {{ color: #1a7f37; font-weight: bold; }}
tr.fail .status, tr.timeout .status {{ color: #c62828; font-weight: bold; }}
.table {{ overflow-x: auto; }}
.shots {{ white-space: nowrap; }}
.shots img {{ width: 180px; border: 1px solid #aaa; margin-right: 4px; }}
.error {{ color: #c62828; }}
@media (prefers-color-scheme: dark) {{ body {{ background: #1e1e1e; color: #ddd; }} a {{ color: #8ab4f8; }} th, td {{ border-color: #444; }} }}
</style></head><body>
<h1>Journey end-to-end test</h1>
<p><strong>{passed} of {len(results)} passed</strong> (pass: at least one connection found)</p>
<ul>{meta_items}</ul>
<div class="table"><table><tr><th>#</th><th>From</th><th>To</th><th>Distance</th><th>Status</th><th>Journeys</th><th>Best connection</th><th>Search</th><th>Screenshots</th></tr>
{''.join(rows)}
</table></div></body></html>
"""
    with open(os.path.join(out, "index.html"), "w") as f:
        f.write(page)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--serial", default=os.environ.get("ANDROID_SERIAL"), help="adb serial of the device (default: $ANDROID_SERIAL)")
    ap.add_argument("--package", default=PACKAGE, help=f"application id (default: {PACKAGE})")
    ap.add_argument("--pairs", type=int, default=10, help="number of pairs to test (default: 10)")
    ap.add_argument("--seed", type=int, help="random seed, for reproducible pairs")
    ap.add_argument("--region", default="germany",
                    help=f"where to pick places: {', '.join(REGIONS)}, bbox:minlon,minlat,maxlon,maxlat, or a JSON file "
                         '{"name", "countries": ["DE"], "polygons": [[[lon, lat], ...]]} (default: germany)')
    ap.add_argument("--distance", type=float, default=100, help="distance between the places in km (default: 100)")
    ap.add_argument("--tolerance", type=float, default=20, help="allowed deviation from the distance in km (default: 20)")
    ap.add_argument("--pairs-file", help="test the pairs in this file (pairs.json of an earlier run) instead of random ones")
    ap.add_argument("--only", help="with --pairs-file: test only these pairs, e.g. 3,4 (numbered from 1)")
    ap.add_argument("--slow", type=float, default=6, help="mark connections taking longer than this many hours (default: 6)")
    ap.add_argument("--time", default=None, help="departure time, ISO 8601 local time (default: next weekday 09:00)")
    ap.add_argument("--timeout", type=float, default=180, help="seconds to wait for a search (default: 180)")
    ap.add_argument("--settle", type=float, default=6, help="seconds to let the map load before the screenshot (default: 6)")
    ap.add_argument("--photon", default="https://photon.komoot.io", help="Photon instance for reverse geocoding")
    ap.add_argument("--out", required=True, help="output directory for the report")
    args = ap.parse_args()

    if not args.serial:
        raise SystemExit("No device given: use --serial or set ANDROID_SERIAL")
    os.makedirs(args.out, exist_ok=True)
    search_time = args.time or default_time()
    region = Region.parse(args.region)

    if args.pairs_file:
        with open(args.pairs_file) as f:
            pairs = json.load(f)
        if args.only:
            pairs = [pairs[int(i) - 1] for i in args.only.split(",")]
    else:
        seed = args.seed if args.seed is not None else random.randrange(1 << 30)
        args.seed = seed
        log(f"Picking {args.pairs} pairs in {region.name}, about {args.distance:.0f} km apart, seed {seed}")
        photon = Photon(args.photon, delay=1.0)
        pairs = make_pairs(args.pairs, region, random.Random(seed), photon, args.distance * 1000, args.tolerance * 1000)
    with open(os.path.join(args.out, "pairs.json"), "w") as f:
        json.dump(pairs, f, indent=2, ensure_ascii=False)

    device = Device(args.serial, args.package)
    meta = {
        "date": datetime.datetime.now().isoformat(timespec="seconds"),
        "device": args.serial,
        "app": args.package,
        "region": region.name,
        "distance": f"{args.distance:.0f} ± {args.tolerance:.0f} km",
        "seed": args.seed if not args.pairs_file else f"pairs from {args.pairs_file}",
        "departure": search_time,
    }
    results = []
    for i, pair in enumerate(pairs, start=1):
        log(f"[{i}/{len(pairs)}] {pair['from']['name']} -> {pair['to']['name']}")
        r = run_pair(device, i, pair, search_time, args.out, args.timeout, args.settle, args.slow)
        best = r.get("best") or {}
        log(f"  {r['status']}: {r.get('results')} journeys in {r['searchSeconds']} s"
            + (f" ({r['note']})" if r.get("note") else "")
            + (f", best {fmt_duration(best.get('duration'))} {best.get('sections', '')}" if best else "")
            + (f", error {r['error']}" if r.get("error") else ""))
        results.append(r)
        with open(os.path.join(args.out, "results.json"), "w") as f:
            json.dump({"meta": meta, "results": results}, f, indent=2, ensure_ascii=False)
        write_report(args.out, meta, results)
    passed = sum(1 for r in results if r["status"] == "pass")
    log(f"{passed} of {len(results)} passed, report: {os.path.join(args.out, 'index.html')}")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
