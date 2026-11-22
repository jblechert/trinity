// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.coreaddons as CoreAddons
import org.kde.kpublictransport as KPublicTransport
import org.kde.kpublictransport.ui as KPublicTransportUi
import org.kde.itinerary

/** A public transport stop picked on the map: the lines departing there with their next departures.
 *  Selecting a line or departure shows the route of that trip, which the map then shows as well.
 */
ColumnLayout {
    id: root

    /** The stop to show, a candidate as found by MapPlaceLookup. */
    required property var place
    /** Height available for the lists of lines and stops. */
    property real maximumListHeight: Kirigami.Units.gridUnit * 12

    /** The trip selected to show its route, if hasTrip is set. */
    property KPublicTransport.journeySection trip
    /** A trip has been selected and loaded. */
    readonly property bool hasTrip: root.tripLoaded
    /** Line color of the shown trip. */
    readonly property color tripColor: root.trip.route.line.hasColor ? root.trip.route.line.color : "#232629"

    /** Close the details. */
    signal closeRequested()
    /** Navigate to the stop, on foot, by bike or by car. */
    signal navigationRequested(mode: int)
    /** Use the stop as departure ("from") or arrival ("to") of a journey. */
    signal journeyEndpointRequested(endpoint: string)
    /** The route of the selected trip has been loaded and should be brought into view. */
    signal tripReady()
    /** A stop of the shown trip has been selected. */
    signal tripStopSelected(stopover: KPublicTransport.stopover)

    spacing: Kirigami.Units.smallSpacing

    // internal
    property bool tripLoaded: false
    property bool tripLoading: false
    property int tripStopIndex: -1
    property var tripStops: []
    /** Departures grouped by line and direction, in the order of their next departure. */
    property var lines: []

    /** Show the route of the trip departing at @p stopover. */
    function showTrip(stopover: KPublicTransport.stopover): void {
        root.tripLoading = true;
        let reply = LiveDataManager.publicTransportManager.queryTrip({
            stopover: stopover,
            downloadAssets: Settings.wikimediaOnlineContentEnabled
        });
        reply.finished.connect(() => {
            root.tripLoading = false;
            if (reply.error === KPublicTransport.Reply.NoError) {
                root.trip = reply.trip;
                let stops = [reply.trip.departure];
                for (const s of reply.trip.intermediateStops) {
                    stops.push(s);
                }
                stops.push(reply.trip.arrival);
                root.tripStops = stops;
                root.tripStopIndex = reply.stopoverIndex;
                root.tripLoaded = true;
                root.tripReady();
            } else {
                applicationWindow().showPassiveNotification(reply.errorString);
            }
            reply.destroy();
        });
    }

    function hideTrip(): void {
        root.tripLoaded = false;
        root.tripStops = [];
        root.tripStopIndex = -1;
    }

    /** Departure or arrival time of @p stopover, with the day of the week if it is not on @p day. */
    function formatTime(stopover: KPublicTransport.stopover, arrival: bool, day: date): string {
        const property = arrival ? (stopover.hasExpectedArrivalTime ? "expectedArrivalTime" : "scheduledArrivalTime")
                                 : (stopover.hasExpectedDepartureTime ? "expectedDepartureTime" : "scheduledDepartureTime");
        const time = CoreAddons.Format.formatTime(stopover, property, Locale.ShortFormat);
        const dt = stopover[property];
        if (isNaN(dt.getTime()) || dt.toDateString() === day.toDateString()) {
            return time;
        }
        return i18nc("@info day of the week and time of a departure", "%1 %2", dt.toLocaleDateString(Qt.locale(), "ddd"), time);
    }

    function updateLines(): void {
        let lines = [];
        for (let i = 0; i < departureModel.rowCount(); ++i) {
            const stopover = departureModel.data(departureModel.index(i, 0), KPublicTransport.StopoverQueryModel.StopoverRole);
            const key = stopover.route.line.name + "\n" + stopover.route.direction;
            let line = lines.find((l) => l.key === key);
            if (!line) {
                line = { key: key, stopover: stopover, times: [], day: new Date() };
                lines.push(line);
            }
            if (line.times.length < 3) {
                // the day only once, for the first departure on it
                line.times.push(root.formatTime(stopover, false, line.day));
                line.day = stopover.hasExpectedDepartureTime ? stopover.expectedDepartureTime : stopover.scheduledDepartureTime;
            }
        }
        root.lines = lines;
    }

    KPublicTransport.StopoverQueryModel {
        id: departureModel
        manager: LiveDataManager.publicTransportManager
        request: ({
            stop: root.place.location,
            downloadAssets: Settings.wikimediaOnlineContentEnabled,
        })
        onRowsInserted: Qt.callLater(root.updateLines)
        onRowsRemoved: Qt.callLater(root.updateLines)
        onModelReset: Qt.callLater(root.updateLines)
        onDataChanged: Qt.callLater(root.updateLines)
    }

    RowLayout {
        spacing: Kirigami.Units.largeSpacing
        Layout.fillWidth: true

        QQC2.ToolButton {
            icon.name: "go-previous-symbolic"
            text: i18nc("@action:button", "Back to the lines")
            display: QQC2.AbstractButton.IconOnly
            visible: root.hasTrip
            onClicked: root.hideTrip()
        }
        Kirigami.Icon {
            source: root.place.iconSource
            visible: !root.hasTrip
            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
        }
        KPublicTransportUi.TransportNameControl {
            visible: root.hasTrip
            line: root.trip.route.line
        }
        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            Kirigami.Heading {
                level: 3
                text: root.hasTrip ? i18nc("@title direction of a public transport line", "To %1", root.trip.route.direction !== "" ? root.trip.route.direction : root.trip.arrival.stopPoint.name)
                                   : root.place.name
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: root.hasTrip ? i18nc("@info", "From %1", root.place.name) : root.place.typeName
                elide: Text.ElideRight
                opacity: 0.7
                Layout.fillWidth: true
            }
        }
        QQC2.BusyIndicator {
            running: departureModel.loading || root.tripLoading
            visible: running
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
        }
        QQC2.ToolButton {
            icon.name: "window-close-symbolic"
            text: i18nc("@action:button", "Close")
            display: QQC2.AbstractButton.IconOnly
            onClicked: root.closeRequested()
        }
    }

    // how to get there, and all departures
    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        visible: !root.hasTrip
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
            icon.name: "view-calendar-day"
            text: i18nc("@action:button show all departures at a stop", "Departures")
            onClicked: applicationWindow().pageStack.push(Qt.createComponent("org.kde.itinerary", "DepartureQueryPage"), {
                stop: root.place.location,
                dateTime: new Date(),
            })
        }
    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        visible: !root.hasTrip
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
        Layout.fillWidth: true
    }

    QQC2.Label {
        text: departureModel.errorMessage !== "" ? departureModel.errorMessage : i18nc("@info", "No departures found.")
        visible: !root.hasTrip && !departureModel.loading && root.lines.length === 0
        wrapMode: Text.WordWrap
        opacity: 0.7
        Layout.fillWidth: true
    }

    // the lines departing here, with their next departures
    ListView {
        id: lineView
        visible: !root.hasTrip && root.lines.length > 0
        model: root.lines
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(lineView.contentHeight, root.maximumListHeight)

        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

        delegate: QQC2.ItemDelegate {
            id: lineDelegate
            required property var modelData
            width: ListView.view.width
            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing
                KPublicTransportUi.TransportNameControl {
                    line: lineDelegate.modelData.stopover.route.line
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    QQC2.Label {
                        text: lineDelegate.modelData.stopover.route.direction
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        text: lineDelegate.modelData.times.join(", ")
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        Layout.fillWidth: true
                    }
                }
            }
            onClicked: root.showTrip(lineDelegate.modelData.stopover)
        }
    }

    // the stops of the selected trip
    ListView {
        id: tripView
        visible: root.hasTrip
        model: root.tripStops
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(tripView.contentHeight, root.maximumListHeight)

        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

        onCountChanged: {
            if (root.tripStopIndex > 0) {
                tripView.positionViewAtIndex(root.tripStopIndex, ListView.Beginning);
            }
        }

        delegate: QQC2.ItemDelegate {
            id: stopDelegate
            required property var modelData
            required property int index
            readonly property bool isCurrent: stopDelegate.index === root.tripStopIndex
            readonly property bool isLast: stopDelegate.index === root.tripStops.length - 1
            width: ListView.view.width
            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Rectangle {
                    color: stopDelegate.isCurrent ? root.tripColor : "#eff0f1"
                    border.color: root.tripColor
                    border.width: 2
                    radius: height / 2
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                QQC2.Label {
                    text: stopDelegate.modelData.stopPoint.name
                    font.bold: stopDelegate.isCurrent
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: root.formatTime(stopDelegate.modelData, stopDelegate.isLast || isNaN(stopDelegate.modelData.scheduledDepartureTime.getTime()), new Date())
                    opacity: 0.7
                }
            }
            onClicked: root.tripStopSelected(stopDelegate.modelData)
        }
    }

    QQC2.Button {
        visible: root.hasTrip
        icon.name: "documentinfo"
        text: i18nc("@action:button", "Trip Details")
        onClicked: applicationWindow().pageStack.push(Qt.createComponent("org.kde.itinerary", "StopoverDetailsPage"), {
            stopover: root.tripStops[Math.max(0, root.tripStopIndex)],
            ptMgr: LiveDataManager.publicTransportManager,
        })
    }
}
