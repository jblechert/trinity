// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtPositioning
import org.kde.kosmindoormap as KOSM
import org.kde.kpublictransport as KPublicTransport
import org.kde.itinerary

/** Searches places such as shops or restaurants around a given point, by category or by name.
 *
 *  Results are candidates in the same form as found by MapPlaceLookup, nearest first, but without
 *  the amenity details (such as opening hours), which have to be looked up separately by their
 *  OSM element id. Each result has
 *  - type: "place"
 *  - name, typeName, iconSource: for showing it in a list
 *  - latitude, longitude, distance: where it is, and how far from the search center in metres
 *  - osmId: the OSM element, e.g. "n123", "w123" or "r123"
 *  - address: street and locality, if known
 *  - amenity: all NearbyAmenityModel roles, for places found in the map data around the search center
 *
 *  Places are searched with Photon, which only knows places with a name or an address. Places
 *  of the searched category without (such as most toilets or charging stations) are added from
 *  the OpenStreetMap data within a few hundred metres of the search center, for categories whose
 *  places usually have no name, or if Photon finds few places.
 */
QtObject {
    id: root

    /** A search was started and not cleared since. */
    readonly property bool active: root.text !== ""
    /** The search text. */
    property string text
    /** The category searched for, as from PlaceCategories, or an empty object when searching by name. */
    property var category: ({})
    /** Center of the search. */
    property var center: QtPositioning.coordinate()
    /** Search radius in metres, 0 for searching the nearest places. */
    property int radius: 0
    /** Most results a search returns, there might be more places matching then. */
    readonly property int maximumResults: root.radius > 0 ? 50 : 20
    /** The search was limited to maximumResults. */
    property bool limitReached: false
    /** Places without a name were only searched within this distance from the center (in metres), 0 if not at all. */
    property int unnamedPlacesRadius: 0

    /** Found places, nearest first. */
    property var results: []
    readonly property bool loading: query.loading || root.mapDataPending
    readonly property string errorMessage: query.errorMessage

    /** Emitted when a search is complete. */
    signal finished()

    /** Search for @p text around @p center, within @p radius metres (or the nearest places if 0).
     *  @p text is either the name of a category (see PlaceCategories) or the name of a place.
     *  @p categoryId forces searching that category, regardless of @p text.
     */
    function search(text: string, categoryId: string, center: var, radius: int): void {
        root.text = text;
        root.category = categoryId !== "" ? PlaceCategories.category(categoryId) : PlaceCategories.categoryForText(text);
        root.center = center;
        root.radius = radius;
        root.results = [];
        root.limitReached = false;
        root.unnamedPlacesRadius = 0;
        root.mapDataPending = false;

        let request = {
            latitude: center.latitude,
            longitude: center.longitude,
            types: KPublicTransport.Location.PointOfInterest,
            // "nearby" means the nearest places, but there have to be limits
            maximumDistance: radius > 0 ? radius : 25000,
            maximumResults: root.maximumResults,
        };
        if (root.category.id !== undefined) {
            request.osmTags = root.category.osmTags;
        } else {
            request.name = text;
        }
        root.queryRunning = false;
        query.request = request;
    }

    /** Clear the search and its results. */
    function clear(): void {
        query.cancel();
        root.queryRunning = false;
        root.mapDataPending = false;
        root.text = "";
        root.category = {};
        root.results = [];
        root.limitReached = false;
        root.unnamedPlacesRadius = 0;
    }

    // internal
    property bool queryRunning: false
    property bool mapDataPending: false
    /** Radius around the search center in which the map data is searched, in metres. */
    readonly property int mapDataRadius: 250

    function collectResults(): void {
        let results = [];
        let ids = [];
        for (let i = 0; i < query.rowCount(); ++i) {
            const loc = query.data(query.index(i, 0), KPublicTransport.LocationQueryModel.LocationRole);
            if (!loc.hasCoordinate) {
                continue;
            }
            const osmId = loc.identifier("osm");
            const coordinate = QtPositioning.coordinate(loc.latitude, loc.longitude);
            const distance = root.center.distanceTo(coordinate);
            // the same place can be in the data several times, e.g. as a shop and its outdoor seating
            if ((osmId !== "" && ids.includes(osmId))
                || results.some((r) => r.name === loc.name && QtPositioning.coordinate(r.latitude, r.longitude).distanceTo(coordinate) < 30)) {
                continue;
            }
            ids.push(osmId);

            const key = loc.tagKeys.length > 0 ? loc.tagKeys[0] : "";
            let category = key !== "" ? PlaceCategories.categoryForTag(key, loc.tagValue(key)) : {};
            if (category.id === undefined && root.category.id !== undefined) {
                category = root.category;
            }
            results.push({
                type: "place",
                name: loc.name !== "" ? loc.name : (category.name ?? ""),
                typeName: category.name ?? "",
                iconSource: category.iconSource ?? loc.iconName,
                latitude: loc.latitude,
                longitude: loc.longitude,
                distance: distance,
                osmId: osmId,
                address: [loc.streetAddress, loc.locality].filter((s) => s).join(", "),
            });
        }
        results.sort((lhs, rhs) => lhs.distance - rhs.distance);
        root.limitReached = query.rowCount() >= root.maximumResults;
        root.results = results;
    }

    /** Checks whether the place @p amenity of NearbyAmenityModel is in the searched category. */
    function inCategory(amenity: var): bool {
        return root.category.osmTags.some((tag) => {
            const [key, value] = tag.split("=");
            return amenity.element.tagValue(key) === value;
        });
    }

    /** Add the places of the searched category from the map data around the search center. */
    function addMapData(): void {
        let results = root.results.slice();
        for (let i = 0; i < mapData.count; ++i) {
            const amenity = mapData.get(i);
            if (amenity.distance > mapData.radius || !root.inCategory(amenity)) {
                continue;
            }
            // NearbyAmenityModel doesn't tell the OSM id itself yet, only as part of the URL of the element
            const types = { node: "n", way: "w", relation: "r" };
            const match = amenity.element.url.match(/\/(node|way|relation)\/(\d+)$/);
            const osmId = match ? types[match[1]] + match[2] : "";
            if (osmId !== "" && results.some((r) => r.osmId === osmId)) {
                continue;
            }
            results.push({
                type: "place",
                name: amenity.name !== "" ? amenity.name : (amenity.typeName !== "" ? amenity.typeName : root.category.name),
                typeName: amenity.typeName !== "" ? amenity.typeName : root.category.name,
                iconSource: root.category.iconSource,
                latitude: amenity.coordinate.y,
                longitude: amenity.coordinate.x,
                distance: amenity.distance,
                osmId: osmId,
                address: "",
                amenity: amenity,
            });
        }
        results.sort((lhs, rhs) => lhs.distance - rhs.distance);
        root.results = results;
        root.unnamedPlacesRadius = mapData.radius;
    }

    readonly property KPublicTransport.LocationQueryModel queryModel: KPublicTransport.LocationQueryModel {
        id: query
        manager: LiveDataManager.publicTransportManager
        onLoadingChanged: {
            if (query.loading) {
                root.queryRunning = true;
            } else if (root.queryRunning) {
                root.queryRunning = false;
                root.collectResults();
                if (root.category.id !== undefined && (root.category.mostlyUnnamed || root.results.length < 5)) {
                    root.mapDataPending = true;
                    mapData.radius = root.radius > 0 ? Math.min(root.radius, root.mapDataRadius) : root.mapDataRadius;
                    mapData.latitude = root.center.latitude;
                    mapData.longitude = root.center.longitude;
                    mapData.reload();
                } else {
                    root.finished();
                }
            }
        }
    }

    readonly property KOSM.NearbyAmenityModel mapDataModel: KOSM.NearbyAmenityModel {
        id: mapData
        onFinished: {
            if (root.mapDataPending) {
                root.mapDataPending = false;
                root.addMapData();
                root.finished();
            }
        }
    }
}
