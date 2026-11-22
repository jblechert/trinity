// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtPositioning
import org.kde.kosmindoormap as KOSM
import org.kde.itinerary

/** Finds what is at a place tapped on the map: points of interest from OpenStreetMap.
 *
 *  The result is passed to finished() as a list of candidates, nearest first. Each candidate is an object with
 *  - type: "place"
 *  - name, typeName, iconSource: for showing it in a list
 *  - latitude, longitude, distance: where it is, and how far from the tapped point in metres
 *  - amenity: all NearbyAmenityModel roles of a place
 *
 *  Things within the search radius come first. Areas containing the tapped point (such as a park
 *  or a school) are only included when there is nothing within the radius.
 */
Item {
    id: root

    visible: false

    /** A lookup is running. */
    readonly property bool running: root.amenitiesPending
    /** Where the running or last lookup is for. */
    property var coordinate: QtPositioning.coordinate()

    /** Emitted with the found candidates (possibly none) when a lookup is complete. */
    signal finished(candidates: var)

    /** Find points of interest within @p radius metres around @p coordinate. */
    function lookup(coordinate: var, radius: real): void {
        root.coordinate = coordinate;
        root.radius = radius;
        root.amenitiesPending = true;

        amenities.latitude = coordinate.latitude;
        amenities.longitude = coordinate.longitude;
        amenities.radius = radius;
        amenities.reload();
    }

    /** Abort a running lookup, without emitting finished(). */
    function cancel(): void {
        root.amenitiesPending = false;
    }

    // internal
    property real radius: 0
    property bool amenitiesPending: false

    function finishIfComplete(): void {
        if (root.amenitiesPending) {
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
}
