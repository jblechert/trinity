<!--
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: CC0-1.0
-->

# Testing

## Unit tests

The unit tests in `autotests/` run with `ctest` in a desktop build of the app.

## End-to-end journey tests

`tools/test/journey-e2e.py` runs complete journey searches in the app on an Android device or emulator and writes an
HTML report with screenshots. It needs Python 3 (no extra modules), `adb`, the app installed on the device, and
internet access for the device and for the host (to pick places).

```sh
tools/test/journey-e2e.py --serial emulator-5554 --pairs 10 --seed 1 --out /tmp/e2e-report
```

For each test it

1. picks a random point in the region (Germany by default) and snaps it to the closest address or place with
   [Photon](https://photon.komoot.io) reverse geocoding, retrying when that isn't in the region;
2. does the same for a second point about 100 km away (`--distance`, `--tolerance`; the snapped places must be within
   80 to 120 km of each other by default);
3. lets the app search public transport connections between both places, departing on the next weekday at 9:00
   (`--time` to change that), and show the best one on the map;
4. waits for the app to log the result of the search, takes a screenshot of the connection on the map, goes back and
   takes one of the result list;
5. adds the places, their distance, the number of connections found, the best connection and the screenshots to
   `index.html` in the output directory, and the app's log of the search to `pair-NN.log`.

A test passes when at least one connection was found. Connections taking more than 6 hours (`--slow`) are marked, as
they often point to a missing service or data source, like the on-demand buses that were once left out.

`--modes` tests routes on foot, by bike or by car between the same places as well, e.g. `--modes transit,walk,car`.
For these the app opens the route preview on the map; the report has a screenshot of it, the duration and length of
the route, or a failure when none was found. Routes taking longer than `--slow` are marked too, which is expected on
foot or by bike at the default distance.

The pairs are saved to `pairs.json`; `--pairs-file` runs the same pairs again, e.g. after a fix, and `--only 3,5`
picks some of them, keeping their numbers in file names and the report. `--seed` makes the random pairs reproducible as long as the map data used by Photon doesn't change.

### Other regions

`--region` takes the name of a built-in region (`germany`, or `world`: very coarse outlines of the continents with
the most public transport data), a bounding box as `bbox:minlon,minlat,maxlon,maxlat`, or a JSON file:

```json
{
    "name": "Austria",
    "countries": ["AT"],
    "polygons": [[[9.5, 47.5], [16.9, 48.0], [16.1, 46.9], [12.1, 47.0]]]
}
```

Points are picked within the polygons (as longitude, latitude), and kept only if Photon puts them into one of
`countries` (ISO 3166 codes; empty for any).

### How the app is driven

The test opens a `page:` URL in the app, the same kind of link Android shortcuts use:

```sh
adb shell "am start -n at.blechert.trinity/org.kde.itinerary.Activity -a android.intent.action.VIEW \
    -d 'page:///map?from=50.1998,9.112&fromName=Rothenbergen&to=50.111,8.682&toName=Frankfurt&search=transit&time=2026-11-23T09:00&show=best'"
```

`page:///map` opens the map with the journey planner. Its parameters (see `MapPage.openRequest()`):

| Parameter | Meaning |
|---|---|
| `from`, `to` | departure and arrival as `latitude,longitude`; the current location if `from` is missing |
| `fromName`, `toName` | their names, otherwise they're named by their address |
| `search` | `transit` to search public transport connections, `walk`, `bike` or `car` to preview a route |
| `time` | departure time for `transit`, ISO 8601 local time, now if missing |
| `show` | `best` to show the best connection on the map once the search is done |
| `place`, `placeName` | instead of a journey: show a place on the map, as `geo:` links do |
| `query` | instead of a journey: search places on the map |

On the desktop, `itinerary --page "map?from=...&to=...&search=transit"` does the same.

When a journey search finishes the app logs a line like

```
journey search finished: results=10 shown=10 error="" best: departure=2026-11-23T09:36 arrival=2026-11-23T10:42 duration=3960 changes=3 sections="68,RE50,walk,U2,U5,walk"
```

The best connection is the one arriving first of those departing at or after the requested time. When it is shown
on the map the app logs `map: showing a journey with N sections`. A route preview logs

```
route preview finished: mode=car results=1 error="" best: duration=2220 distance=41230
```

or `best: none` when no route was found. These lines are logged in the `org.kde.itinerary.journeysearch` category.

### Finding out why a test failed

- `error` in the log line and the report has the error message of the data sources, if any.
- Run the same request on the host against KPublicTransport with `KPUBLICTRANSPORT_LOG_DIR` set, which saves the
  requests and replies of each data source, to see which data source answered and what it returned.
- Compare with another journey planner, e.g. [Transitous](https://transitous.org) or the operator's, to tell missing
  connections in the data apart from problems in the app or in KPublicTransport.
