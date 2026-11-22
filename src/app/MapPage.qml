// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtLocation as QtLocation
import QtPositioning
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.components as Components
import org.kde.coreaddons as CoreAddons
import org.kde.kpublictransport as KPublicTransport
import org.kde.kpublictransport.ui as KPublicTransportUi
import org.kde.itinerary

/** A map centered on the current location, with optional overlays for marked hiking, cycling and
 *  mountain bike routes, and routes on foot, by bike or by car to any place picked on the map.
 *  Tapping a marked route shows its course and elevation profile, and allows to follow it.
 *  Without overlay, tapping a shop, restaurant or other point of interest shows its details such as opening hours,
 *  and tapping a public transport stop shows the lines departing there and their routes.
 *  Places can be searched by name or category (such as bakeries or pharmacies) around the current location
 *  or the center of the map.
 *  Departure and arrival of a journey can be picked on the map or searched, to search connections between them.
 *  Connections found that way can be shown on the map with all their sections, and routes on foot, by bike
 *  or by car are previewed on the map before navigation starts.
 */
Kirigami.Page {
    id: root

    title: i18nc("@title", "Map")
    padding: 0
    Kirigami.ColumnView.preventStealing: true

    /** Marked routes shown on top of the map: "", "hiking", "cycling" or "mtb". */
    property string overlay: Settings.read("MapPage/Overlay", "")
    property QtLocation.Map overlayMap
    /** Keep the map centered on the current position, until the user moves the map. */
    property bool followPosition: true
    /** The place picked on the map, to go to. */
    property var pickedCoordinate

    /** Departure of the journey to search, the current location if not set. */
    property var journeyFrom
    /** Arrival of the journey to search. */
    property var journeyTo
    /** The journey planner is shown. */
    property bool plannerShown: false
    /** The place search is shown. */
    property bool searchShown: false
    // there is room for only one of them at the top
    onPlannerShownChanged: {
        if (root.plannerShown) {
            root.searchShown = false;
        }
    }
    onSearchShownChanged: {
        if (root.searchShown) {
            root.plannerShown = false;
        }
    }
    readonly property bool hasPosition: positionSource.valid && positionSource.position.latitudeValid && positionSource.position.longitudeValid

    function currentLocation(): var {
        const coord = positionSource.position.coordinate;
        return helper.locationAt(coord.latitude, coord.longitude, i18nc("@info start of navigation", "Current location"));
    }

    /** Use the place picked on the map as departure ("from") or arrival ("to") of the journey. */
    function setJourneyEndpoint(endpoint: string, coord: var): void {
        const location = helper.locationAt(coord.latitude, coord.longitude, i18nc("@info a place picked on the map", "Selected place"));
        if (endpoint === "from") {
            root.journeyFrom = location;
        } else {
            root.journeyTo = location;
        }
        root.pickedCoordinate = undefined;
        root.plannerShown = true;
        root.showJourneyEndpoints();
        // name the place by its address
        root.geocode(endpoint === "from" ? fromGeocoder : toGeocoder, coord);
    }

    /** Look up the address at @p coord with @p geocoder, see applyGeocoding(). */
    function geocode(geocoder: QtLocation.GeocodeModel, coord: var): void {
        // the plugin is created on demand, which must not happen in a binding
        if (!geocoder.plugin) {
            geocoder.plugin = applicationWindow().geocodingPlugin();
        }
        geocoder.query = coord;
        geocoder.update();
    }

    /** Rename the departure or arrival ("from", "to"), the destination of a route preview ("preview"),
     *  or the selected place ("place") to the address found for it, unless it changed meanwhile.
     */
    function applyGeocoding(endpoint: string, geocoder: QtLocation.GeocodeModel): void {
        const locations = { from: root.journeyFrom, to: root.journeyTo, preview: root.previewTo, place: root.selection };
        const location = locations[endpoint];
        if (geocoder.status !== QtLocation.GeocodeModel.Ready || geocoder.count === 0 || !location) {
            return;
        }
        const coord = geocoder.query;
        if (Math.abs(location.latitude - coord.latitude) > 1e-7 || Math.abs(location.longitude - coord.longitude) > 1e-7) {
            return;
        }
        const address = geocoder.get(0).address;
        const street = [address.street, address.streetNumber].filter((s) => s).join(" ");
        const name = [street, address.city].filter((s) => s).join(", ");
        if (name === "") {
            return;
        }
        if (endpoint === "place") {
            root.select(Object.assign({}, location, { name: name }));
            return;
        }
        const named = helper.locationAt(coord.latitude, coord.longitude, name);
        if (endpoint === "from") {
            root.journeyFrom = named;
        } else if (endpoint === "to") {
            root.journeyTo = named;
        } else {
            root.previewTo = named;
        }
    }

    function searchConnection(): void {
        root.searchConnectionAt(undefined, false);
    }

    /** Search public transport connections departing at @p dateTime, or now if undefined.
     *  With @p showBest the best connection found is shown on the map once the search is done.
     */
    function searchConnectionAt(dateTime: var, showBest: bool): void {
        const from = root.journeyFrom ?? root.currentLocation();
        let properties = {
            publicTransportManager: LiveDataManager.publicTransportManager,
            departureStop: from,
            arrivalStop: root.journeyTo,
            returnsToMap: true,
        };
        if (dateTime) {
            properties.initialDateTime = dateTime;
        }
        const page = root.QQC2.ApplicationWindow.window.pageStack.push(Qt.resolvedUrl("JourneyRequestPage.qml"), properties);
        const queryPage = page.searchJourney();
        queryPage.showBestOnMap = showBest;
    }

    /** A location at the coordinate given as "latitude,longitude" in @p coord, named @p name.
     *  Undefined if @p coord is not a valid coordinate.
     */
    function parseLocation(coord: var, name: var): var {
        const parts = (coord ?? "").split(",");
        if (parts.length !== 2) {
            return undefined;
        }
        const lat = parseFloat(parts[0]);
        const lon = parseFloat(parts[1]);
        if (!isFinite(lat) || !isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
            return undefined;
        }
        return helper.locationAt(lat, lon, name ? name : i18nc("@info a place picked on the map", "Selected place"));
    }

    /** Show a place given by @p args, see openRequest(). */
    function openPlace(args: var): void {
        root.closeJourney();
        root.prepareJourneyDisplay();
        root.plannerShown = false;
        if (args.query && !args.place) {
            root.openSearch();
            searchPane.text = args.query;
            searchPane.search("");
            return;
        }
        const location = root.parseLocation(args.place, args.placeName);
        if (!location) {
            console.warn("Invalid place to show on the map:", args.place);
            return;
        }
        const coord = QtPositioning.coordinate(location.latitude, location.longitude);
        root.followPosition = false;
        map.zoomLevel = 17;
        root.select({
            type: "place",
            name: location.name,
            typeName: "",
            iconSource: "mark-location-symbolic",
            latitude: location.latitude,
            longitude: location.longitude,
            distance: 0,
            address: "",
        });
        root.centerOn(coord);
        if (!args.placeName) {
            root.geocode(placeGeocoder, coord);
        }
    }

    /** Plan a journey given by @p args, the query items of a page:///map URL (see ApplicationController::handlePageUrl()),
     *  e.g. from another app or for automated tests:
     *  - from, to: departure and arrival as "latitude,longitude", the current location if from is missing
     *  - fromName, toName: their names, otherwise they are named by their address
     *  - search: "transit" to search public transport connections, "walk", "bike" or "car" to preview a route
     *  - time: departure time of the connections to search, as ISO 8601 local time, e.g. 2026-11-23T09:00, now if missing
     *  - show: "best" to show the best connection found on the map once the search is done
     *  Or a single place to show, e.g. from a geo: URI:
     *  - place: the place as "latitude,longitude", placeName: its name, otherwise it is named by its address
     *  - query: text to search places for, if there is no coordinate
     */
    function openRequest(args: var): void {
        if (args.place || args.query) {
            root.openPlace(args);
            return;
        }
        const from = root.parseLocation(args.from, args.fromName);
        const to = root.parseLocation(args.to, args.toName);
        if (!from && !to) {
            console.warn("No valid departure or arrival given to open the map with:", JSON.stringify(args));
            return;
        }
        root.pendingSearch = undefined;
        root.closeJourney();
        root.prepareJourneyDisplay();
        root.journeyFrom = from;
        root.journeyTo = to;
        root.plannerShown = true;
        if (from && !args.fromName) {
            root.geocode(fromGeocoder, QtPositioning.coordinate(from.latitude, from.longitude));
        }
        if (to && !args.toName) {
            root.geocode(toGeocoder, QtPositioning.coordinate(to.latitude, to.longitude));
        }
        root.showJourneyEndpoints();
        if (!to) {
            return;
        }
        if (args.search === "transit") {
            const time = args.time ? new Date(args.time) : undefined;
            if (time && isNaN(time.getTime())) {
                console.warn("Invalid departure time:", args.time);
                return;
            }
            // once departure and arrival are named by their address, as the search shows and remembers their names
            root.pendingSearch = { time: time, showBest: args.show === "best" };
            pendingSearchTimer.restart();
            root.runPendingSearch(false);
            return;
        }
        const modes = {
            walk: KPublicTransport.IndividualTransport.Walk,
            bike: KPublicTransport.IndividualTransport.Bike,
            car: KPublicTransport.IndividualTransport.Car,
        };
        if (modes[args.search] !== undefined) {
            root.previewRoute(from, to, modes[args.search]);
            if (!args.toName) {
                root.geocode(previewGeocoder, QtPositioning.coordinate(to.latitude, to.longitude));
            }
        }
    }

    /** A journey search requested by openRequest(), waiting for departure and arrival to be named. */
    property var pendingSearch

    /** Run the pending journey search once departure and arrival are named, or right away with @p force. */
    function runPendingSearch(force: bool): void {
        if (!root.pendingSearch) {
            return;
        }
        if (!force && (fromGeocoder.status === QtLocation.GeocodeModel.Loading || toGeocoder.status === QtLocation.GeocodeModel.Loading)) {
            return;
        }
        const search = root.pendingSearch;
        root.pendingSearch = undefined;
        pendingSearchTimer.stop();
        root.searchConnectionAt(search.time, search.showBest);
    }

    Timer {
        id: pendingSearchTimer
        // don't wait for the names forever
        interval: 3000
        onTriggered: root.runPendingSearch(true)
    }

    QtLocation.GeocodeModel {
        id: fromGeocoder
        autoUpdate: false
        limit: 1
        onStatusChanged: {
            root.applyGeocoding("from", fromGeocoder);
            root.runPendingSearch(false);
        }
    }
    QtLocation.GeocodeModel {
        id: toGeocoder
        autoUpdate: false
        limit: 1
        onStatusChanged: {
            root.applyGeocoding("to", toGeocoder);
            root.runPendingSearch(false);
        }
    }
    QtLocation.GeocodeModel {
        id: placeGeocoder
        autoUpdate: false
        limit: 1
        onStatusChanged: root.applyGeocoding("place", placeGeocoder)
    }
    QtLocation.GeocodeModel {
        id: previewGeocoder
        autoUpdate: false
        limit: 1
        onStatusChanged: root.applyGeocoding("preview", previewGeocoder)
    }

    /** Show departure and arrival on the map, after one of them was searched or picked on the map.
     *  Once the journey planner is laid out, so they are not hidden behind it.
     */
    function showJourneyEndpoints(): void {
        root.focusLater("endpoints");
    }

    /** Coordinates of departure and arrival of the journey to search, those known so far. */
    function journeyEndpointCoordinates(): var {
        let coords = [];
        for (const location of [root.journeyFrom ?? (root.hasPosition ? root.currentLocation() : undefined), root.journeyTo]) {
            if (location && location.hasCoordinate) {
                coords.push(QtPositioning.coordinate(location.latitude, location.longitude));
            }
        }
        return coords;
    }

    Component {
        id: stopPickerComponent
        StopPickerPage {
            property string endpoint
            publicTransportManager: LiveDataManager.publicTransportManager
            showUseCurrentLocationButton: endpoint === "from"
            historySortRoleName: Settings.read("StopPicker/historySortMode", "lastUsed")
            onHistorySortRoleChanged: (sortRoleName) => Settings.write("StopPicker/historySortMode", sortRoleName)
            onLocationChanged: {
                if (endpoint === "from") {
                    root.journeyFrom = PublicTransport.copyLocation(location);
                } else {
                    root.journeyTo = PublicTransport.copyLocation(location);
                }
                root.showJourneyEndpoints();
            }
        }
    }
    function searchJourneyEndpoint(endpoint: string): void {
        root.QQC2.ApplicationWindow.window.pageStack.push(stopPickerComponent, {
            endpoint: endpoint,
            title: endpoint === "from" ? i18nc("departure train station", "Select Departure Stop") : i18nc("arrival train station", "Select Arrival Stop"),
        });
    }

    // the plugin of a map can't be changed once set, so the overlay map is recreated when the overlay changes
    onOverlayChanged: {
        markedRoutes.clearRoute();
        root.applyOverlay();
    }
    function applyOverlay(): void {
        if (root.overlayMap) {
            root.overlayMap.destroy();
        }
        root.overlayMap = overlayMapComponent.createObject(map.parent);
        root.overlayMap.plugin = root.overlay === "" ? emptyOverlayPlugin : trailsPluginComponent.createObject(root.overlayMap);
        root.overlayMap.activeMapType = root.overlayMap.supportedMapTypes[root.overlayMap.supportedMapTypes.length - 1];
        Settings.write("MapPage/Overlay", root.overlay);
    }

    Component.onCompleted: {
        root.applyOverlay();
        if (locationPermission.status !== Qt.Granted) {
            locationPermission.request();
        }
    }

    /** Navigate from the current position to @p destination, on foot, by bike or by car.
     *  @p journey is the route to follow if already known, e.g. from a preview.
     */
    function startNavigation(destination: var, mode: int, journey: var): void {
        let properties = {
            destination: destination,
            travelMode: mode,
        };
        if (journey) {
            properties.journey = journey;
        }
        root.QQC2.ApplicationWindow.window.pageStack.layers.push(Qt.createComponent("org.kde.itinerary", "WalkingNavigationPage"), properties);
    }

    /** Where shown journeys and the outcome of route previews are logged, e.g. for automated tests. */
    readonly property LoggingCategory searchLog: LoggingCategory {
        name: "org.kde.itinerary.journeysearch"
        defaultLogLevel: LoggingCategory.Info
    }

    /** The journey shown on the map: a public transport connection, or the preview of a route on foot, by bike or by car. */
    property var shownJourney
    /** The KPublicTransport.IndividualTransport mode of a route preview, -1 for a public transport connection. */
    property int shownJourneyMode: -1
    /** The pane with the shown journey or route preview is open. */
    property bool journeyPaneShown: false
    /** The search results page a shown connection was picked from. */
    property var journeyResultsPage: null
    /** Index of the section of the shown journey brought into view, -1 for all of it. */
    property int focusedSection: -1
    /** Start of a route preview, undefined for the current location. */
    property var previewFrom
    /** Destination of a route preview. */
    property var previewTo

    /** Whether @p location is where we are, so navigation can start there. Undefined stands for the current location. */
    function isHere(location: var): bool {
        return root.hasPosition && (!location
            || QtPositioning.coordinate(location.latitude, location.longitude).distanceTo(positionSource.position.coordinate) < 100);
    }

    /** Close what would hide a journey or compete with it on the map. */
    function prepareJourneyDisplay(): void {
        root.clearSelection();
        if (root.searchShown) {
            root.closeSearch();
        }
        markedRoutes.clearRoute();
        root.routeListShown = false;
        root.routeShown = false;
        root.pickedCoordinate = undefined;
    }

    /** Show @p journey, a public transport connection, on the map with all its sections.
     *  @p resultsPage is the page with the search results it was picked from, to go back to.
     */
    function showJourney(journey: var, resultsPage: var): void {
        root.prepareJourneyDisplay();
        root.saveViewport();
        previewModel.running = false;
        previewModel.cancel();
        root.shownJourneyMode = -1;
        root.previewFrom = undefined;
        root.previewTo = undefined;
        root.shownJourney = journey;
        root.journeyResultsPage = resultsPage ?? null;
        root.journeyPaneShown = true;
        root.focusedSection = -1;
        root.focusLater("journey");
        console.info(root.searchLog, "map: showing a journey with", journey.sections.length, "sections");
    }

    /** Show the route from @p from (undefined for the current location) to @p to, on foot, by bike or by car,
     *  before starting navigation along it.
     */
    function previewRoute(from: var, to: var, mode: int): void {
        if (!from && !root.hasPosition) {
            // without a start there is nothing to show yet, navigation waits for the location though
            root.startNavigation(to, mode, undefined);
            return;
        }
        root.prepareJourneyDisplay();
        root.saveViewport();
        root.previewFrom = from;
        root.previewTo = to;
        root.shownJourneyMode = mode;
        root.shownJourney = undefined;
        root.journeyResultsPage = null;
        root.journeyPaneShown = true;
        root.focusedSection = -1;
        // the same request navigation uses, so the preview shows the route it follows
        const start = from ?? root.currentLocation();
        helper.travelMode = mode;
        let request = helper.routeRequest(start.latitude, start.longitude, to);
        request.from = start;
        // the model still has the routes of a previous request until the new one starts, see onLoadingChanged
        previewModel.running = false;
        previewModel.request = request;
        // show where the route goes already while it is searched
        root.focusLater("journey");
    }

    function closeJourney(): void {
        previewModel.running = false;
        previewModel.cancel();
        // back to where the planner was, or to the map from before
        if (root.plannerShown && root.journeyTo) {
            root.savedViewport = undefined;
            root.showJourneyEndpoints();
        } else {
            root.restoreViewport();
        }
        root.journeyPaneShown = false;
        root.shownJourney = undefined;
        root.previewFrom = undefined;
        root.previewTo = undefined;
        root.journeyResultsPage = null;
        root.focusedSection = -1;
        if (root.focusTarget === "journey") {
            root.focusTarget = undefined;
        }
    }

    /** Switch a route preview to another mode, or search public transport connections instead for -1. */
    function changePreviewMode(mode: int): void {
        if (mode >= 0) {
            root.previewRoute(root.previewFrom, root.previewTo, mode);
            return;
        }
        root.journeyFrom = root.previewFrom;
        root.journeyTo = root.previewTo;
        root.closeJourney();
        root.plannerShown = true;
        root.searchConnection();
    }

    /** Bring the section with index @p index of the shown journey into view, or all of it for -1. */
    function focusJourneySection(index: int): void {
        root.focusedSection = index;
        root.focusTarget = "journey";
        root.applyFocus();
    }

    /** Index of the page with the search results of the shown connection in the page stack, -1 if it is gone. */
    function journeyResultsPageIndex(): int {
        const pageStack = root.QQC2.ApplicationWindow.window?.pageStack;
        if (!root.journeyResultsPage || !pageStack) {
            return -1;
        }
        for (let i = 0; i < pageStack.depth; ++i) {
            if (pageStack.get(i) === root.journeyResultsPage) {
                return i;
            }
        }
        return -1;
    }

    /** Go back to the search results the shown connection was picked from. */
    function showJourneyResults(): void {
        const index = root.journeyResultsPageIndex();
        if (index >= 0) {
            root.QQC2.ApplicationWindow.window.pageStack.currentIndex = index;
        }
    }

    /** Close what was opened last on the map, such as the details of a place or a shown journey,
     *  when going back. Only checks whether there is something to close if @p apply is false.
     */
    function closeLast(apply: bool): bool {
        if (routeMenu.opened) {
            return false; // the menu handles that itself
        }
        if (root.selection !== undefined || root.candidates.length > 0) {
            if (apply) {
                if (root.tripShown) {
                    sheetLoader.item.hideTrip();
                } else {
                    root.clearSelection();
                }
            }
            return true;
        }
        if (routePane.visible) {
            if (apply) {
                markedRoutes.clearRoute();
                root.routeListShown = false;
                root.routeShown = false;
            }
            return true;
        }
        if (root.journeyPaneShown) {
            if (apply) {
                if (root.journeyResultsPageIndex() >= 0) {
                    root.showJourneyResults();
                } else {
                    root.closeJourney();
                }
            }
            return true;
        }
        if (root.searchShown) {
            if (apply) {
                if (placeSearch.active) {
                    placeSearch.clear();
                } else {
                    root.closeSearch();
                }
            }
            return true;
        }
        if (root.plannerShown) {
            if (apply) {
                root.plannerShown = false;
            }
            return true;
        }
        return false;
    }

    // Going back is handled with the keyboard focus on this page, which actions in the header take away from it,
    // e.g. the one opening the journey planner. Take it back when there is something to close.
    readonly property bool canGoBack: root.closeLast(false)
    onCanGoBackChanged: {
        if (root.canGoBack && !root.activeFocus && root.isCurrentPage) {
            root.forceActiveFocus();
        }
    }

    onBackRequested: (event) => {
        event.accepted = root.closeLast(true);
    }
    // the page stack only asks pages after the first one, the map is usually the first page of its tab though,
    // so handle the key itself as well; instead of a shortcut, as two shortcuts for it would be ambiguous
    Keys.onShortcutOverride: (event) => {
        event.accepted = event.key === Qt.Key_Back && root.closeLast(false);
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Back) {
            event.accepted = root.closeLast(true);
        }
    }

    /** Log the outcome of a route preview, like JourneyQueryPage does for public transport searches. */
    function logPreview(): void {
        const count = previewModel.rowCount();
        const route = count > 0 ? previewModel.data(previewModel.index(0, 0), KPublicTransport.JourneyQueryModel.JourneyRole) : undefined;
        const mode = root.shownJourneyMode === KPublicTransport.IndividualTransport.Walk ? "walk"
            : root.shownJourneyMode === KPublicTransport.IndividualTransport.Bike ? "bike" : "car";
        const best = route ? "duration=" + route.duration + " distance=" + Math.round(route.distance) : "none";
        console.info(root.searchLog, "route preview finished: mode=" + mode + " results=" + count
            + " error=" + JSON.stringify(previewModel.errorMessage) + " best: " + best);
    }

    KPublicTransport.JourneyQueryModel {
        id: previewModel
        /** The current request is being searched, so the results are its own once loading stops.
         *  A new request cancels the previous one first, which stops loading as well.
         */
        property bool running: false
        manager: LiveDataManager.publicTransportManager
        onLoadingChanged: {
            if (previewModel.loading) {
                previewModel.running = true;
                return;
            }
            if (!previewModel.running) {
                return;
            }
            previewModel.running = false;
            if (!root.journeyPaneShown || root.shownJourneyMode < 0) {
                return;
            }
            root.logPreview();
            if (previewModel.rowCount() > 0) {
                root.shownJourney = previewModel.data(previewModel.index(0, 0), KPublicTransport.JourneyQueryModel.JourneyRole);
                root.focusLater("journey");
            }
        }
    }

    // what to draw on the map for the shown journey
    MapJourneyGeometry {
        id: journeyDrawing
        journey: root.shownJourney
        mapView: map
    }

    MapStopoverInfoSheetDrawer {
        id: stopInfoDrawer
        parent: root.QQC2.Overlay.overlay
    }

    /** The place or stop tapped on the map whose details are shown, a candidate as found by MapPlaceLookup. */
    property var selection
    /** Several places or stops found at a tapped place, to choose from. */
    property var candidates: []
    /** The route of a public transport trip shown on the map, from a tapped stop. */
    readonly property bool tripShown: sheetLoader.item?.hasTrip ?? false

    /** Telling that places can only be tapped when zoomed in is only needed once. */
    property bool zoomHintShown: false

    /** The distance on the map covered by a finger's width at @p position. */
    function fingerRadius(position: point): real {
        // also beyond the edge of the map, for taps close to it
        const coord = map.toCoordinate(position, false);
        return coord.distanceTo(map.toCoordinate(Qt.point(position.x + Kirigami.Units.gridUnit * 1.5, position.y), false));
    }

    /** Find out what is at @p position on the map: a point of interest or a public transport stop. */
    function lookupAt(position: point): void {
        // points of interest are shown from zoom level 15 on, below that a tap would just hit something random
        if (map.zoomLevel < 15) {
            if (!root.zoomHintShown) {
                root.zoomHintShown = true;
                applicationWindow().showPassiveNotification(i18nc("@info", "Zoom in to see details of places and stops."));
            }
            return;
        }
        const coord = map.toCoordinate(position);
        const radius = root.fingerRadius(position);
        placeLookup.lookup(coord, Math.max(radius, 10));
    }

    /** Show what was found at a tapped place: details if there is one obvious match, a list to choose from otherwise. */
    function showCandidates(candidates: var): void {
        if (candidates.length === 0) {
            // tapping on the empty map closes the details, unless a route is shown that would be lost then
            if (!root.tripShown) {
                root.clearSelection();
            }
            return;
        }
        // the list has stops first, see MapPlaceLookup, a place right where the map was tapped is meant though
        const nearest = candidates.slice().sort((lhs, rhs) => lhs.distance - rhs.distance);
        if (nearest.length === 1 || nearest[0].distance < nearest[1].distance * 0.35) {
            root.select(nearest[0]);
            return;
        }
        // A single stop next to things without a name of their own, such as a post box or a bench, is what
        // was tapped: its symbol stands out on the map, theirs aren't shown. The coordinate of a stop often
        // is a bit off from its symbol on the map though, so it doesn't need to be the nearest.
        const stops = candidates.filter((c) => c.type === "stop");
        if (stops.length === 1 && candidates.every((c) => c.type === "stop" || (c.amenity?.name ?? "") === "")) {
            root.select(stops[0]);
            return;
        }
        root.selection = undefined;
        sheetLoader.source = "";
        root.candidates = candidates.slice(0, 8);
        root.focusLater(placeLookup.coordinate);
    }

    function select(candidate: var): void {
        // the map stays where the new selection is
        root.tripViewport = undefined;
        root.candidates = [];
        root.selection = candidate;
        // a new sheet for each selection, so nothing of the previous one is left
        sheetLoader.source = "";
        sheetLoader.setSource(Qt.resolvedUrl(candidate.type === "stop" ? "MapStopSheet.qml" : "MapPlaceSheet.qml"), {
            place: candidate,
            maximumListHeight: root.sheetListHeight,
        });
        root.focusLater(QtPositioning.coordinate(candidate.latitude, candidate.longitude));
    }

    function clearSelection(): void {
        placeLookup.cancel();
        root.focusTarget = undefined;
        root.selection = undefined;
        root.candidates = [];
        sheetLoader.source = "";
    }

    /** Height available for lists in the sheet with details of a tapped place. */
    readonly property real sheetListHeight: Math.max(Kirigami.Units.gridUnit * 4,
        (root.height - root.visibleTop) * 0.5 - Kirigami.Units.gridUnit * 8)

    /** What to keep in view while the size of the sheet at the bottom changes, e.g. when its content is loaded:
     *  a coordinate, or "trip" for the shown trip. Until the user moves the map.
     */
    property var focusTarget

    function focusLater(what: var): void {
        root.focusTarget = what;
        focusTimer.restart();
    }

    Timer {
        id: focusTimer
        interval: 200
        onTriggered: root.applyFocus()
    }

    /** Top of the part of the map not hidden by the planner or the search. */
    readonly property real visibleTop: plannerPane.visible ? plannerPane.height : (searchPane.visible ? searchPane.height : 0)
    /** Bottom of the part of the map not hidden by the pane at the bottom, and the attribution of the map above it. */
    readonly property real visibleBottom: root.height - root.bottomPaneHeight - map.attribution.height - Kirigami.Units.largeSpacing

    /** Show the area @p bbox (x/y being longitude/latitude) within the part of the map that is not hidden. */
    function fitBoundingBox(bbox: rect): void {
        const margin = Kirigami.Units.gridUnit;
        const zoom = KPublicTransportUi.MapUtils.zoomLevel(bbox, map.width - margin * 2, root.visibleBottom - root.visibleTop - margin * 2);
        map.zoomLevel = isFinite(zoom) ? Math.min(zoom, 17) : 17;
        const center = KPublicTransportUi.MapUtils.center(bbox);
        root.centerOn(QtPositioning.coordinate(center.latitude, center.longitude));
    }

    /** The area containing all of @p coords, with x/y being longitude/latitude as for fitBoundingBox(). */
    function boundingBox(coords: var): rect {
        const lats = coords.map((c) => c.latitude);
        const lons = coords.map((c) => c.longitude);
        const minLat = Math.min(...lats);
        const minLon = Math.min(...lons);
        return Qt.rect(minLon, minLat, Math.max(...lons) - minLon, Math.max(...lats) - minLat);
    }

    /** Center the map on @p coord within the part of it that is not hidden. */
    function centerOn(coord: var): void {
        root.followPosition = false;
        map.alignCoordinateToPoint(coord, Qt.point(map.width / 2, (root.visibleTop + root.visibleBottom) / 2));
    }

    /** Move the map so that what was selected isn't hidden behind the planner at the top or the sheet at the bottom. */
    function applyFocus(): void {
        const what = root.focusTarget;
        if (what === undefined) {
            return;
        }
        const top = root.visibleTop;
        const bottom = root.visibleBottom;
        const margin = Kirigami.Units.gridUnit;
        if (what === "trip") {
            if (!root.tripShown) {
                return;
            }
            root.fitBoundingBox(KPublicTransportUi.MapUtils.boundingBox(sheetLoader.item.trip));
            return;
        }
        if (what === "journey") {
            const sections = root.shownJourney?.sections ?? [];
            if (root.focusedSection >= 0 && root.focusedSection < sections.length) {
                root.fitBoundingBox(KPublicTransportUi.MapUtils.boundingBox(sections[root.focusedSection]));
            } else if (sections.length > 0) {
                root.fitBoundingBox(KPublicTransportUi.MapUtils.boundingBox(root.shownJourney));
            } else if (root.previewTo) {
                // a route preview still being searched: where it starts and ends
                const from = root.previewFrom ?? (root.hasPosition ? root.currentLocation() : root.previewTo);
                root.fitBoundingBox(root.boundingBox([from, root.previewTo]));
            }
            return;
        }
        if (what === "endpoints") {
            const coords = root.journeyEndpointCoordinates();
            if (coords.length === 1) {
                root.centerOn(coords[0]);
            } else if (coords.length === 2) {
                root.fitBoundingBox(root.boundingBox(coords));
            }
            return;
        }
        if (what === "results") {
            // the found places, and where they were searched from
            let coords = placeSearch.results.map((r) => QtPositioning.coordinate(r.latitude, r.longitude));
            coords.push(placeSearch.center);
            const bbox = root.boundingBox(coords);
            if (bbox.width > 0 || bbox.height > 0) {
                map.zoomLevel = Math.min(KPublicTransportUi.MapUtils.zoomLevel(bbox, map.width - margin * 2, bottom - top - margin * 2), 17);
            }
            root.centerOn(QtPositioning.coordinate(bbox.y + bbox.height / 2, bbox.x + bbox.width / 2));
            return;
        }
        const pos = map.fromCoordinate(what, false);
        // the pin marking the selection is drawn above the coordinate
        if (pos.y < top + margin + Kirigami.Units.iconSizes.huge || pos.y > bottom - margin) {
            root.centerOn(what);
        }
    }

    /** The selected place or stop as departure or arrival of a journey, or as navigation destination. */
    function selectionLocation(): var {
        if (root.selection.type === "stop") {
            return root.selection.location;
        }
        return helper.locationAt(root.selection.latitude, root.selection.longitude, root.selection.name);
    }

    function setJourneyEndpointToSelection(endpoint: string): void {
        const location = root.selectionLocation();
        if (endpoint === "from") {
            root.journeyFrom = location;
        } else {
            root.journeyTo = location;
        }
        root.plannerShown = true;
        root.clearSelection();
        root.showJourneyEndpoints();
    }

    MapPlaceLookup {
        id: placeLookup
        onFinished: (candidates) => root.showCandidates(candidates)
    }

    function openSearch(): void {
        root.searchShown = true;
        // the pane at the bottom is needed for the search results
        markedRoutes.clearRoute();
        root.routeListShown = false;
        root.routeShown = false;
        if (placeSearch.active) {
            root.focusLater("results");
        } else {
            searchPane.focusSearchField();
        }
    }

    function closeSearch(): void {
        root.searchShown = false;
        placeSearch.clear();
        if (root.selection?.osmId !== undefined) {
            root.clearSelection();
        }
    }

    /** Search the text entered in the search pane, or the category @p categoryId if not empty. */
    function runSearch(categoryId: string): void {
        const text = searchPane.text.trim();
        if (text === "") {
            return;
        }
        root.clearSelection();
        root.amenityCache = {};
        const center = searchPane.aroundMe ? positionSource.position.coordinate
            : map.toCoordinate(Qt.point(map.width / 2, (root.visibleTop + root.visibleBottom) / 2), false);
        placeSearch.search(text, categoryId, center, searchPane.radius);
    }

    /** Show the details of a search result. */
    function selectSearchResult(result: var): void {
        const amenity = root.amenityCache[result.osmId];
        root.select(amenity ? Object.assign({}, result, { amenity: amenity }) : result);
    }

    MapPlaceSearch {
        id: placeSearch
        onFinished: {
            root.saveViewport();
            root.focusLater("results");
        }
        onActiveChanged: {
            if (!placeSearch.active && !root.journeyPaneShown) {
                root.restoreViewport();
            }
        }
    }

    /** Where the map was before it was moved to show search results, a journey or a route preview, to go back there
     *  when they are closed: center, zoomLevel and followPosition.
     */
    property var savedViewport

    /** Where the map was before it was moved to show the route of a trip from a stop, see savedViewport. */
    property var tripViewport

    /** The part of the world the map shows, for savedViewport and tripViewport. */
    function currentViewport(): var {
        // a copy, map.center would be a reference to the property, changing with it
        const center = QtPositioning.coordinate(map.center.latitude, map.center.longitude);
        return { center: center, zoomLevel: map.zoomLevel, followPosition: root.followPosition };
    }

    function applyViewport(viewport: var): void {
        map.zoomLevel = viewport.zoomLevel;
        map.center = viewport.center;
        root.followPosition = viewport.followPosition;
    }

    function saveViewport(): void {
        if (root.savedViewport === undefined) {
            root.savedViewport = root.currentViewport();
        }
    }

    function restoreViewport(): void {
        const viewport = root.savedViewport;
        if (viewport === undefined) {
            return;
        }
        root.savedViewport = undefined;
        if (root.focusTarget === "results" || root.focusTarget === "journey") {
            root.focusTarget = undefined;
        }
        root.applyViewport(viewport);
    }

    // back to where the map was when the route of a trip is closed, unless another place was selected meanwhile
    onTripShownChanged: {
        if (root.tripShown || root.tripViewport === undefined) {
            return;
        }
        const viewport = root.tripViewport;
        root.tripViewport = undefined;
        if (root.focusTarget === "trip") {
            root.focusTarget = undefined;
        }
        root.applyViewport(viewport);
    }
    /** Details of the found places loaded so far, by OSM element id, see MapSearchResultDelegate. */
    property var amenityCache: ({})

    function navigateToPickedPlace(mode: int): void {
        const coord = root.pickedCoordinate;
        root.previewRoute(undefined, helper.locationAt(coord.latitude, coord.longitude, i18nc("@info a place picked on the map", "Selected place")), mode);
        if (root.journeyPaneShown) {
            root.geocode(previewGeocoder, coord);
        }
    }

    // only used for its helper functions
    WalkingNavigationController {
        id: helper
    }

    MarkedRouteController {
        id: markedRoutes
        routeType: root.overlay === "" ? "hiking" : root.overlay
        onRouteChanged: {
            if (markedRoutes.hasRoute && !root.routeShown) {
                root.routeShown = true;
                root.followPosition = false;
                map.fitViewportToGeoShape(QtPositioning.path(KPublicTransportUi.MapUtils.polyline(markedRoutes.path)), Kirigami.Units.gridUnit * 2);
            }
        }
    }
    /** The loaded marked route has been brought into view. */
    property bool routeShown: false
    /** The list of routes at a tapped place is shown. */
    property bool routeListShown: false

    function followRoute(): void {
        const path = KPublicTransportUi.MapUtils.polyline(markedRoutes.path);
        const end = path[path.length - 1];
        root.QQC2.ApplicationWindow.window.pageStack.layers.push(Qt.createComponent("org.kde.itinerary", "WalkingNavigationPage"), {
            destination: helper.locationAt(end.latitude, end.longitude, markedRoutes.routeName),
            travelMode: root.overlay === "hiking" ? KPublicTransport.IndividualTransport.Walk : KPublicTransport.IndividualTransport.Bike,
            trail: markedRoutes.path,
            trailProfile: markedRoutes.elevationProfile,
        });
    }

    QQC2.ActionGroup { id: overlayGroup }
    actions: [
        Kirigami.Action {
            icon.name: "search"
            text: i18nc("@action:button search places such as shops or restaurants on the map", "Find Places")
            // the search icon tells what it is, leaving room for the journey planner
            displayHint: Kirigami.DisplayHint.IconOnly | Kirigami.DisplayHint.KeepVisible
            visible: !root.searchShown
            onTriggered: root.openSearch()
        },
        Kirigami.Action {
            icon.source: KPublicTransport.LineMode.iconName(KPublicTransport.Line.LocalTrain)
            text: i18nc("@action:button search a public transport connection between two places", "Plan Journey")
            visible: !root.plannerShown
            onTriggered: root.plannerShown = true
        },
        Kirigami.Action {
            text: i18nc("@action:inmenu map overlay", "Map Only")
            checkable: true
            checked: root.overlay === ""
            QQC2.ActionGroup.group: overlayGroup
            displayHint: Kirigami.DisplayHint.AlwaysHide
            onTriggered: root.overlay = ""
        },
        Kirigami.Action {
            text: i18nc("@action:inmenu map overlay", "Hiking Routes")
            checkable: true
            checked: root.overlay === "hiking"
            QQC2.ActionGroup.group: overlayGroup
            displayHint: Kirigami.DisplayHint.AlwaysHide
            onTriggered: root.overlay = "hiking"
        },
        Kirigami.Action {
            text: i18nc("@action:inmenu map overlay", "Cycling Routes")
            checkable: true
            checked: root.overlay === "cycling"
            QQC2.ActionGroup.group: overlayGroup
            displayHint: Kirigami.DisplayHint.AlwaysHide
            onTriggered: root.overlay = "cycling"
        },
        Kirigami.Action {
            text: i18nc("@action:inmenu map overlay", "Mountain Bike Routes")
            checkable: true
            checked: root.overlay === "mtb"
            QQC2.ActionGroup.group: overlayGroup
            displayHint: Kirigami.DisplayHint.AlwaysHide
            onTriggered: root.overlay = "mtb"
        }
    ]

    LocationPermission {
        id: locationPermission
        accuracy: LocationPermission.Precise
        availability: LocationPermission.WhenInUse
    }

    PositionSource {
        id: positionSource
        active: locationPermission.status === Qt.Granted && root.visible
        updateInterval: 2000
        onPositionChanged: {
            if (root.followPosition && positionSource.position.latitudeValid && positionSource.position.longitudeValid) {
                map.center = positionSource.position.coordinate;
            }
        }
    }

    MapView {
        id: map
        anchors.fill: parent
        zoomLevel: 15
        coveringItems: [plannerPane, searchPane, routePane, selectionPane, journeyPane]
        // keep the attribution visible above the pane at the bottom, using as little height as possible there
        attribution.anchors.bottomMargin: root.bottomPaneHeight + Kirigami.Units.largeSpacing
        attribution.width: Math.min(Kirigami.Units.gridUnit * 22, map.width - Kirigami.Units.largeSpacing * 2)

        onUserInteractingChanged: {
            if (map.userInteracting) {
                root.followPosition = false;
                root.focusTarget = undefined;
            }
        }

        // the current position
        QtLocation.MapQuickItem {
            visible: positionSource.valid && positionSource.position.latitudeValid
            coordinate: positionSource.position.coordinate
            anchorPoint.x: positionMarker.width / 2
            anchorPoint.y: positionMarker.height / 2
            z: 10
            sourceItem: Rectangle {
                id: positionMarker
                width: Kirigami.Units.gridUnit
                height: width
                radius: width / 2
                color: Kirigami.Theme.highlightColor
                border.color: "white"
                border.width: 3
            }
        }

        // the picked place
        MapCircle {
            visible: root.pickedCoordinate !== undefined
            coordinate: root.pickedCoordinate ?? QtPositioning.coordinate()
            color: "#232629"
            textColor: "#eff0f1"
            iconName: "flag"
            size: 24
        }

        // departure and arrival of the journey to search, along with the planner
        MapCircle {
            visible: root.journeyFrom !== undefined && root.plannerShown && !root.journeyPaneShown
            coordinate: root.journeyFrom ? QtPositioning.coordinate(root.journeyFrom.latitude, root.journeyFrom.longitude) : QtPositioning.coordinate()
            color: "#27ae60"
            textColor: "#eff0f1"
            iconName: "flag"
            size: 24
            z: 6
        }
        MapCircle {
            visible: root.journeyTo !== undefined && root.plannerShown && !root.journeyPaneShown
            coordinate: root.journeyTo ? QtPositioning.coordinate(root.journeyTo.latitude, root.journeyTo.longitude) : QtPositioning.coordinate()
            color: "#da4453"
            textColor: "#eff0f1"
            iconName: "flag"
            size: 24
            z: 6
        }

        // the shown journey: lines of public transport and of routes by bike or by car, dots along walks,
        // stops, line names, and where it starts and ends
        QtLocation.MapItemView {
            model: root.journeyPaneShown ? journeyDrawing.geometry.lines : []
            z: 4
            delegate: QtLocation.MapPolyline {
                id: journeyLineDelegate
                required property var modelData
                line.width: journeyLineDelegate.modelData.width
                line.color: journeyLineDelegate.modelData.color
                path: journeyLineDelegate.modelData.path
            }
        }
        QtLocation.MapItemView {
            model: root.journeyPaneShown ? journeyDrawing.walkDots : []
            z: 5
            delegate: QtLocation.MapQuickItem {
                id: walkDotDelegate
                required property var modelData
                coordinate: walkDotDelegate.modelData
                anchorPoint.x: walkDot.width / 2
                anchorPoint.y: walkDot.height / 2
                sourceItem: Rectangle {
                    id: walkDot
                    width: Math.round(Kirigami.Units.gridUnit * 0.5)
                    height: walkDot.width
                    radius: walkDot.width / 2
                    color: journeyDrawing.routeColor
                    border.color: "white"
                    border.width: 1
                }
            }
        }
        QtLocation.MapItemView {
            model: root.journeyPaneShown ? journeyDrawing.geometry.stops : []
            z: 6
            delegate: MapCircle {
                id: journeyStopDelegate
                required property var modelData
                coordinate: QtPositioning.coordinate(journeyStopDelegate.modelData.stopover.stopPoint.latitude, journeyStopDelegate.modelData.stopover.stopPoint.longitude)
                size: journeyStopDelegate.modelData.size
                borderWidth: journeyStopDelegate.modelData.size > 10 ? 2 : 1
                color: journeyStopDelegate.modelData.color
                textColor: "#eff0f1"
                onClicked: {
                    stopInfoDrawer.isDeparture = journeyStopDelegate.modelData.isDeparture;
                    stopInfoDrawer.isArrival = journeyStopDelegate.modelData.isArrival;
                    stopInfoDrawer.stop = journeyStopDelegate.modelData.stopover;
                    stopInfoDrawer.popup();
                }
            }
        }
        QtLocation.MapItemView {
            model: root.journeyPaneShown ? journeyDrawing.labels : []
            z: 7
            delegate: QtLocation.MapQuickItem {
                id: journeyLabelDelegate
                required property var modelData
                coordinate: journeyLabelDelegate.modelData.coordinate
                anchorPoint.x: journeyLabel.width / 2
                anchorPoint.y: journeyLabel.height / 2
                sourceItem: KPublicTransportUi.TransportNameControl {
                    id: journeyLabel
                    journeySection: journeyLabelDelegate.modelData.section
                }
            }
        }
        MapCircle {
            // a route preview from the current location starts at the marker of the location
            visible: root.journeyPaneShown && (journeyDrawing.geometry.start !== undefined || root.previewFrom !== undefined)
            coordinate: journeyDrawing.geometry.start ?? (root.previewFrom ? QtPositioning.coordinate(root.previewFrom.latitude, root.previewFrom.longitude) : QtPositioning.coordinate())
            color: "#27ae60"
            textColor: "#eff0f1"
            iconName: "flag"
            size: 24
            z: 8
        }
        MapCircle {
            visible: root.journeyPaneShown && (journeyDrawing.geometry.end !== undefined || root.previewTo !== undefined)
            coordinate: journeyDrawing.geometry.end ?? (root.previewTo ? QtPositioning.coordinate(root.previewTo.latitude, root.previewTo.longitude) : QtPositioning.coordinate())
            color: "#da4453"
            textColor: "#eff0f1"
            iconName: "flag"
            size: 24
            z: 8
        }

        // the route of the trip selected at a stop
        QtLocation.MapPolyline {
            visible: root.tripShown
            line.width: 8
            line.color: sheetLoader.item?.tripColor ?? "#232629"
            path: root.tripShown ? KPublicTransportUi.MapUtils.polyline(sheetLoader.item.trip) : []
            z: 4
        }
        QtLocation.MapItemView {
            model: root.tripShown ? sheetLoader.item.tripStops : []
            z: 5
            delegate: MapCircle {
                id: tripStopDelegate
                required property var modelData
                required property int index
                // the sheet can be gone before the delegates are
                readonly property bool isEnd: tripStopDelegate.index === 0 || tripStopDelegate.index === (sheetLoader.item?.tripStops?.length ?? 0) - 1
                coordinate: QtPositioning.coordinate(tripStopDelegate.modelData.stopPoint.latitude, tripStopDelegate.modelData.stopPoint.longitude)
                size: tripStopDelegate.isEnd ? 15 : 10
                borderWidth: tripStopDelegate.isEnd ? 2 : 1
                color: sheetLoader.item?.tripColor ?? "#232629"
                textColor: "#eff0f1"
                onClicked: {
                    root.focusTarget = undefined;
                    root.centerOn(tripStopDelegate.coordinate);
                }
            }
        }

        // places found by a search, and where they were searched from
        QtLocation.MapItemView {
            model: root.searchShown ? placeSearch.results : []
            z: 6
            delegate: MapCircle {
                id: resultDelegate
                required property var modelData
                coordinate: QtPositioning.coordinate(resultDelegate.modelData.latitude, resultDelegate.modelData.longitude)
                size: 24
                color: "#3daee9"
                textColor: "#eff0f1"
                iconName: resultDelegate.modelData.iconSource
                onClicked: root.selectSearchResult(resultDelegate.modelData)
            }
        }
        MapCircle {
            visible: root.searchShown && placeSearch.active && !(placeSearch.center.distanceTo(positionSource.position.coordinate) < 1)
            coordinate: placeSearch.center
            color: "#232629"
            textColor: "#eff0f1"
            iconName: "crosshairs"
            size: 20
            z: 5
        }

        // what was found at a tapped place, to choose from
        QtLocation.MapItemView {
            model: root.candidates
            z: 7
            delegate: MapCircle {
                id: candidateDelegate
                required property var modelData
                coordinate: QtPositioning.coordinate(candidateDelegate.modelData.latitude, candidateDelegate.modelData.longitude)
                size: 12
                color: Kirigami.Theme.highlightColor
                textColor: "#eff0f1"
                onClicked: root.select(candidateDelegate.modelData)
            }
        }

        // the place or stop whose details are shown
        MapPin {
            visible: root.selection !== undefined
            coordinate: root.selection ? QtPositioning.coordinate(root.selection.latitude, root.selection.longitude) : QtPositioning.coordinate()
            color: "#3daee9"
            textColor: "#eff0f1"
            iconName: root.selection?.iconSource ?? ""
            z: 8
        }

        // a tapped place, while looking up what is there
        QtLocation.MapQuickItem {
            visible: placeLookup.running
            coordinate: placeLookup.coordinate
            anchorPoint.x: lookupIndicator.width / 2
            anchorPoint.y: lookupIndicator.height / 2
            z: 9
            sourceItem: QQC2.BusyIndicator {
                id: lookupIndicator
                running: placeLookup.running
                width: Kirigami.Units.iconSizes.medium
                height: Kirigami.Units.iconSizes.medium
            }
        }

        // the marked route shown
        QtLocation.MapPolyline {
            visible: markedRoutes.hasRoute
            line.width: 8
            line.color: Kirigami.Theme.highlightColor
            path: KPublicTransportUi.MapUtils.polyline(markedRoutes.path)
            z: 5
        }

        TapHandler {
            id: mapTapHandler
            onTapped: (eventPoint) => {
                // a double tap zooms in, so a single tap is only handled once it can't become a double tap anymore
                if (mapTapHandler.tapCount >= 2) {
                    singleTapTimer.stop();
                    root.zoomInAt(eventPoint.position);
                    return;
                }
                singleTapTimer.position = eventPoint.position;
                singleTapTimer.restart();
            }
            onLongPressed: {
                singleTapTimer.stop();
                placeLookup.cancel();
                root.pickedCoordinate = map.toCoordinate(point.position);
                routeMenu.popup();
            }
        }
    }

    Timer {
        id: singleTapTimer
        property point position
        interval: Qt.styleHints.mouseDoubleClickInterval
        onTriggered: root.handleTap(singleTapTimer.position)
    }

    function handleTap(position: point): void {
        if (root.overlay === "") {
            root.lookupAt(position);
            return;
        }
        if (markedRoutes.hasRoute) {
            return;
        }
        // routes within a finger's width
        const coord = map.toCoordinate(position);
        const radius = root.fingerRadius(position);
        root.routeListShown = true;
        markedRoutes.findRoutes(coord.latitude, coord.longitude, radius);
    }

    /** Zoom in by one level, keeping the place at @p position where it is. */
    function zoomInAt(position: point): void {
        const coord = map.toCoordinate(position);
        root.followPosition = false;
        // a whole level more, rounding to a whole level would hardly zoom at all at times, e.g. from 15.9 to 16
        map.zoomLevel = Math.min(map.maximumZoomLevel, map.zoomLevel + 1);
        map.alignCoordinateToPoint(coord, position);
    }

    QQC2.Menu {
        id: routeMenu
        QQC2.MenuItem {
            icon.name: "mark-location-symbolic"
            text: i18nc("@action:inmenu", "Walk Here")
            onTriggered: root.navigateToPickedPlace(KPublicTransport.IndividualTransport.Walk)
        }
        QQC2.MenuItem {
            icon.name: "mark-location-symbolic"
            text: i18nc("@action:inmenu", "Cycle Here")
            onTriggered: root.navigateToPickedPlace(KPublicTransport.IndividualTransport.Bike)
        }
        QQC2.MenuItem {
            icon.name: "mark-location-symbolic"
            text: i18nc("@action:inmenu", "Drive Here")
            onTriggered: root.navigateToPickedPlace(KPublicTransport.IndividualTransport.Car)
        }
        QQC2.MenuSeparator {}
        QQC2.MenuItem {
            icon.name: "go-next-symbolic"
            text: i18nc("@action:inmenu search public transport connections starting here", "Journey From Here")
            onTriggered: root.setJourneyEndpoint("from", root.pickedCoordinate)
        }
        QQC2.MenuItem {
            icon.name: "flag"
            text: i18nc("@action:inmenu search public transport connections to here", "Journey To Here")
            onTriggered: root.setJourneyEndpoint("to", root.pickedCoordinate)
        }
    }

    /** The name of departure or arrival @p location in the planner, with the town for addresses found by a search,
     *  as their name is just the street.
     */
    function endpointName(location: var): string {
        const locality = location.locality ?? "";
        if (location.type !== KPublicTransport.Location.Address || locality === "" || location.name.includes(locality)) {
            return location.name;
        }
        return i18nc("@info a place in the journey planner, %1 is a street address, %2 a town", "%1, %2", location.name, locality);
    }

    // departure and arrival of a journey to search
    QQC2.Pane {
        id: plannerPane
        // a shown journey tells where it goes itself, and needs the room
        visible: root.plannerShown && !root.journeyPaneShown
        z: map.z + 3
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false

        component EndpointDelegate: QQC2.ItemDelegate {
            id: endpointDelegate
            required property string label
            required property string placeName
            required property color flagColor
            Layout.fillWidth: true
            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    source: "flag"
                    color: endpointDelegate.flagColor
                    isMask: true
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    QQC2.Label {
                        text: endpointDelegate.label
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        text: endpointDelegate.placeName
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    EndpointDelegate {
                        label: i18nc("departure train station", "From:")
                        placeName: root.journeyFrom ? root.endpointName(root.journeyFrom)
                            : root.hasPosition ? i18nc("@info start of navigation", "Current location")
                            : i18nc("@info:placeholder", "Search, or tap and hold on the map")
                        flagColor: "#27ae60"
                        onClicked: root.searchJourneyEndpoint("from")
                    }
                    Kirigami.Separator { Layout.fillWidth: true }
                    EndpointDelegate {
                        label: i18nc("arrival train station", "To:")
                        placeName: root.journeyTo ? root.endpointName(root.journeyTo) : i18nc("@info:placeholder", "Search, or tap and hold on the map")
                        flagColor: "#da4453"
                        onClicked: root.searchJourneyEndpoint("to")
                    }
                }
                ColumnLayout {
                    spacing: 0
                    QQC2.ToolButton {
                        icon.name: "window-close-symbolic"
                        text: i18nc("@action:button", "Close")
                        display: QQC2.AbstractButton.IconOnly
                        onClicked: {
                            root.plannerShown = false;
                            root.journeyFrom = undefined;
                            root.journeyTo = undefined;
                        }
                    }
                    QQC2.ToolButton {
                        icon.name: "reverse"
                        text: i18nc("departure and arrival stops", "Swap departure and arrival")
                        display: QQC2.AbstractButton.IconOnly
                        enabled: root.journeyTo !== undefined
                        onClicked: {
                            const from = root.journeyFrom ?? (root.hasPosition ? root.currentLocation() : undefined);
                            root.journeyFrom = root.journeyTo;
                            root.journeyTo = from;
                        }
                    }
                }
            }
            // how to get there: public transport connections, or navigation on foot, by bike or by car
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Layout.fillWidth: true

                component ModeButton: QQC2.Button {
                    display: QQC2.AbstractButton.TextUnderIcon
                    icon.width: Kirigami.Units.iconSizes.smallMedium
                    icon.height: Kirigami.Units.iconSizes.smallMedium
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1 // all equally wide
                }

                ModeButton {
                    icon.source: KPublicTransport.LineMode.iconName(KPublicTransport.Line.LocalTrain)
                    text: i18nc("@action:button search public transport connections, short", "Transit")
                    enabled: root.journeyTo !== undefined && (root.journeyFrom !== undefined || root.hasPosition)
                    onClicked: root.searchConnection()
                }
                ModeButton {
                    icon.source: KPublicTransport.IndividualTransportMode.modeIconName(KPublicTransport.IndividualTransport.Walk)
                    text: i18nc("@action:button navigate on foot", "Walk")
                    enabled: root.journeyTo !== undefined && (root.journeyFrom !== undefined || root.hasPosition)
                    onClicked: root.previewRoute(root.journeyFrom, root.journeyTo, KPublicTransport.IndividualTransport.Walk)
                }
                ModeButton {
                    icon.source: KPublicTransport.IndividualTransportMode.modeIconName(KPublicTransport.IndividualTransport.Bike)
                    text: i18nc("@action:button navigate by bike", "Bike")
                    enabled: root.journeyTo !== undefined && (root.journeyFrom !== undefined || root.hasPosition)
                    onClicked: root.previewRoute(root.journeyFrom, root.journeyTo, KPublicTransport.IndividualTransport.Bike)
                }
                ModeButton {
                    icon.source: KPublicTransport.IndividualTransportMode.modeIconName(KPublicTransport.IndividualTransport.Car)
                    text: i18nc("@action:button navigate by car", "Car")
                    enabled: root.journeyTo !== undefined && (root.journeyFrom !== undefined || root.hasPosition)
                    onClicked: root.previewRoute(root.journeyFrom, root.journeyTo, KPublicTransport.IndividualTransport.Car)
                }
            }
        }
    }

    // searching places by name or category
    MapSearchPane {
        id: searchPane
        visible: root.searchShown
        z: map.z + 3
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        hasPosition: root.hasPosition
        onSearchRequested: (categoryId) => root.runSearch(categoryId)
        onAreaEdited: {
            if (placeSearch.active) {
                root.runSearch(placeSearch.category.id ?? "");
            }
        }
        onCloseRequested: root.closeSearch()
    }

    QtLocation.Plugin {
        id: emptyOverlayPlugin
        name: "itemsoverlay"
    }

    // marked routes from Waymarked Trails, https://waymarkedtrails.org
    Component {
        id: trailsPluginComponent
        QtLocation.Plugin {
            name: "osm"
            QtLocation.PluginParameter { name: "osm.useragent"; value: ApplicationController.userAgent }
            QtLocation.PluginParameter { name: "osm.mapping.custom.host"; value: "https://tile.waymarkedtrails.org/" + root.overlay + "/%z/%x/%y.png" }
            QtLocation.PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: true }
            QtLocation.PluginParameter { name: "osm.mapping.custom.datacopyright"; value: "OpenStreetMap contributors" }
            QtLocation.PluginParameter { name: "osm.mapping.custom.mapcopyright"; value: "Waymarked Trails" }
            QtLocation.PluginParameter { name: "osm.mapping.cache.directory"; value: Util.cacheLocation("QtLocation-WaymarkedTrails/" + root.overlay) }
        }
    }

    Component {
        id: overlayMapComponent
        QtLocation.Map {
            anchors.fill: map
            center: map.center
            color: "transparent"
            minimumZoomLevel: map.minimumZoomLevel
            maximumZoomLevel: map.maximumZoomLevel
            zoomLevel: map.zoomLevel
            tilt: map.tilt
            bearing: map.bearing
            fieldOfView: map.fieldOfView
            copyrightsVisible: false
            z: map.z + 1
            // fade out other routes, so the selected one stands out
            opacity: markedRoutes.hasRoute ? 0.3 : 1.0
            // let input through to the map below
            enabled: false
        }
    }

    QQC2.Label {
        anchors {
            left: parent.left
            top: plannerPane.visible ? plannerPane.bottom : (searchPane.visible ? searchPane.bottom : parent.top)
            margins: Kirigami.Units.largeSpacing
        }
        visible: root.overlay !== ""
        text: i18nc("@info attribution of the hiking/cycling route overlay", "Routes: <a href=\"https://waymarkedtrails.org\">Waymarked Trails</a> (CC BY-SA)")
        textFormat: Text.RichText
        onLinkActivated: (link) => Qt.openUrlExternally(link)
        z: map.z + 2
        background: Rectangle {
            color: "#B0ffffff"
            radius: Kirigami.Units.cornerRadius
        }
        color: "#232629"
        padding: Kirigami.Units.smallSpacing
    }

    // routes at a tapped place, or the selected route
    QQC2.Pane {
        id: routePane
        visible: root.routeListShown || markedRoutes.hasRoute
        z: map.z + 3
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Image {
                    source: markedRoutes.routeSymbolUrl
                    visible: markedRoutes.hasRoute && markedRoutes.routeSymbolUrl !== ""
                    sourceSize.height: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    fillMode: Image.PreserveAspectFit
                }
                Kirigami.Heading {
                    level: 3
                    text: markedRoutes.hasRoute ? markedRoutes.routeName : i18nc("@title", "Marked Routes Here")
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                QQC2.BusyIndicator {
                    running: markedRoutes.loading
                    visible: running
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                }
                QQC2.ToolButton {
                    icon.name: "window-close-symbolic"
                    text: i18nc("@action:button", "Close")
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: {
                        markedRoutes.clearRoute();
                        root.routeListShown = false;
                        root.routeShown = false;
                    }
                }
            }

            QQC2.Label {
                text: markedRoutes.errorMessage
                visible: text !== ""
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.negativeTextColor
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: i18nc("@info", "No marked routes here. Tap on a route on the map.")
                visible: !markedRoutes.hasRoute && !markedRoutes.loading && markedRoutes.routes.length === 0 && markedRoutes.errorMessage === ""
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // the routes at the tapped place
            ListView {
                visible: !markedRoutes.hasRoute
                model: markedRoutes.routes
                clip: true
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, root.height * 0.35)
                delegate: QQC2.ItemDelegate {
                    id: routeDelegate
                    required property var modelData
                    width: ListView.view.width
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        Image {
                            source: routeDelegate.modelData.symbolUrl
                            sourceSize.height: Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                            Layout.preferredWidth: Kirigami.Units.iconSizes.medium * 1.5
                            fillMode: Image.PreserveAspectFit
                        }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            QQC2.Label {
                                text: routeDelegate.modelData.name !== "" ? routeDelegate.modelData.name : routeDelegate.modelData.ref
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            QQC2.Label {
                                text: routeDelegate.modelData.itinerary
                                visible: text !== ""
                                elide: Text.ElideRight
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                                Layout.fillWidth: true
                            }
                        }
                    }
                    onClicked: markedRoutes.loadRoute(routeDelegate.modelData.id)
                }
            }

            // the selected route
            QQC2.Label {
                visible: markedRoutes.hasRoute
                text: {
                    const length = CoreAddons.Format.formatDistance(markedRoutes.length, Settings.distanceFormat);
                    if (isNaN(markedRoutes.ascent)) {
                        return length;
                    }
                    return i18nc("@info route length, total ascent and descent", "%1 · ↑ %2 m · ↓ %3 m", length, Math.round(markedRoutes.ascent), Math.round(markedRoutes.descent));
                }
                Layout.fillWidth: true
            }
            QQC2.Label {
                visible: markedRoutes.hasRoute && text !== ""
                text: markedRoutes.routeDescription
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                opacity: 0.7
                Layout.fillWidth: true
            }
            ElevationProfile {
                visible: markedRoutes.hasRoute && markedRoutes.elevationProfile.length >= 2
                profile: markedRoutes.elevationProfile
                minElevation: markedRoutes.minElevation
                maxElevation: markedRoutes.maxElevation
                Layout.fillWidth: true
            }
            RowLayout {
                visible: markedRoutes.hasRoute
                Layout.fillWidth: true
                QQC2.Button {
                    icon.name: "mark-location-symbolic"
                    text: i18nc("@action:button", "Follow Route")
                    onClicked: root.followRoute()
                }
                QQC2.ToolButton {
                    icon.name: "exchange-positions"
                    text: i18nc("@action:button", "Reverse")
                    onClicked: markedRoutes.reverseRoute()
                }
                Item { Layout.fillWidth: true }
                QQC2.ToolButton {
                    icon.name: "internet-services"
                    text: i18nc("@action:button", "Website")
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: Qt.openUrlExternally(markedRoutes.routeWebUrl)
                }
            }
        }
    }

    /** Height of the pane at the bottom, if any. */
    readonly property real bottomPaneHeight: routePane.visible ? routePane.height
        : selectionPane.visible ? selectionPane.height
        : journeyPane.visible ? journeyPane.height
        : 0

    /** Search results are shown in the pane at the bottom. */
    readonly property bool searchResultsShown: root.searchShown && placeSearch.active && root.selection === undefined && root.candidates.length === 0

    // details of a place or stop tapped on the map or found by a search, a list to choose from if several were found
    // at a tapped place, or the search results
    QQC2.Pane {
        id: selectionPane
        visible: !routePane.visible && (root.selection !== undefined || root.candidates.length > 0 || root.searchResultsShown)
        z: map.z + 3
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false
        // the map can only be moved to show the selection once the size of this is known
        onHeightChanged: {
            if (root.focusTarget !== undefined) {
                focusTimer.restart();
            }
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            // search results
            RowLayout {
                visible: root.searchResultsShown
                spacing: Kirigami.Units.largeSpacing
                Layout.fillWidth: true
                Kirigami.Icon {
                    source: placeSearch.category.iconSource ?? "search"
                    isMask: true
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Kirigami.Heading {
                        level: 3
                        text: placeSearch.category.name ?? i18nc("@title search results for a name, %1 is the name", "“%1”", placeSearch.text)
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        text: {
                            const count = placeSearch.results.length;
                            const radius = CoreAddons.Format.formatDistance(placeSearch.radius, Settings.distanceFormat);
                            if (placeSearch.loading) {
                                return i18nc("@info", "Searching…");
                            }
                            if (placeSearch.errorMessage !== "" || count === 0) {
                                return "";
                            }
                            if (placeSearch.limitReached) {
                                return placeSearch.radius > 0 ? i18ncp("@info", "The nearest place within %2", "The nearest %1 places within %2", count, radius)
                                    : i18ncp("@info", "The nearest place", "The nearest %1 places", count);
                            }
                            return placeSearch.radius > 0 ? i18ncp("@info", "One place within %2", "%1 places within %2", count, radius)
                                : i18ncp("@info", "One place nearby", "%1 places nearby", count);
                        }
                        visible: text !== ""
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        Layout.fillWidth: true
                    }
                }
                QQC2.BusyIndicator {
                    running: placeSearch.loading
                    visible: running
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                }
                QQC2.ToolButton {
                    icon.name: "window-close-symbolic"
                    text: i18nc("@action:button", "Close")
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: root.closeSearch()
                }
            }
            QQC2.Label {
                visible: root.searchResultsShown && !placeSearch.loading && placeSearch.unnamedPlacesRadius > 0
                    && (placeSearch.radius === 0 || placeSearch.radius > placeSearch.unnamedPlacesRadius)
                text: i18nc("@info %1 is a distance", "Places without a name are only included within %1.",
                    CoreAddons.Format.formatDistance(placeSearch.unnamedPlacesRadius, Settings.distanceFormat))
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                Layout.fillWidth: true
            }
            QQC2.Label {
                visible: root.searchResultsShown && !placeSearch.loading && placeSearch.results.length === 0
                text: {
                    if (placeSearch.errorMessage !== "") {
                        return placeSearch.errorMessage;
                    }
                    return placeSearch.radius > 0 && placeSearch.radius < 16000 ? i18nc("@info", "Nothing found. Try a larger search area.")
                        : i18nc("@info", "Nothing found.");
                }
                color: placeSearch.errorMessage !== "" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            ListView {
                id: resultView
                visible: root.searchResultsShown
                model: placeSearch.results
                clip: true
                // only load details for the places actually shown
                cacheBuffer: 0
                boundsBehavior: Flickable.StopAtBounds
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(resultView.contentHeight, (root.height - root.visibleTop) * 0.5 - Kirigami.Units.gridUnit * 3)
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
                delegate: MapSearchResultDelegate {
                    id: resultRow
                    amenityCache: root.amenityCache
                    onClicked: root.selectSearchResult(resultRow.modelData)
                }
            }

            RowLayout {
                visible: root.selection === undefined && root.candidates.length > 0
                Layout.fillWidth: true
                Kirigami.Heading {
                    level: 3
                    text: i18nc("@title places found where the map was tapped", "Places Here")
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                QQC2.ToolButton {
                    icon.name: "window-close-symbolic"
                    text: i18nc("@action:button", "Close")
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: root.clearSelection()
                }
            }
            ListView {
                id: candidateView
                visible: root.selection === undefined && root.candidates.length > 0
                model: root.candidates
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(candidateView.contentHeight, root.sheetListHeight)
                delegate: MapPlaceDelegate {
                    id: candidateRow
                    onClicked: root.select(candidateRow.modelData)
                }
            }

            Loader {
                id: sheetLoader
                visible: root.selection !== undefined
                Layout.fillWidth: true
            }
            Binding {
                target: sheetLoader.item
                property: "maximumListHeight"
                value: root.sheetListHeight
                when: sheetLoader.item !== null
            }
            Connections {
                target: sheetLoader.item
                ignoreUnknownSignals: true
                function onCloseRequested(): void {
                    root.clearSelection();
                }
                function onNavigationRequested(mode: int): void {
                    root.previewRoute(undefined, root.selectionLocation(), mode);
                }
                function onJourneyEndpointRequested(endpoint: string): void {
                    root.setJourneyEndpointToSelection(endpoint);
                }
                function onTripReady(): void {
                    if (root.tripViewport === undefined) {
                        root.tripViewport = root.currentViewport();
                    }
                    root.focusLater("trip");
                }
                function onTripStopSelected(stopover: var): void {
                    root.focusTarget = undefined;
                    root.centerOn(QtPositioning.coordinate(stopover.stopPoint.latitude, stopover.stopPoint.longitude));
                }
            }
        }
    }

    // the shown journey, or route preview; a place or stop tapped meanwhile goes first
    MapJourneyPane {
        id: journeyPane
        visible: root.journeyPaneShown && !routePane.visible && !selectionPane.visible
        z: map.z + 3
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        journey: root.shownJourney
        travelMode: root.shownJourneyMode
        loading: root.shownJourneyMode >= 0 && previewModel.loading
        errorMessage: previewModel.errorMessage
        destinationName: root.previewTo?.name ?? ""
        canStart: root.isHere(root.previewFrom)
        currentPosition: root.hasPosition ? positionSource.position.coordinate : QtPositioning.coordinate()
        canShowResults: root.journeyResultsPage !== null && root.QQC2.ApplicationWindow.window !== null
            && root.QQC2.ApplicationWindow.window.pageStack.depth > 0 && root.journeyResultsPageIndex() >= 0
        currentSection: root.focusedSection
        maximumListHeight: root.sheetListHeight
        onHeightChanged: {
            if (root.focusTarget !== undefined) {
                focusTimer.restart();
            }
        }
        onCloseRequested: root.closeJourney()
        onResultsRequested: root.showJourneyResults()
        onSectionRequested: (index) => root.focusJourneySection(index)
        onTravelModeRequested: (mode) => root.changePreviewMode(mode)
        onStartRequested: root.startNavigation(root.previewTo, root.shownJourneyMode, root.shownJourney)
        onWalkToStopRequested: (stop) => root.QQC2.ApplicationWindow.window.pageStack.layers.push(Qt.createComponent("org.kde.itinerary", "WalkingNavigationPage"), {
            journey: root.shownJourney,
            destination: stop,
        })
    }

    Components.FloatingButton {
        icon.name: "mark-location-symbolic"
        text: i18nc("@action:button", "Follow my location")
        visible: !root.followPosition
        z: map.z + 2
        onClicked: {
            root.followPosition = true;
            if (positionSource.valid) {
                map.center = positionSource.position.coordinate;
            }
        }
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: Kirigami.Units.largeSpacing
            // above the attribution of the map
            bottomMargin: root.bottomPaneHeight + Kirigami.Units.gridUnit * 5
        }
    }
}
