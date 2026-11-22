// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtLocation as QtLocation
import QtPositioning
import org.kde.kirigami as Kirigami
import org.kde.kpublictransport as KPublicTransport
import org.kde.kpublictransport.ui as KPublicTransportUi

/** What to draw on a map for a journey: public transport lines in their colors with their stops and line labels,
 *  routes on foot, by bike or by car, and walks as dots, as map lines can't be dashed.
 *  Dots and labels are placed for the current zoom level of the map, and updated when it changes.
 */
QtObject {
    id: root

    /** The journey to draw. */
    property var journey
    /** The map it is drawn on, for spacing walk dots and placing labels at its current zoom level. */
    required property QtLocation.Map mapView

    /** What to draw: lines, walks, stops and labels with their coordinates, and where the journey starts and ends. */
    readonly property var geometry: root.buildJourneyGeometry(root.journey)

    /** Lines, stops, labels and walks of @p journey, to draw on the map. */
    function buildJourneyGeometry(journey: var): var {
        let geometry = { lines: [], walks: [], stops: [], labels: [], start: undefined, end: undefined };
        if (!journey || journey.sections.length === 0) {
            return geometry;
        }
        const sections = journey.sections;
        for (const section of sections) {
            const path = KPublicTransportUi.MapUtils.polyline(section);
            switch (section.mode) {
            case KPublicTransport.JourneySection.PublicTransport: {
                const line = section.route.line;
                // hardcoded Breeze black, as there is no theme color with enough contrast to the map in all themes
                const color = line.hasColor ? line.color : "#232629";
                geometry.lines.push({ path: path, color: color, width: line.mode === KPublicTransport.Line.Air ? 3 : 8 });
                geometry.stops.push({ stopover: section.departure, color: color, size: 14, isDeparture: true, isArrival: false });
                for (const stop of section.intermediateStops) {
                    geometry.stops.push({ stopover: stop, color: color, size: 7, isDeparture: false, isArrival: false });
                }
                geometry.stops.push({ stopover: section.arrival, color: color, size: 14, isDeparture: false, isArrival: true });
                const middle = root.pathMiddle(path);
                if (middle) {
                    geometry.labels.push({ section: section, coordinate: middle, length: root.pathLength(path) });
                }
                break;
            }
            case KPublicTransport.JourneySection.Walking:
            case KPublicTransport.JourneySection.Transfer:
                if (path.length >= 2) {
                    geometry.walks.push(path);
                }
                break;
            case KPublicTransport.JourneySection.IndividualTransport:
            case KPublicTransport.JourneySection.RentedVehicle:
                geometry.lines.push({ path: path, color: root.routeColor, width: 6 });
                break;
            }
        }
        const from = sections[0].from;
        const to = sections[sections.length - 1].to;
        if (from.hasCoordinate) {
            geometry.start = QtPositioning.coordinate(from.latitude, from.longitude);
        }
        if (to.hasCoordinate) {
            geometry.end = QtPositioning.coordinate(to.latitude, to.longitude);
        }
        return geometry;
    }

    /** Color of routes on foot, by bike or by car. */
    readonly property color routeColor: "#2980b9"

    /** Distance in meters between two coordinates, precise enough for short distances. */
    function roughDistance(a: var, b: var): real {
        const cosLat = Math.cos((a.latitude + b.latitude) / 2 * Math.PI / 180);
        const dx = (b.longitude - a.longitude) * cosLat;
        const dy = b.latitude - a.latitude;
        return Math.sqrt(dx * dx + dy * dy) * 111195;
    }

    /** Length of @p path in meters. */
    function pathLength(path: var): real {
        let length = 0;
        for (let i = 0; i + 1 < path.length; ++i) {
            length += root.roughDistance(path[i], path[i + 1]);
        }
        return length;
    }

    /** The point halfway along @p path, e.g. to label a line there. */
    function pathMiddle(path: var): var {
        if (path.length === 0) {
            return undefined;
        }
        let remaining = root.pathLength(path) / 2;
        for (let i = 0; i + 1 < path.length; ++i) {
            const d = root.roughDistance(path[i], path[i + 1]);
            if (d >= remaining && d > 0) {
                const t = remaining / d;
                return QtPositioning.coordinate(path[i].latitude + t * (path[i + 1].latitude - path[i].latitude),
                                                path[i].longitude + t * (path[i + 1].longitude - path[i].longitude));
            }
            remaining -= d;
        }
        return QtPositioning.coordinate(path[0].latitude, path[0].longitude);
    }

    /** Dots along the walks of the journey, within and around the visible part of the map.
     *  Map lines can't be dashed, so walks are drawn as dots, spaced evenly on screen at the current zoom level.
     */
    property var walkDots: []

    /** The line labels of the journey that fit on the map at the current zoom level: not for lines too short
     *  to tell them apart there, nor where they would hide other labels or where the journey starts and ends.
     */
    property var labels: []

    function updateLabels(metersPerPixel: real): void {
        const geometry = root.geometry;
        // about the width of a label
        const minDistance = Kirigami.Units.gridUnit * 4 * metersPerPixel;
        let taken = [geometry.start, geometry.end].filter((coord) => coord !== undefined);
        let labels = [];
        // the longest lines first, as they matter most for the whole journey
        for (const label of geometry.labels.slice().sort((lhs, rhs) => rhs.length - lhs.length)) {
            if (label.length < minDistance || taken.some((coord) => coord.distanceTo(label.coordinate) < minDistance)) {
                continue;
            }
            labels.push(label);
            taken.push(label.coordinate);
        }
        // not when only moving the map, as that would create all labels again
        if (labels.length !== root.labels.length || labels.some((label, i) => label !== root.labels[i])) {
            root.labels = labels;
        }
    }

    function update(): void {
        if (root.mapView.width <= 0) {
            return;
        }
        const center = root.mapView.toCoordinate(Qt.point(root.mapView.width / 2, root.mapView.height / 2), false);
        const metersPerPixel = center.distanceTo(root.mapView.toCoordinate(Qt.point(root.mapView.width / 2 + 100, root.mapView.height / 2), false)) / 100;
        if (!(metersPerPixel > 0)) {
            return;
        }
        root.updateLabels(metersPerPixel);
        const walks = root.geometry.walks;
        if (walks.length === 0) {
            root.walkDots = [];
            return;
        }
        const spacing = metersPerPixel * Kirigami.Units.gridUnit * 0.8;
        // the visible part of the map, and as much around it, for moving the map a bit without dots missing
        const topLeft = root.mapView.toCoordinate(Qt.point(-root.mapView.width, -root.mapView.height), false);
        const bottomRight = root.mapView.toCoordinate(Qt.point(root.mapView.width * 2, root.mapView.height * 2), false);
        const bounded = topLeft.isValid && bottomRight.isValid;
        const minLat = Math.min(topLeft.latitude, bottomRight.latitude);
        const maxLat = Math.max(topLeft.latitude, bottomRight.latitude);
        const minLon = Math.min(topLeft.longitude, bottomRight.longitude);
        const maxLon = Math.max(topLeft.longitude, bottomRight.longitude);
        let dots = [];
        for (const path of walks) {
            let offset = spacing / 2;
            for (let i = 0; i + 1 < path.length && dots.length < 2000; ++i) {
                const a = path[i];
                const b = path[i + 1];
                const length = root.roughDistance(a, b);
                for (; offset < length && dots.length < 2000; offset += spacing) {
                    const t = offset / length;
                    const lat = a.latitude + t * (b.latitude - a.latitude);
                    const lon = a.longitude + t * (b.longitude - a.longitude);
                    if (!bounded || (lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon)) {
                        dots.push(QtPositioning.coordinate(lat, lon));
                    }
                }
                offset -= length;
            }
        }
        root.walkDots = dots;
    }
    onGeometryChanged: updateTimer.restart()

    readonly property Timer updateTimer: Timer {
        id: updateTimer
        interval: 100
        onTriggered: root.update()
    }
    readonly property Connections mapConnections: Connections {
        target: root.mapView
        // walk dots and labels depend on the zoom level
        enabled: root.geometry.walks.length > 0 || root.geometry.labels.length > 0
        function onZoomLevelChanged(): void {
            updateTimer.restart();
        }
        function onCenterChanged(): void {
            updateTimer.restart();
        }
        function onWidthChanged(): void {
            updateTimer.restart();
        }
        function onHeightChanged(): void {
            updateTimer.restart();
        }
    }
}
