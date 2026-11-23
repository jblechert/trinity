// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.coreaddons as CoreAddons
import org.kde.kopeninghours as OH
import org.kde.itinerary

/** List entry for a place or stop found on the map, as found by MapPlaceLookup or MapPlaceSearch,
 *  with its category, distance, address and whether it is open now.
 */
QQC2.ItemDelegate {
    id: root

    /** The place or stop to show. */
    required property var modelData
    /** Details of a place, such as its opening hours, as provided by KOSMIndoorMap's NearbyAmenityModel. */
    property var amenity: root.modelData.amenity

    width: ListView.view.width

    // internal
    readonly property string openingHours: root.amenity?.openingHours ?? ""
    readonly property var oh: {
        let v = OH.OpeningHoursParser.parse(root.openingHours);
        v.region = root.amenity?.regionCode ?? "";
        v.timeZone = root.amenity?.timeZone ?? "";
        v.setLocation(root.modelData.latitude, root.modelData.longitude);
        return v;
    }
    readonly property bool hasOpeningHours: root.openingHours !== "" && root.oh.error === OH.OpeningHours.NoError
    /** When the opening state was determined, it is updated regularly while shown, so it matches the details
     *  opened from here, which tell it as of when they are opened.
     */
    property date now: new Date()
    Timer {
        interval: 10000
        repeat: true
        // also when shown again
        triggeredOnStart: true
        running: root.visible && root.hasOpeningHours
        onTriggered: root.now = new Date()
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Icon {
            source: root.modelData.iconSource
            isMask: root.modelData.type === "place"
            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
        }

        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true

            QQC2.Label {
                text: root.modelData.name
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: {
                    let parts = [];
                    const typeName = root.modelData.typeName !== "" ? root.modelData.typeName : (root.amenity?.typeName ?? "");
                    if (typeName !== "" && typeName !== root.modelData.name) {
                        parts.push(typeName);
                    }
                    parts.push(CoreAddons.Format.formatDistance(root.modelData.distance, Settings.distanceFormat));
                    if (root.modelData.address) {
                        parts.push(root.modelData.address);
                    }
                    return parts.join(i18nc("@info separator between type, distance and address of a place", " · "));
                }
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                Layout.fillWidth: true
            }
            QQC2.Label {
                visible: root.hasOpeningHours && text !== ""
                // depends on now, which Display.currentState() uses as well
                text: root.hasOpeningHours && root.now ? OH.Display.currentState(root.oh) : ""
                color: {
                    if (!root.hasOpeningHours) {
                        return Kirigami.Theme.textColor;
                    }
                    switch (root.oh.interval(root.now).state) {
                        case OH.Interval.Open: return Kirigami.Theme.positiveTextColor;
                        case OH.Interval.Closed: return Kirigami.Theme.negativeTextColor;
                        default: return Kirigami.Theme.textColor;
                    }
                }
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                Layout.fillWidth: true
            }
        }
    }
}
