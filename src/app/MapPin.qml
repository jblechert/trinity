/*
    SPDX-FileCopyrightText: 2024 Volker Krause <vkrause@kde.org>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtLocation as QtLocation
import org.kde.kirigami as Kirigami

/** Icon in pin element for the map. */
QtLocation.MapQuickItem {
    id: root

    property alias color: mainIcon.color
    property alias textColor: bgRect.color
    property alias iconName: subIcon.source
    signal clicked()

    anchorPoint.x: sourceItem.width / 2
    // the tip of the pin in the map-symbolic icon, which has some room below it
    anchorPoint.y: sourceItem.height * 7 / 8
    autoFadeIn: false

    sourceItem: Kirigami.Icon {
        id: mainIcon

        height: Kirigami.Units.iconSizes.huge
        width: height
        source: "map-symbolic"
        isMask: true
        color: "#232629"

        Rectangle {
            id: bgRect
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -parent.height / 8
            width: height
            height: parent.height / 3 + 1
            radius: height / 2
        }
        Kirigami.Icon {
            id: subIcon
            anchors.centerIn: mainIcon
            anchors.verticalCenterOffset: -mainIcon.height / 8
            width: height
            height: parent.height / 3 + 1
            isMask: true
            color: root.color
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.clicked()
        }
    }
}
