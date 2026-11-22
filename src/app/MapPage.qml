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
    /** The journey starts where we are, so navigating there on foot, by bike or by car is possible. */
    readonly property bool journeyStartsHere: root.hasPosition && (!root.journeyFrom
        || QtPositioning.coordinate(root.journeyFrom.latitude, root.journeyFrom.longitude).distanceTo(positionSource.position.coordinate) < 100)

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
        // name the place by its address
        const geocoder = endpoint === "from" ? fromGeocoder : toGeocoder;
        // the plugin is created on demand, which must not happen in a binding
        if (!geocoder.plugin) {
            geocoder.plugin = applicationWindow().geocodingPlugin();
        }
        geocoder.query = coord;
        geocoder.update();
    }

    /** Rename the departure or arrival to the address found for it, unless it changed meanwhile. */
    function applyGeocoding(endpoint: string, geocoder: QtLocation.GeocodeModel): void {
        const location = endpoint === "from" ? root.journeyFrom : root.journeyTo;
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
        const named = helper.locationAt(coord.latitude, coord.longitude, name);
        if (endpoint === "from") {
            root.journeyFrom = named;
        } else {
            root.journeyTo = named;
        }
    }

    function searchConnection(): void {
        const from = root.journeyFrom ?? root.currentLocation();
        const page = root.QQC2.ApplicationWindow.window.pageStack.push(Qt.resolvedUrl("JourneyRequestPage.qml"), {
            publicTransportManager: LiveDataManager.publicTransportManager,
            departureStop: from,
            arrivalStop: root.journeyTo,
        });
        page.searchJourney();
    }

    QtLocation.GeocodeModel {
        id: fromGeocoder
        autoUpdate: false
        limit: 1
        onStatusChanged: root.applyGeocoding("from", fromGeocoder)
    }
    QtLocation.GeocodeModel {
        id: toGeocoder
        autoUpdate: false
        limit: 1
        onStatusChanged: root.applyGeocoding("to", toGeocoder)
    }

    /** Show departure and arrival on the map, after one of them was searched. */
    function showJourneyEndpoints(): void {
        let coords = [];
        for (const location of [root.journeyFrom ?? (root.hasPosition ? root.currentLocation() : undefined), root.journeyTo]) {
            if (location && location.hasCoordinate) {
                coords.push(QtPositioning.coordinate(location.latitude, location.longitude));
            }
        }
        if (coords.length === 0) {
            return;
        }
        root.followPosition = false;
        if (coords.length === 1) {
            map.center = coords[0];
            return;
        }
        // with room for the journey planner on top
        map.fitViewportToGeoShape(QtPositioning.rectangle(coords), Kirigami.Units.gridUnit * 6);
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

    /** Navigate from the current position to @p destination, on foot, by bike or by car. */
    function startNavigation(destination: var, mode: int): void {
        root.QQC2.ApplicationWindow.window.pageStack.layers.push(Qt.createComponent("org.kde.itinerary", "WalkingNavigationPage"), {
            destination: destination,
            travelMode: mode,
        });
    }

    /** The place or stop tapped on the map whose details are shown, a candidate as found by MapPlaceLookup. */
    property var selection
    /** Several places or stops found at a tapped place, to choose from. */
    property var candidates: []
    /** The route of a public transport trip shown on the map, from a tapped stop. */
    readonly property bool tripShown: sheetLoader.item?.hasTrip ?? false

    /** Find out what is at @p position on the map: a point of interest or a public transport stop. */
    function lookupAt(position: point): void {
        // points of interest are shown from zoom level 15 on, below that a tap would just hit something random
        if (map.zoomLevel < 15) {
            return;
        }
        // within a finger's width
        const coord = map.toCoordinate(position);
        const radius = coord.distanceTo(map.toCoordinate(Qt.point(position.x + Kirigami.Units.gridUnit * 1.5, position.y)));
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
        if (candidates.length === 1 || candidates[0].distance < candidates[1].distance * 0.35) {
            root.select(candidates[0]);
            return;
        }
        root.selection = undefined;
        sheetLoader.source = "";
        root.candidates = candidates.slice(0, 8);
        root.focusLater(placeLookup.coordinate);
    }

    function select(candidate: var): void {
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
            const bbox = KPublicTransportUi.MapUtils.boundingBox(sheetLoader.item.trip);
            const center = KPublicTransportUi.MapUtils.center(bbox);
            map.zoomLevel = Math.min(KPublicTransportUi.MapUtils.zoomLevel(bbox, map.width - margin * 2, bottom - top - margin * 2), 17);
            root.centerOn(QtPositioning.coordinate(center.latitude, center.longitude));
            return;
        }
        if (what === "results") {
            // the found places, and where they were searched from
            let coords = placeSearch.results.map((r) => QtPositioning.coordinate(r.latitude, r.longitude));
            coords.push(placeSearch.center);
            const lats = coords.map((c) => c.latitude);
            const lons = coords.map((c) => c.longitude);
            const minLat = Math.min(...lats);
            const minLon = Math.min(...lons);
            const bbox = Qt.rect(minLon, minLat, Math.max(...lons) - minLon, Math.max(...lats) - minLat);
            if (bbox.width > 0 || bbox.height > 0) {
                map.zoomLevel = Math.min(KPublicTransportUi.MapUtils.zoomLevel(bbox, map.width - margin * 2, bottom - top - margin * 2), 17);
            }
            root.centerOn(QtPositioning.coordinate(minLat + bbox.height / 2, minLon + bbox.width / 2));
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
        onFinished: root.focusLater("results")
    }
    /** Details of the found places loaded so far, by OSM element id, see MapSearchResultDelegate. */
    property var amenityCache: ({})

    function navigateToPickedPlace(mode: int): void {
        root.startNavigation(helper.locationAt(root.pickedCoordinate.latitude, root.pickedCoordinate.longitude, i18nc("@info a place picked on the map", "Selected place")), mode);
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
        coveringItems: [plannerPane, searchPane, routePane, selectionPane]
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

        // departure and arrival of the journey to search
        MapCircle {
            visible: root.journeyFrom !== undefined
            coordinate: root.journeyFrom ? QtPositioning.coordinate(root.journeyFrom.latitude, root.journeyFrom.longitude) : QtPositioning.coordinate()
            color: "#27ae60"
            textColor: "#eff0f1"
            iconName: "flag"
            size: 24
            z: 6
        }
        MapCircle {
            visible: root.journeyTo !== undefined
            coordinate: root.journeyTo ? QtPositioning.coordinate(root.journeyTo.latitude, root.journeyTo.longitude) : QtPositioning.coordinate()
            color: "#da4453"
            textColor: "#eff0f1"
            iconName: "flag"
            size: 24
            z: 6
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
                readonly property bool isEnd: tripStopDelegate.index === 0 || tripStopDelegate.index === sheetLoader.item.tripStops.length - 1
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
        const radius = coord.distanceTo(map.toCoordinate(Qt.point(position.x + Kirigami.Units.gridUnit * 1.5, position.y)));
        root.routeListShown = true;
        markedRoutes.findRoutes(coord.latitude, coord.longitude, radius);
    }

    /** Zoom in by one level, keeping the place at @p position where it is. */
    function zoomInAt(position: point): void {
        const coord = map.toCoordinate(position);
        root.followPosition = false;
        map.zoomLevel = Math.min(map.maximumZoomLevel, Math.floor(map.zoomLevel + 1));
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

    // departure and arrival of a journey to search
    QQC2.Pane {
        id: plannerPane
        visible: root.plannerShown
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
                        placeName: root.journeyFrom ? root.journeyFrom.name
                            : root.hasPosition ? i18nc("@info start of navigation", "Current location")
                            : i18nc("@info:placeholder", "Search, or tap and hold on the map")
                        flagColor: "#27ae60"
                        onClicked: root.searchJourneyEndpoint("from")
                    }
                    Kirigami.Separator { Layout.fillWidth: true }
                    EndpointDelegate {
                        label: i18nc("arrival train station", "To:")
                        placeName: root.journeyTo ? root.journeyTo.name : i18nc("@info:placeholder", "Search, or tap and hold on the map")
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
                    enabled: root.journeyTo !== undefined && root.journeyStartsHere
                    onClicked: root.startNavigation(root.journeyTo, KPublicTransport.IndividualTransport.Walk)
                }
                ModeButton {
                    icon.source: KPublicTransport.IndividualTransportMode.modeIconName(KPublicTransport.IndividualTransport.Bike)
                    text: i18nc("@action:button navigate by bike", "Bike")
                    enabled: root.journeyTo !== undefined && root.journeyStartsHere
                    onClicked: root.startNavigation(root.journeyTo, KPublicTransport.IndividualTransport.Bike)
                }
                ModeButton {
                    icon.source: KPublicTransport.IndividualTransportMode.modeIconName(KPublicTransport.IndividualTransport.Car)
                    text: i18nc("@action:button navigate by car", "Car")
                    enabled: root.journeyTo !== undefined && root.journeyStartsHere
                    onClicked: root.startNavigation(root.journeyTo, KPublicTransport.IndividualTransport.Car)
                }
            }
            QQC2.Label {
                text: i18nc("@info", "Navigation on foot, by bike or by car starts at your location.")
                visible: root.journeyTo !== undefined && !root.journeyStartsHere
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                Layout.fillWidth: true
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
    readonly property real bottomPaneHeight: routePane.visible ? routePane.height : (selectionPane.visible ? selectionPane.height : 0)

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
                    root.startNavigation(root.selectionLocation(), mode);
                }
                function onJourneyEndpointRequested(endpoint: string): void {
                    root.setJourneyEndpointToSelection(endpoint);
                }
                function onTripReady(): void {
                    root.focusLater("trip");
                }
                function onTripStopSelected(stopover: var): void {
                    root.focusTarget = undefined;
                    root.centerOn(QtPositioning.coordinate(stopover.stopPoint.latitude, stopover.stopPoint.longitude));
                }
            }
        }
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
