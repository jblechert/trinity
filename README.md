# Trinity

Trinity replaces three apps when traveling: the one with your tickets, the one to find connections, and the map.
It is a personal fork of [KDE Itinerary](https://apps.kde.org/itinerary), a digital travel assistant that supports
you while traveling without compromising your privacy, and focuses on Android and on getting to your ticket quickly.

It is not affiliated with or endorsed by KDE. For the original application, its official releases for all
platforms and its documentation, see the [upstream repository](https://invent.kde.org/pim/itinerary).

## Do I have a ticket for here?

You wake up in Barcelona. Can you get on the metro with what you have? Open the app, and the *Current Ticket* tab
answers that first, for where you are right now:

- 🟢 **Green check:** you have a ticket valid in the entire country, e.g. the Deutschlandticket in Germany.
- 🟡 **Yellow check:** you have a ticket valid in this area, e.g. a city day, week or month ticket. It's valid here,
  but mind its zones and area limits.
- 🔴 **Red cross:** none of your tickets is known to be valid here.

The ticket that is valid here is shown right away, barcode included. The location is determined once when the app
starts, country and region are worked out offline. The Deutschlandticket is recognized automatically, for other
tickets you set once where they are valid: a country, or within a radius of where you are.

## Differences to upstream

- The Android Back gesture navigates back inside the application instead of closing it.
- The *Current Ticket* tab is always available: during a trip it shows the current reservation, otherwise
  your currently valid tickets and passes, ready to be shown for inspection.
- The page shown on start can be chosen, by default this is the *Current Ticket* tab.
- Journey search remembers previously searched connections. Selecting one, or its return journey,
  shows the connections departing now.
- Journey search results show what was searched for, hide connections that already departed, and show
  when the first train or bus actually leaves when a journey starts with a walk.
- Journey search results can be shown on a timeline: each connection is a column, with its trains and
  buses placed at the time they run, so you see at a glance when and how you can get somewhere. It
  opens at the current time, and loads earlier or later connections when scrolling to its edge.
  The idea comes from Andreas Schildbach's app [Öffi](https://oeffi.schildbach.de/), which shows
  connections this way. Simple in hindsight, but whether it would have come up without his work is
  questionable. Standing on the shoulders of giants.
- From a connection you can go straight to buying the ticket: with the booking link where the data source
  provides one, otherwise on the website of the transport company running it.
- Turn-by-turn navigation in the app, on foot, by bike or by car: to the departure stop of a connection, or to any place
  picked on the map. A map follows your position, instructions are spoken ahead of each turn, and a new route is found
  when you leave it. Routes come from KPublicTransport. Handing over to Organic Maps or Google Maps remains possible.
- A map tab, with marked hiking, cycling and mountain bike routes from [Waymarked Trails](https://waymarkedtrails.org)
  on top if you like. Tap a route to see its length, ascent and elevation profile, and follow it: if you're not on it,
  you're guided to its closest point first. Navigation keeps going with the screen off.
- Journeys from the map: tap and hold to pick where to start or where to go, or search a station or address. Starting
  from your current location is the default, and picked places are named by their address. Then choose how to get
  there: public transport connections between them, walking all the way included where that's all it takes, or
  navigation on foot, by bike or by car. Routes on foot, by bike or by car are shown on the map first, with duration,
  length and ascent, before navigation starts. For now these are only found when they take up to about half an hour,
  and not around Frankfurt and Hanau; both need fixes in KPublicTransport.
- Show a connection from the journey search on the map: trains, buses and subways in their line colors with their stops
  and line names, walks as dotted lines, and a list of its sections to zoom to each of them.
- Back (the key or gesture) closes what was last opened on the map: details of a place, a trip, search results, a
  journey or the planner.
- Tap a shop, café or other place on the map to see what OpenStreetMap knows about it: opening hours and whether it's
  open now, address, phone, website. Walk, cycle or drive there, or use it as start or destination of a journey.
- Tap a bus stop or station on the map to see the lines departing there with their next departures, and tap a line to
  see its route on the map with all its stops. Double tap the map to zoom in.
- Find places on the map by name or by category: "Bäckerei", "pharmacies" or "nearest ATM", or pick one of about fifty
  categories. Search near you or around the center of the map, for the nearest places or within 1, 5 or 20 km. The
  results are listed by distance with whether they're open now, shown on the map, and open the same details as a tap.
- Ascent and descent of walks and bike rides, where the routing service provides them (KPublicTransport extension,
  to be proposed to KDE).
- Rental bikes in the journey search, if you like: to and from stations or all the way, shown in the timeline with
  the bike sharing system's name and color, and a button to rent the bike at the right station in its app.
- On-demand buses (Rufbus, Anrufsammeltaxi) and shuttle buses are part of the journey search. In rural areas they're
  often the only public transport, and leaving them out found connections hours later or none at all.
- `geo:` links from other apps show the place on the map, with the same details as a tap: walk, cycle or drive there,
  or use it as start or destination of a journey.
- Flights in the journey search, if you like. They're left out by default, as flight data is only available for a few
  regions so far.
- The journey search remembers the kind of ticket you travel with, e.g. local transport only for the
  Deutschlandticket, so long distance trains don't show up when you can't use them.

## Sponsors

Development of this fork is sponsored by [horst-gummi.de](https://horst-gummi.de) and
[siegel-dichtungen.de](https://siegel-dichtungen.de), who paid for the Claude account it is being built with.
Rubber, made in Germany. Thank you!

## Download

**[Download the latest APK](https://github.com/jblechert/trinity/releases/latest/download/trinity-arm64-v8a.apk)**
(Android 9 or later, 64-bit ARM), or pick a specific build from the
[releases page](https://github.com/jblechert/trinity/releases).

For iOS, each release also has an unsigned app (`trinity-ios-unsigned.ipa`), which has to be signed before it can be
installed, see [docs/ios/PORTING.md](docs/ios/PORTING.md).

Things to know before installing:

- These are development builds, provided as-is and without any warranty. Whether you run them is up to you.
- Trinity has its own application ID, so it can be installed alongside the official KDE Itinerary. To take
  your data along, export it in KDE Itinerary and import the file in Trinity. Builds up to 8 still used
  KDE Itinerary's application ID and replace the official app.
- There is no automatic update, you get a new version by downloading and installing it again.

## Building

`tools/android/build-apk.sh` builds the APK the same way KDE's CI does, using KDE Craft in a container.
It needs Docker and a few gigabytes of disk space.

```
tools/android/build-apk.sh arm64 all      # dependencies, application, APK
tools/android/build-apk.sh arm64 install  # sign with the Android debug key and install via adb
```

`tools/test/journey-e2e.py` runs journey searches between random places in the app on a device or emulator, by public
transport and optionally on foot, by bike or by car (`--modes`), and writes a report with screenshots, see
[docs/testing.md](docs/testing.md).

## Contributing

Changes that are useful beyond this fork should go to KDE Itinerary itself, see
https://community.kde.org/Get_Involved for how to get started there.

Important external components:
- Travel document extractor engine: https://invent.kde.org/pim/kitinerary
- Public transport data access: https://invent.kde.org/libraries/kpublictransport
- Indoor map renderer: https://invent.kde.org/libraries/kosmindoormap
