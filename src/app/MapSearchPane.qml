// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.coreaddons as CoreAddons
import org.kde.itinerary

/** Search field for places on the map, by name or category, with the area to search in
 *  and categories to pick from.
 */
QQC2.Pane {
    id: root

    /** The search text. */
    property alias text: searchField.text
    /** Searching around the current location is possible. */
    property bool hasPosition: false
    /** Search around the current location, rather than around the center of the map. */
    readonly property bool aroundMe: root.hasPosition && !root.aroundMapCenter
    /** Search radius in metres, 0 for the nearest places. */
    property int radius: 0

    /** Search for the entered text, or the category @p categoryId if not empty. */
    signal searchRequested(categoryId: string)
    /** The area to search in changed. */
    signal areaEdited()
    signal closeRequested()

    /** Give the search field the keyboard focus. */
    function focusSearchField(): void {
        searchField.forceActiveFocus();
    }

    // internal
    property bool aroundMapCenter: false

    function search(categoryId: string): void {
        if (root.text.trim() === "") {
            return;
        }
        searchField.focus = false;
        Qt.inputMethod.hide();
        root.searchRequested(categoryId);
    }

    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.inherit: false

    component OptionChip: Kirigami.Chip {
        closable: false
        checkable: true
    }

    /** Fades out the end of a horizontally scrolling row, to show there is more in it. */
    component EndFade: Rectangle {
        id: fade
        required property Flickable flickable
        // on top of the flickable, rather than on its content moving with it
        parent: fade.flickable
        z: 1
        anchors {
            top: parent.top
            bottom: parent.bottom
            right: parent.right
        }
        width: Kirigami.Units.gridUnit * 2
        visible: fade.flickable.contentX + fade.flickable.width < fade.flickable.contentWidth - 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Kirigami.Theme.backgroundColor }
        }
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            Kirigami.SearchField {
                id: searchField
                autoAccept: false
                placeholderText: i18nc("@info:placeholder", "Find places, e.g. bakery")
                onAccepted: {
                    // also emitted by the button clearing the field, which takes the focus from it
                    if (searchField.text === "") {
                        searchField.forceActiveFocus();
                        Qt.inputMethod.show();
                        return;
                    }
                    root.search("");
                }
                Layout.fillWidth: true
            }
            QQC2.ToolButton {
                icon.name: "window-close-symbolic"
                text: i18nc("@action:button", "Close")
                display: QQC2.AbstractButton.IconOnly
                onClicked: root.closeRequested()
            }
        }

        // where to search
        Flickable {
            id: areaFlickable
            contentWidth: areaRow.implicitWidth
            implicitHeight: areaRow.implicitHeight
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            Layout.fillWidth: true

            EndFade {
                flickable: areaFlickable
            }

            RowLayout {
                id: areaRow
                spacing: Kirigami.Units.smallSpacing

                QQC2.ButtonGroup { id: areaGroup }
                OptionChip {
                    text: i18nc("@option:radio search places around the current location", "Near Me")
                    icon.name: "mark-location-symbolic"
                    enabled: root.hasPosition
                    checked: root.aroundMe
                    QQC2.ButtonGroup.group: areaGroup
                    onClicked: {
                        root.aroundMapCenter = false;
                        root.areaEdited();
                    }
                }
                OptionChip {
                    text: i18nc("@option:radio search places around the center of the map", "Map Center")
                    icon.name: "crosshairs"
                    checked: !root.aroundMe
                    QQC2.ButtonGroup.group: areaGroup
                    onClicked: {
                        root.aroundMapCenter = true;
                        root.areaEdited();
                    }
                }

                Kirigami.Separator {
                    Layout.fillHeight: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                }

                QQC2.ButtonGroup { id: radiusGroup }
                Repeater {
                    // about 1, 3 and 10 miles with imperial units
                    model: Settings.imperialDistances ? [0, 1609, 4828, 16093] : [0, 1000, 5000, 20000]
                    delegate: OptionChip {
                        id: radiusChip
                        required property int modelData
                        text: radiusChip.modelData === 0 ? i18nc("@option:radio search the nearest places", "Nearby")
                            : CoreAddons.Format.formatDistance(radiusChip.modelData, Settings.distanceFormat)
                        checked: root.radius === radiusChip.modelData
                        QQC2.ButtonGroup.group: radiusGroup
                        onClicked: {
                            root.radius = radiusChip.modelData;
                            root.areaEdited();
                        }
                    }
                }
            }
        }


        // what to search, for quick access
        ListView {
            id: categoryView
            orientation: ListView.Horizontal
            model: PlaceCategories.categories
            spacing: Kirigami.Units.smallSpacing
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            implicitHeight: categoryView.currentItem ? categoryView.currentItem.implicitHeight : Kirigami.Units.gridUnit * 2
            Layout.fillWidth: true
            EndFade {
                flickable: categoryView
            }
            delegate: Kirigami.Chip {
                id: categoryChip
                required property var modelData
                text: categoryChip.modelData.name
                icon.source: categoryChip.modelData.iconSource
                iconMask: true
                closable: false
                checkable: false
                onClicked: {
                    root.text = categoryChip.modelData.name;
                    root.search(categoryChip.modelData.id);
                }
            }
        }

    }
}
