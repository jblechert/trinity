// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.coreaddons as CoreAddons
import org.kde.kopeninghours as OH
import org.kde.itinerary

/** List entry for a place or stop found on the map, as found by MapPlaceLookup,
 *  with its category, distance and whether it is open now.
 */
QQC2.ItemDelegate {
    id: root

    /** The place or stop to show. */
    required property var modelData

    width: ListView.view.width

    // internal
    readonly property string openingHours: root.modelData.amenity?.openingHours ?? ""
    readonly property var oh: {
        let v = OH.OpeningHoursParser.parse(root.openingHours);
        v.region = root.modelData.amenity?.regionCode ?? "";
        v.timeZone = root.modelData.amenity?.timeZone ?? "";
        v.setLocation(root.modelData.latitude, root.modelData.longitude);
        return v;
    }
    readonly property bool hasOpeningHours: root.openingHours !== "" && root.oh.error === OH.OpeningHours.NoError

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
                    const distance = CoreAddons.Format.formatDistance(root.modelData.distance, Settings.distanceFormat);
                    if (root.modelData.typeName === "" || root.modelData.typeName === root.modelData.name) {
                        return distance;
                    }
                    return i18nc("@info type of a place and its distance", "%1 · %2", root.modelData.typeName, distance);
                }
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                Layout.fillWidth: true
            }
            QQC2.Label {
                visible: root.hasOpeningHours && text !== ""
                text: root.hasOpeningHours ? OH.Display.currentState(root.oh) : ""
                color: {
                    if (!root.hasOpeningHours) {
                        return Kirigami.Theme.textColor;
                    }
                    switch (root.oh.interval(new Date()).state) {
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
