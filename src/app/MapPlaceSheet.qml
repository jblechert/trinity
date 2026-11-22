// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kosmindoormap as KOSM
import org.kde.kpublictransport as KPublicTransport
import org.kde.itinerary

/** Details of a point of interest picked on the map, such as a shop or a restaurant:
 *  its category, opening hours, address and contact information as far as known in OpenStreetMap,
 *  and actions to go there.
 */
ColumnLayout {
    id: root

    /** The place to show, a candidate as found by MapPlaceLookup. */
    required property var place
    /** Height available for the details list. */
    property real maximumListHeight: Kirigami.Units.gridUnit * 12

    /** Close the details. */
    signal closeRequested()
    /** Navigate to the place, on foot, by bike or by car. */
    signal navigationRequested(mode: int)
    /** Use the place as departure ("from") or arrival ("to") of a journey. */
    signal journeyEndpointRequested(endpoint: string)

    spacing: Kirigami.Units.smallSpacing

    KOSM.OSMElementInformationModel {
        id: infoModel
        element: root.place.amenity.element
        allowOnlineContent: Settings.wikimediaOnlineContentEnabled
        debug: Settings.developmentMode
    }

    RowLayout {
        spacing: Kirigami.Units.largeSpacing
        Layout.fillWidth: true

        Kirigami.Icon {
            source: root.place.iconSource
            isMask: true
            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
        }
        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            Kirigami.Heading {
                level: 3
                text: infoModel.name !== "" ? infoModel.name : root.place.name
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: infoModel.category !== "" ? infoModel.category : root.place.typeName
                visible: text !== "" && text !== root.place.name
                elide: Text.ElideRight
                opacity: 0.7
                Layout.fillWidth: true
            }
        }
        QQC2.ToolButton {
            icon.name: "internet-services"
            text: i18nc("@action:button", "Show on OpenStreetMap")
            display: QQC2.AbstractButton.IconOnly
            visible: !root.place.amenity.element.isNull
            onClicked: Qt.openUrlExternally(root.place.amenity.element.url)
            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.ToolButton {
            icon.name: "window-close-symbolic"
            text: i18nc("@action:button", "Close")
            display: QQC2.AbstractButton.IconOnly
            onClicked: root.closeRequested()
        }
    }

    // how to get there
    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.fillWidth: true

        component ActionButton: QQC2.Button {
            display: QQC2.AbstractButton.TextUnderIcon
            icon.width: Kirigami.Units.iconSizes.smallMedium
            icon.height: Kirigami.Units.iconSizes.smallMedium
            Layout.fillWidth: true
            Layout.preferredWidth: 1 // all equally wide
        }

        ActionButton {
            icon.source: KPublicTransport.IndividualTransportMode.modeIconName(KPublicTransport.IndividualTransport.Walk)
            text: i18nc("@action:button navigate on foot", "Walk")
            onClicked: root.navigationRequested(KPublicTransport.IndividualTransport.Walk)
        }
        ActionButton {
            icon.source: KPublicTransport.IndividualTransportMode.modeIconName(KPublicTransport.IndividualTransport.Bike)
            text: i18nc("@action:button navigate by bike", "Bike")
            onClicked: root.navigationRequested(KPublicTransport.IndividualTransport.Bike)
        }
        ActionButton {
            icon.source: KPublicTransport.IndividualTransportMode.modeIconName(KPublicTransport.IndividualTransport.Car)
            text: i18nc("@action:button navigate by car", "Car")
            onClicked: root.navigationRequested(KPublicTransport.IndividualTransport.Car)
        }
    }
    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.fillWidth: true

        component JourneyButton: QQC2.Button {
            Layout.fillWidth: true
            Layout.preferredWidth: 1 // all equally wide
        }

        JourneyButton {
            icon.name: "go-next-symbolic"
            text: i18nc("@action:button search public transport connections starting here", "From Here")
            onClicked: root.journeyEndpointRequested("from")
        }
        JourneyButton {
            icon.name: "flag"
            text: i18nc("@action:button search public transport connections to here", "To Here")
            onClicked: root.journeyEndpointRequested("to")
        }
    }

    Kirigami.Separator {
        visible: infoView.count > 0
        Layout.fillWidth: true
    }

    // everything known about the place, as in the details dialog of the indoor map
    ListView {
        id: infoView
        model: infoModel
        clip: true
        visible: infoView.count > 0
        boundsBehavior: Flickable.StopAtBounds
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(infoView.contentHeight, root.maximumListHeight)

        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

        Component {
            id: infoStringDelegate
            KOSM.OSMElementInformationDialogStringDelegate {
                property var row
                keyLabel: row?.keyLabel ?? ""
                value: row?.value ?? ""
                category: row?.category ?? -1
            }
        }
        Component {
            id: infoLinkDelegate
            KOSM.OSMElementInformationDialogLinkDelegate {
                property var row
                keyLabel: row?.keyLabel ?? ""
                value: row?.value ?? ""
                category: row?.category ?? -1
                url: row?.url ?? ""
            }
        }
        Component {
            id: infoAddressDelegate
            KOSM.OSMElementInformationDialogAddressDelegate {
                property var row
                address: row?.value ?? ""
            }
        }
        Component {
            id: infoOpeningHoursDelegate
            Item {
                id: openingHoursItem
                property var row
                implicitHeight: openingHoursDelegate.implicitHeight
                KOSM.OSMElementInformationDialogOpeningHoursDelegate {
                    id: openingHoursDelegate
                    width: openingHoursItem.width
                    regionCode: root.place.amenity.regionCode
                    timeZoneId: root.place.amenity.timeZone
                    latitude: root.place.latitude
                    longitude: root.place.longitude
                    openingHours: openingHoursItem.row?.value ?? ""
                }
                // the week overview is a list view of its own, which would keep the details from scrolling
                MouseArea {
                    anchors.fill: parent
                }
            }
        }
        Component {
            id: infoImageDelegate
            KOSM.OSMElementInformationDialogImageDelegate {
                property var row
                source: row?.value ?? ""
                url: row?.url ?? ""
                maximumHeight: Kirigami.Units.gridUnit * 6
            }
        }

        section.property: "categoryLabel"
        section.criteria: ViewSection.FullString
        section.labelPositioning: ViewSection.InlineLabels
        section.delegate: Kirigami.Heading {
            required property string section
            level: 4
            text: section
            height: implicitHeight + Kirigami.Units.largeSpacing
            verticalAlignment: Qt.AlignBottom
        }

        delegate: Loader {
            id: infoDelegate
            required property var model
            width: ListView.view.width
            sourceComponent: {
                switch (infoDelegate.model.type) {
                    case KOSM.OSMElementInformationModel.Link:
                        return infoLinkDelegate;
                    case KOSM.OSMElementInformationModel.PostalAddress:
                        return infoAddressDelegate;
                    case KOSM.OSMElementInformationModel.OpeningHoursType:
                        return infoOpeningHoursDelegate;
                    case KOSM.OSMElementInformationModel.ImageType:
                        return infoImageDelegate;
                    case KOSM.OSMElementInformationModel.String:
                    default:
                        return infoStringDelegate;
                }
            }
            onLoaded: infoDelegate.item.row = infoDelegate.model
        }
    }
}
