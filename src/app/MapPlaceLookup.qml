// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtPositioning
import org.kde.kosmindoormap as KOSM
import org.kde.kpublictransport as KPublicTransport
import org.kde.itinerary

/** Finds what is at a place tapped on the map: points of interest from OpenStreetMap,
 *  and public transport stops.
 *
 *  The result is passed to finished() as a list of candidates, nearest first. Each candidate is an object with
 *  - type: "place" or "stop"
 *  - name, typeName, iconSource: for showing it in a list
 *  - latitude, longitude, distance: where it is, and how far from the tapped point in metres
 *  - amenity: all NearbyAmenityModel roles of a place
 *  - location: the KPublicTransport location of a stop
 *
 *  Things within the search radius come first. Areas containing the tapped point (such as a park
 *  or a school) are only included when there is nothing within the radius.
 */
Item {
    id: root

    visible: false

    /** A lookup is running. */
    readonly property bool running: root.amenitiesPending || root.stopsPending
    /** Where the running or last lookup is for. */
    property var coordinate: QtPositioning.coordinate()

    /** Emitted with the found candidates (possibly none) when a lookup is complete. */
    signal finished(candidates: var)

    /** Find points of interest and stops within @p radius metres around @p coordinate. */
    function lookup(coordinate: var, radius: real): void {
        root.coordinate = coordinate;
        root.radius = radius;
        root.amenitiesPending = true;
        root.stopsPending = true;

        amenities.latitude = coordinate.latitude;
        amenities.longitude = coordinate.longitude;
        amenities.radius = radius;
        amenities.reload();

        if (root.stopCacheCovers(coordinate)) {
            root.stopsPending = false;
            root.finishIfComplete();
            return;
        }
        root.stopCache = [];
        root.stopCacheRadius = 0;
        root.stopCacheCenter = coordinate;
        stopTimeout.restart();
        // setting the request cancels a still running query, that must not count as done
        root.stopQueryRunning = false;
        stopQuery.request = {
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            types: KPublicTransport.Location.Stop,
            maximumDistance: root.stopSearchRadius,
            maximumResults: 50,
        };
    }

    /** Abort a running lookup, without emitting finished(). */
    function cancel(): void {
        root.amenitiesPending = false;
        root.stopsPending = false;
        stopTimeout.stop();
        stopQuery.cancel();
    }

    // internal
    property real radius: 0
    property bool amenitiesPending: false
    property bool stopsPending: false
    property bool stopQueryRunning: false

    // Stops are searched in a larger area than a tap and kept, so further taps nearby
    // don't need to wait for the network.
    readonly property int stopSearchRadius: 300
    property var stopCache: []
    property var stopCacheCenter: QtPositioning.coordinate()
    property real stopCacheRadius: 0
    property date stopCacheTime

    function stopCacheCovers(coordinate: var): bool {
        return root.stopCacheRadius > 0 && root.stopCacheCenter.isValid
            && (Date.now() - root.stopCacheTime.getTime()) < 15 * 60 * 1000
            && root.stopCacheCenter.distanceTo(coordinate) + root.radius * 2 <= root.stopCacheRadius;
    }

    function collectStops(complete: bool): void {
        let stops = [];
        let maxDistance = 0;
        for (let i = 0; i < stopQuery.rowCount(); ++i) {
            const loc = stopQuery.data(stopQuery.index(i, 0), KPublicTransport.LocationQueryModel.LocationRole);
            // a stop search can also return addresses and other places
            if (loc.type !== KPublicTransport.Location.Stop || !loc.hasCoordinate || loc.name === "") {
                continue;
            }
            stops.push(loc);
            maxDistance = Math.max(maxDistance, root.stopCacheCenter.distanceTo(QtPositioning.coordinate(loc.latitude, loc.longitude)));
        }
        root.stopCache = stops;
        root.stopCacheTime = new Date();
        // backends might only return the nearest few stops, the area beyond the farthest one is unknown then
        root.stopCacheRadius = complete ? (stops.length >= 8 ? Math.min(maxDistance, root.stopSearchRadius) : root.stopSearchRadius) : 0;
    }

    function finishIfComplete(): void {
        if (root.amenitiesPending || root.stopsPending) {
            return;
        }

        let near = [];
        let areas = [];
        for (let i = 0; i < amenities.count; ++i) {
            const amenity = amenities.get(i);
            const candidate = {
                type: "place",
                name: amenity.name !== "" ? amenity.name : (amenity.fallbackName !== "" ? amenity.fallbackName : amenity.typeName),
                typeName: amenity.typeName,
                iconSource: amenity.iconSource,
                latitude: amenity.coordinate.y,
                longitude: amenity.coordinate.x,
                distance: amenity.distance,
                amenity: amenity,
            };
            if (amenity.distance <= root.radius) {
                near.push(candidate);
            } else {
                areas.push(candidate);
            }
        }

        // stop coordinates of public transport data often differ a bit from where the map shows them
        const stopRadius = Math.max(root.radius * 1.5, 40);
        let names = [];
        for (const loc of root.stopCache) {
            const distance = root.coordinate.distanceTo(QtPositioning.coordinate(loc.latitude, loc.longitude));
            if (distance > stopRadius || names.includes(loc.name)) {
                continue;
            }
            names.push(loc.name);
            near.push({
                type: "stop",
                name: loc.name,
                typeName: i18nc("@info a place on the map", "Public transport stop"),
                iconSource: loc.iconName,
                latitude: loc.latitude,
                longitude: loc.longitude,
                distance: distance,
                location: loc,
            });
        }

        let candidates = near.length > 0 ? near : areas;
        candidates.sort((lhs, rhs) => lhs.distance - rhs.distance);
        root.finished(candidates);
    }

    KOSM.NearbyAmenityModel {
        id: amenities
        onFinished: {
            if (root.amenitiesPending) {
                root.amenitiesPending = false;
                root.finishIfComplete();
            }
        }
    }

    KPublicTransport.LocationQueryModel {
        id: stopQuery
        manager: LiveDataManager.publicTransportManager
        onLoadingChanged: {
            if (stopQuery.loading) {
                root.stopQueryRunning = true;
            } else if (root.stopQueryRunning && root.stopsPending) {
                root.stopQueryRunning = false;
                stopTimeout.stop();
                root.collectStops(true);
                root.stopsPending = false;
                root.finishIfComplete();
            }
        }
    }

    // don't let a slow backend delay showing what was found
    Timer {
        id: stopTimeout
        interval: 5000
        onTriggered: {
            if (root.stopsPending) {
                root.collectStops(false);
                root.stopsPending = false;
                root.finishIfComplete();
            }
        }
    }
}
