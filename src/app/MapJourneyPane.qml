// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtPositioning
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.coreaddons as CoreAddons
import org.kde.kpublictransport as KPublicTransport
import org.kde.kpublictransport.ui as KPublicTransportUi
import org.kde.itinerary

/** A journey shown on the map: a public transport connection with the list of its sections,
 *  or the preview of a route on foot, by bike or by car before starting navigation.
 */
QQC2.Pane {
    id: root

    /** The journey to show. */
    property var journey
    /** The journey is a route preview with this KPublicTransport.IndividualTransport mode,
     *  or -1 for a public transport connection.
     */
    property int travelMode: -1
    readonly property bool isPreview: root.travelMode >= 0
    /** The route of a preview is being searched. */
    property bool loading: false
    /** Why no route of a preview could be found, if none was. */
    property string errorMessage
    /** Name of the destination of a preview. */
    property string destinationName
    /** Navigation along the previewed route can start, as it starts at the current location. */
    property bool canStart: false
    /** The search results the shown connection was picked from can be shown again. */
    property bool canShowResults: false
    /** The current location, if known, for offering walking directions to the first stop when it is close. */
    property var currentPosition: QtPositioning.coordinate()
    /** Index of the journey section brought into view on the map, -1 for the whole journey. */
    property int currentSection: -1
    /** Height available for the list of sections. */
    property real maximumListHeight: Kirigami.Units.gridUnit * 10

    signal closeRequested()
    /** Show the search results the connection was picked from. */
    signal resultsRequested()
    /** Bring the journey section with index @p index into view, or the whole journey for -1. */
    signal sectionRequested(index: int)
    /** Preview the route with another KPublicTransport.IndividualTransport mode, or search public transport connections for -1. */
    signal travelModeRequested(mode: int)
    /** Start navigation along the previewed route. */
    signal startRequested()
    /** Start navigation to @p stop, the departure stop of the first public transport section of the connection. */
    signal walkToStopRequested(stop: var)

    readonly property bool hasJourney: root.journey !== undefined && root.journey !== null && root.journey.sections.length > 0

    // internal
    /** The sections listed, waiting needs no line of its own. */
    readonly property var sections: {
        if (!root.hasJourney) {
            return [];
        }
        let sections = [];
        const all = root.journey.sections;
        for (let i = 0; i < all.length; ++i) {
            if (all[i].mode !== KPublicTransport.JourneySection.Waiting) {
                sections.push({ section: all[i], index: i });
            }
        }
        return sections;
    }
    /** The first section using public transport, e.g. to walk to its departure stop. */
    readonly property var firstTransportSection: {
        if (!root.hasJourney) {
            return null;
        }
        for (const section of root.journey.sections) {
            if (section.mode === KPublicTransport.JourneySection.PublicTransport) {
                return section;
            }
        }
        return null;
    }
    /** Elevation along the previewed route, points of distance from its start and elevation, in meters. */
    readonly property var elevationProfile: {
        if (!root.isPreview || !root.hasJourney || root.journey.sections.length !== 1) {
            return [];
        }
        return root.journey.sections[0].path.elevationProfile ?? [];
    }

    function departureTime(object: var): string {
        return Localizer.formatTime(object, object.hasExpectedDepartureTime ? "expectedDepartureTime" : "scheduledDepartureTime");
    }
    function arrivalTime(object: var): string {
        return Localizer.formatTime(object, object.hasExpectedArrivalTime ? "expectedArrivalTime" : "scheduledArrivalTime");
    }
    function joinDetails(parts: var): string {
        return parts.filter((p) => p !== "").join(i18nc("@info separator between details of a journey", " · "));
    }
    function distanceText(distance: int, ascent: int, descent: int): string {
        const length = distance > 0 ? CoreAddons.Format.formatDistance(distance, Settings.distanceFormat) : "";
        if (length !== "" && (ascent > 0 || descent > 0)) {
            return i18nc("@info route length, total ascent and descent", "%1 · ↑ %2 m · ↓ %3 m", length, Math.max(ascent, 0), Math.max(descent, 0));
        }
        return length;
    }

    /** What a section not using public transport is, with its length and duration. */
    function sectionText(section: var): string {
        const distance = CoreAddons.Format.formatDistance(section.distance, Settings.distanceFormat);
        const duration = Localizer.formatDuration(section.duration);
        switch (section.mode) {
        case KPublicTransport.JourneySection.Walking:
            return section.distance === 0 ? i18n("Walk (%1)", duration) : i18n("Walk %1 (%2)", distance, duration);
        case KPublicTransport.JourneySection.Transfer:
            return i18n("Transfer (%1)", duration);
        case KPublicTransport.JourneySection.RentedVehicle:
            return i18n("%1 %2 (%3)", section.rentalVehicle.network.name, distance, duration);
        case KPublicTransport.JourneySection.IndividualTransport:
            if (section.individualTransport.mode === KPublicTransport.IndividualTransport.Bike) {
                return i18n("Cycle %1 (%2)", distance, duration);
            }
            return i18n("Drive %1 (%2)", distance, duration);
        }
        return "";
    }

    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.inherit: false

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            spacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true

            QQC2.ToolButton {
                icon.name: "go-previous-symbolic"
                text: i18nc("@action:button show the list of found connections again", "Back to the connections")
                display: QQC2.AbstractButton.IconOnly
                visible: !root.isPreview && root.canShowResults
                onClicked: root.resultsRequested()
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            Kirigami.Icon {
                source: root.isPreview ? KPublicTransport.IndividualTransportMode.modeIconName(root.travelMode) : ""
                visible: root.isPreview
                isMask: true
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Kirigami.Heading {
                    level: 3
                    text: {
                        if (root.isPreview) {
                            return i18n("To %1", root.destinationName);
                        }
                        if (!root.hasJourney) {
                            return "";
                        }
                        return i18nc("@title departure and arrival time of a journey", "%1 – %2", root.departureTime(root.journey), root.arrivalTime(root.journey));
                    }
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: {
                        if (root.loading) {
                            return i18nc("@info", "Searching for a route…");
                        }
                        if (!root.hasJourney) {
                            return "";
                        }
                        if (root.isPreview) {
                            return root.joinDetails([Localizer.formatDuration(root.journey.duration),
                                root.distanceText(root.journey.distance, root.journey.ascent, root.journey.descent)]);
                        }
                        return root.joinDetails([Localizer.formatDuration(root.journey.duration),
                            i18ncp("number of switches to another transport", "One change", "%1 changes", root.journey.numberOfChanges)]);
                    }
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    opacity: 0.7
                    Layout.fillWidth: true
                }
            }
            QQC2.BusyIndicator {
                running: root.loading
                visible: running
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
            }
            QQC2.ToolButton {
                icon.name: "zoom-fit-best"
                text: i18nc("@action:button show the entire journey on the map", "Show All")
                display: QQC2.AbstractButton.IconOnly
                visible: root.hasJourney && !root.loading
                onClicked: root.sectionRequested(-1)
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

        // route preview: switching the mode, and starting navigation
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            visible: root.isPreview
            Layout.fillWidth: true

            component ModeButton: QQC2.Button {
                id: modeButton
                required property int mode
                display: QQC2.AbstractButton.TextUnderIcon
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                checkable: true
                checked: root.travelMode === modeButton.mode
                onClicked: {
                    // checked follows the mode shown, not the click
                    modeButton.checked = Qt.binding(() => root.travelMode === modeButton.mode);
                    if (root.travelMode !== modeButton.mode) {
                        root.travelModeRequested(modeButton.mode);
                    }
                }
                Layout.fillWidth: true
                Layout.preferredWidth: 1 // all equally wide
            }

            ModeButton {
                mode: KPublicTransport.IndividualTransport.Walk
                icon.source: KPublicTransport.IndividualTransportMode.modeIconName(KPublicTransport.IndividualTransport.Walk)
                text: i18nc("@action:button navigate on foot", "Walk")
            }
            ModeButton {
                mode: KPublicTransport.IndividualTransport.Bike
                icon.source: KPublicTransport.IndividualTransportMode.modeIconName(KPublicTransport.IndividualTransport.Bike)
                text: i18nc("@action:button navigate by bike", "Bike")
            }
            ModeButton {
                mode: KPublicTransport.IndividualTransport.Car
                icon.source: KPublicTransport.IndividualTransportMode.modeIconName(KPublicTransport.IndividualTransport.Car)
                text: i18nc("@action:button navigate by car", "Car")
            }
            ModeButton {
                mode: -1
                icon.source: KPublicTransport.LineMode.iconName(KPublicTransport.Line.LocalTrain)
                text: i18nc("@action:button search public transport connections, short", "Transit")
            }
        }

        QQC2.Label {
            text: root.errorMessage !== "" ? root.errorMessage : i18nc("@info navigation", "No route found")
            visible: root.isPreview && !root.loading && !root.hasJourney
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.negativeTextColor
            Layout.fillWidth: true
        }
        QQC2.Label {
            // TODO remove once KPublicTransport asks Transitous for longer direct routes, and asks it for routes
            // around Frankfurt as well, see the README
            text: i18nc("@info why no route on foot, by bike or by car was found", "Some routes can't be found yet, mostly those taking longer than about half an hour. Public transport connections can be searched with Transit.")
            visible: root.isPreview && !root.loading && !root.hasJourney && root.errorMessage === ""
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.fillWidth: true
        }

        ElevationProfile {
            visible: root.isPreview && !root.loading && root.elevationProfile.length >= 2
            profile: root.elevationProfile
            implicitHeight: Kirigami.Units.gridUnit * 3
            Layout.fillWidth: true
        }

        RowLayout {
            visible: root.isPreview
            spacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true
            QQC2.Button {
                icon.name: "media-playback-start"
                text: i18nc("@action:button start navigation", "Start")
                enabled: root.canStart && root.hasJourney && !root.loading
                onClicked: root.startRequested()
            }
            QQC2.Label {
                text: i18nc("@info", "Navigation starts at your location.")
                visible: !root.canStart
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                Layout.fillWidth: true
            }
        }

        // the sections of a public transport connection
        ListView {
            id: sectionView
            visible: !root.isPreview && root.hasJourney
            model: root.sections
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(sectionView.contentHeight, root.maximumListHeight)
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

            delegate: QQC2.ItemDelegate {
                id: sectionDelegate
                required property var modelData
                readonly property var section: sectionDelegate.modelData.section
                readonly property bool isTransport: sectionDelegate.section.mode === KPublicTransport.JourneySection.PublicTransport
                width: ListView.view.width
                highlighted: root.currentSection === sectionDelegate.modelData.index
                onClicked: root.sectionRequested(sectionDelegate.modelData.index)

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    QQC2.Label {
                        text: root.departureTime(sectionDelegate.section)
                        font.features: { "tnum": 1 }
                        Layout.alignment: Qt.AlignTop
                    }
                    Item {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                        Layout.preferredHeight: transportName.implicitHeight
                        Layout.alignment: Qt.AlignTop
                        KPublicTransportUi.TransportNameControl {
                            id: transportName
                            journeySection: sectionDelegate.section
                            visible: sectionDelegate.isTransport
                            width: Math.min(implicitWidth, parent.width)
                            squashToFit: true
                        }
                        Kirigami.Icon {
                            source: sectionDelegate.section.iconName
                            visible: !sectionDelegate.isTransport
                            isMask: true
                            width: Kirigami.Units.iconSizes.smallMedium
                            height: Kirigami.Units.iconSizes.smallMedium
                            x: Kirigami.Units.smallSpacing
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        QQC2.Label {
                            text: sectionDelegate.isTransport
                                ? i18nc("journey from departure to arrival stop", "%1 → %2", sectionDelegate.section.from.name, sectionDelegate.section.to.name)
                                : root.sectionText(sectionDelegate.section)
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        QQC2.Label {
                            text: sectionDelegate.isTransport
                                ? root.joinDetails([i18nc("@info arrival time of a journey section", "Arrival %1", root.arrivalTime(sectionDelegate.section)),
                                    Localizer.formatDuration(sectionDelegate.section.duration)])
                                : i18n("To %1", sectionDelegate.section.to.name)
                            visible: text !== ""
                            elide: Text.ElideRight
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        QQC2.Button {
            id: walkButton
            readonly property var stop: root.firstTransportSection ? root.firstTransportSection.from : null
            visible: !root.isPreview && walkButton.stop !== null && walkButton.stop.hasCoordinate
                // e.g. not when planning a journey somewhere else
                && root.currentPosition.isValid && root.currentPosition.distanceTo(QtPositioning.coordinate(walkButton.stop.latitude, walkButton.stop.longitude)) < 5000
            icon.source: KPublicTransport.IndividualTransportMode.modeIconName(KPublicTransport.IndividualTransport.Walk)
            text: walkButton.stop ? i18nc("@action:button walking directions to a departure stop", "Walk to %1", walkButton.stop.name) : ""
            onClicked: root.walkToStopRequested(walkButton.stop)
            Layout.fillWidth: true
        }
    }
}
