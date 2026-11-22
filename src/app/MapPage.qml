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
        coveringItems: [plannerPane, routePane]

        onUserInteractingChanged: {
            if (map.userInteracting) {
                root.followPosition = false;
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
        if (root.overlay === "" || markedRoutes.hasRoute) {
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
            top: plannerPane.visible ? plannerPane.bottom : parent.top
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
            bottom: routePane.visible ? routePane.top : parent.bottom
            margins: Kirigami.Units.largeSpacing
            bottomMargin: routePane.visible ? Kirigami.Units.largeSpacing : Kirigami.Units.gridUnit * 5
        }
    }
}
