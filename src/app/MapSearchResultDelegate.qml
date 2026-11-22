// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

import QtQuick
import org.kde.kosmindoormap as KOSM
import org.kde.itinerary

/** List entry for a place found by MapPlaceSearch.
 *
 *  Details such as the opening hours are loaded from the OpenStreetMap data around the place
 *  only once the entry is shown for a moment, so scrolling through a long list doesn't
 *  load the data of every place passed.
 */
MapPlaceDelegate {
    id: root

    /** Details already loaded, by OSM element id, shared between entries so they are only loaded once.
     *  Null for places whose details could not be found.
     */
    required property var amenityCache

    amenity: undefined

    Component.onCompleted: {
        if (root.modelData.amenity) {
            root.amenity = root.modelData.amenity;
        } else if (root.amenityCache[root.modelData.osmId] !== undefined) {
            root.amenity = root.amenityCache[root.modelData.osmId] ?? undefined;
        } else if (root.modelData.osmId) {
            loadTimer.start();
        }
    }

    Timer {
        id: loadTimer
        interval: 400
        onTriggered: {
            // the element first, otherwise this would look for anything around the coordinate
            details.elementId = root.modelData.osmId;
            details.latitude = root.modelData.latitude;
            details.longitude = root.modelData.longitude;
        }
    }

    KOSM.NearbyAmenityModel {
        id: details
        radius: 30
        onFinished: {
            const amenity = details.count > 0 ? details.get(0) : null;
            // try again next time if the data couldn't be loaded
            if (details.errorMessage === "") {
                root.amenityCache[root.modelData.osmId] = amenity;
            }
            root.amenity = amenity ?? undefined;
        }
    }
}
