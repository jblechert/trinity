// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kpublictransport
import org.kde.kpublictransport.ui as KPublicTransport
import org.kde.itinerary

/** Journey query results on a vertical time axis.
 *  Each journey is a column, its public transport sections are placed at their departure time
 *  and are as long as they take. This makes it easy to see how journeys relate to each other
 *  and to the current time.
 *
 *  Vertical scrolling is left to the containing view, this only scrolls horizontally if needed.
 *
 *  Credit for the idea goes to Andreas Schildbach, whose app Öffi shows connections like this.
 *  Using it made clear how much easier it is to see when and how you can get somewhere this way.
 *  Simple in hindsight, but whether it would have come up without his work is questionable.
 *  Standing on the shoulders of giants.
 */
ColumnLayout {
    id: root

    /** The journeys to show, as a model with a JourneyQueryModel.JourneyRole. */
    required property var journeys
    /** The vertically scrolling view containing this.
     *  Scrolling is coupled: as later journeys are both further down and further right,
     *  scrolling in one direction also scrolls in the other one.
     */
    property Flickable verticalFlickable
    /** Time to initially scroll to, typically the current time. */
    property date focusTime
    /** Time to initially scroll to if focusTime isn't within the shown time range, e.g. the requested time. */
    property date fallbackFocusTime
    property bool initiallyPositioned: false
    /** Whether earlier or later journeys can be loaded. */
    property bool canQueryPrevious: false
    property bool canQueryNext: false

    signal queryPrevious()
    signal queryNext()
    /** Emitted when the user picks a journey. */
    signal journeyClicked(var journey)

    /** Vertical scale of the time axis. */
    readonly property real minuteHeight: Kirigami.Units.gridUnit / 6
    readonly property real columnWidth: Kirigami.Units.gridUnit * 4.5
    readonly property real axisLabelWidth: Kirigami.Units.gridUnit * 3

    /** Shown time range, in milliseconds since the epoch. */
    property double startTime: 0
    property double endTime: 0
    /** The first full hour within the shown time range, and the number of full hours in it. */
    readonly property double firstFullHour: Math.ceil(root.startTime / root.hourMs) * root.hourMs
    readonly property int fullHourCount: root.endTime > root.firstFullHour ? Math.floor((root.endTime - root.firstFullHour) / root.hourMs) + 1 : 0

    /** Current time, updated regularly for the "now" marker. */
    property date now: new Date()

    readonly property double hourMs: 60 * 60 * 1000

    spacing: 0

    function journeyAt(row: int): var {
        return root.journeys.data(root.journeys.index(row, 0), JourneyQueryModel.JourneyRole);
    }

    function departureOf(item: var): date {
        return item.hasExpectedDepartureTime ? item.expectedDepartureTime : item.scheduledDepartureTime;
    }

    function arrivalOf(item: var): date {
        return item.hasExpectedArrivalTime ? item.expectedArrivalTime : item.scheduledArrivalTime;
    }

    /** Whether @p journey is entirely on foot, by bike or by car, without public transport.
     *  For short distances that's all there is, so it's shown like a public transport section.
     */
    function isDirect(journey: var): bool {
        return !journey.sections.some((section) => section.mode === JourneySection.PublicTransport);
    }

    function isRide(section: var): bool {
        return section.mode === JourneySection.PublicTransport || section.mode === JourneySection.RentedVehicle
            || section.mode === JourneySection.IndividualTransport;
    }

    /** Whether @p section of @p journey is shown as a badge: rides on public transport or rented vehicles,
     *  or the walk if that is all there is.
     */
    function isShownSection(section: var, journey: var): bool {
        return root.isRide(section) || !journey.sections.some((s) => root.isRide(s));
    }

    function updateTimeRange(): void {
        let first = Number.MAX_VALUE;
        let last = 0;
        for (let row = 0; row < root.journeys.count; ++row) {
            const journey = root.journeyAt(row);
            for (const section of journey.sections) {
                if (!root.isShownSection(section, journey)) {
                    continue;
                }
                first = Math.min(first, Math.min(section.scheduledDepartureTime.getTime(), root.departureOf(section).getTime()));
                last = Math.max(last, Math.max(section.scheduledArrivalTime.getTime(), root.arrivalOf(section).getTime()));
            }
        }
        if (last === 0) {
            root.startTime = 0;
            root.endTime = 0;
            return;
        }
        // include the current time if that's shortly before the first journey, as a point of reference
        const now = new Date().getTime();
        if (now < first && first - now < 2 * root.hourMs) {
            first = now;
        }
        // with some room for the labels above and below the first and last section
        const margin = 20 * 60 * 1000;
        const previousStartTime = root.startTime;
        root.startTime = first - margin;
        root.endTime = last + margin;

        if (!root.verticalFlickable) {
            return;
        }
        if (!root.initiallyPositioned) {
            root.initiallyPositioned = true;
            Qt.callLater(root.scrollToFocusTime);
        } else if (previousStartTime > 0 && previousStartTime !== root.startTime) {
            // keep showing the same times when earlier journeys got added above
            root.verticalFlickable.contentY += (previousStartTime - root.startTime) / 60000 * root.minuteHeight;
        }
    }

    /** Vertical position on the time axis at which the journey in @p row starts. */
    function journeyY(row: int): real {
        const journey = root.journeyAt(row);
        for (const section of journey.sections) {
            if (section.mode === JourneySection.PublicTransport) {
                return root.yFor(root.departureOf(section));
            }
        }
        return root.yFor(journey.scheduledDepartureTime);
    }

    /** Horizontal scroll position showing the journeys starting around @p y first. */
    function contentXForY(y: real): real {
        const count = root.journeys.count;
        let column = 0;
        for (let row = 0; row < count; ++row) {
            const rowY = root.journeyY(row);
            if (rowY > y) {
                // interpolate between the previous and this journey, for smooth scrolling
                const previousY = row > 0 ? root.journeyY(row - 1) : rowY;
                column = row > 0 && rowY > previousY ? row - 1 + (y - previousY) / (rowY - previousY) : row;
                break;
            }
            column = row;
        }
        return Math.max(0, Math.min(column * root.columnWidth, journeyArea.contentWidth - journeyArea.width));
    }

    /** Inverse of contentXForY(). */
    function yForContentX(x: real): real {
        const count = root.journeys.count;
        if (count === 0) {
            return 0;
        }
        const column = x / root.columnWidth;
        const row = Math.min(Math.floor(column), count - 1);
        const rowY = root.journeyY(row);
        if (row + 1 >= count) {
            return rowY;
        }
        return rowY + (column - row) * (root.journeyY(row + 1) - rowY);
    }

    /** Position on the time axis that is shown at the top of the vertical view. */
    readonly property real referenceOffset: Kirigami.Units.gridUnit * 2
    function visibleTopY(): real {
        return root.verticalFlickable.contentY - timeAxis.mapToItem(root.verticalFlickable.contentItem, 0, 0).y + root.referenceOffset;
    }

    Connections {
        target: root.verticalFlickable
        function onContentYChanged(): void {
            // follow vertical scrolling, unless this is the result of horizontal scrolling
            if (journeyArea.moving || !root.visible) {
                return;
            }
            journeyArea.contentX = root.contentXForY(root.visibleTopY());
            alignTimer.restart();
        }
    }

    // following vertical scrolling smoothly leaves a journey cut off at the left edge, which is fixed once it stops
    Timer {
        id: alignTimer
        interval: 300
        onTriggered: {
            if (root.verticalFlickable?.moving) {
                alignTimer.restart();
            } else {
                root.alignColumns(Math.round);
            }
        }
    }

    /** Scroll horizontally so that no journey is cut off at the left edge, rounding the column with @p round. */
    function alignColumns(round: var): void {
        if (journeyArea.moving || !root.visible || root.columnWidth <= 0) {
            return;
        }
        const maxX = Math.max(0, journeyArea.contentWidth - journeyArea.width);
        journeyArea.contentX = Math.min(round(journeyArea.contentX / root.columnWidth) * root.columnWidth, maxX);
    }

    Connections {
        target: journeyArea
        function onContentXChanged(): void {
            // follow horizontal scrolling by the user
            if (!journeyArea.moving || !root.verticalFlickable) {
                return;
            }
            const flickable = root.verticalFlickable;
            const delta = root.yForContentX(journeyArea.contentX) - root.visibleTopY();
            const maxY = flickable.originY + Math.max(0, flickable.contentHeight - flickable.height);
            flickable.contentY = Math.max(flickable.originY, Math.min(flickable.contentY + delta, maxY));
        }
    }

    function scrollToFocusTime(): void {
        const flickable = root.verticalFlickable;
        const focusInRange = root.focusTime.getTime() >= root.startTime && root.focusTime.getTime() <= root.endTime;
        const focus = focusInRange ? root.focusTime : root.fallbackFocusTime;
        const y = timeAxis.mapToItem(flickable.contentItem, 0, 0).y + root.yFor(focus) - root.referenceOffset;
        const maxY = flickable.originY + Math.max(0, flickable.contentHeight - flickable.height);
        flickable.contentY = Math.max(flickable.originY, Math.min(y, maxY));
        // with the journey departing first fully visible
        root.alignColumns(Math.floor);
    }

    /** Vertical position of @p time on the time axis. */
    function yFor(time: date): real {
        return (time.getTime() - root.startTime) / 60000 * root.minuteHeight;
    }

    Connections {
        target: root.journeys
        function onRowsInserted(): void { Qt.callLater(root.updateTimeRange); }
        function onRowsRemoved(): void { Qt.callLater(root.updateTimeRange); }
        function onModelReset(): void {
            // a new query, scroll to its requested time again once there are results
            root.initiallyPositioned = false;
            Qt.callLater(root.updateTimeRange);
        }
        function onLayoutChanged(): void { Qt.callLater(root.updateTimeRange); }
        function onDataChanged(): void { Qt.callLater(root.updateTimeRange); }
    }
    Component.onCompleted: root.updateTimeRange()

    Timer {
        interval: 30 * 1000
        repeat: true
        running: root.visible
        onTriggered: root.now = new Date()
    }

    VerticalNavigationButton {
        visible: root.canQueryPrevious
        Layout.fillWidth: true
        text: i18nc("@action:button", "Load earlier connections")
        iconName: "go-up-symbolic"
        onClicked: root.queryPrevious()
    }

    Item {
        id: timeAxis

        Layout.fillWidth: true
        // room for the label of the first hour line
        Layout.topMargin: Kirigami.Units.gridUnit * 1.5
        // and below the last one, in case a short ride or walk is shown larger than its duration
        implicitHeight: (root.endTime - root.startTime) / 60000 * root.minuteHeight + Kirigami.Units.gridUnit * 2
        visible: root.endTime > root.startTime

        // hour lines
        Repeater {
            model: root.fullHourCount

            delegate: Item {
                id: hourLine

                required property int index
                readonly property date time: new Date(root.firstFullHour + hourLine.index * root.hourMs)
                // show the date at the start and at day changes
                readonly property bool showDate: hourLine.index === 0 || hourLine.time.getHours() === 0

                y: root.yFor(hourLine.time)
                width: timeAxis.width
                height: 1

                QQC2.Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.bottom: parent.top
                    text: hourLine.showDate
                        ? i18nc("time, date", "%1, %2", hourLine.time.toLocaleTimeString(Qt.locale(), Locale.ShortFormat), hourLine.time.toLocaleDateString(Qt.locale(), Locale.ShortFormat))
                        : hourLine.time.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                }

                Shape {
                    anchors.fill: parent
                    ShapePath {
                        strokeColor: Kirigami.Theme.disabledTextColor
                        strokeWidth: 1
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [2, 4]
                        startX: 0
                        startY: 0
                        PathLine { x: timeAxis.width; y: 0 }
                    }
                }
            }
        }

        // the journeys, scrolling horizontally if they don't fit
        Flickable {
            id: journeyArea

            anchors.fill: parent
            anchors.leftMargin: root.axisLabelWidth
            contentWidth: journeyRepeater.count * root.columnWidth
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Repeater {
                id: journeyRepeater

                model: root.journeys

                delegate: Item {
                    id: journeyColumn

                    required property int index
                    required property var journey

                    readonly property bool isCanceled: journeyColumn.journey.disruptionEffect === Disruption.NoService
                    readonly property bool isDirect: root.isDirect(journeyColumn.journey)
                    // walking or cycling all the way can start any time
                    readonly property bool hasDeparted: !journeyColumn.isDirect && root.journeyY(journeyColumn.index) < root.yFor(root.now)

                    x: journeyColumn.index * root.columnWidth
                    width: root.columnWidth
                    height: timeAxis.height
                    opacity: journeyColumn.isCanceled || journeyColumn.hasDeparted ? 0.5 : 1

                    // the whole journey is clickable, from the first departure to the last arrival
                    MouseArea {
                        readonly property real journeyTop: root.yFor(journeyColumn.journey.scheduledDepartureTime)
                        x: 0
                        y: journeyTop - Kirigami.Units.gridUnit * 2
                        width: parent.width
                        height: root.yFor(journeyColumn.journey.scheduledArrivalTime) - journeyTop + Kirigami.Units.gridUnit * 4
                        onClicked: root.journeyClicked(journeyColumn.journey)
                    }

                    // the public transport sections stacked in time order: each one starts at its
                    // departure time, or right below the previous one if that would overlap
                    Column {
                        x: Kirigami.Units.smallSpacing
                        width: root.columnWidth - 2 * Kirigami.Units.smallSpacing

                        Repeater {
                            model: journeyColumn.journey.sections

                            delegate: ColumnLayout {
                                id: sectionItem

                                required property var modelData
                                readonly property var section: sectionItem.modelData
                                readonly property bool hasDepartureDelay: sectionItem.section.hasExpectedDepartureTime
                                    && sectionItem.section.expectedDepartureTime.getTime() !== sectionItem.section.scheduledDepartureTime.getTime()
                                readonly property real badgeTop: root.yFor(root.departureOf(sectionItem.section))

                                visible: root.isShownSection(sectionItem.section, journeyColumn.journey)
                                width: parent.width
                                spacing: 0

                                Item {
                                    // pushes the departure time label and badge to the departure time
                                    Layout.preferredHeight: Math.max(0, sectionItem.badgeTop - departureLabels.implicitHeight - sectionItem.y)
                                }

                                ColumnLayout {
                                    id: departureLabels

                                    spacing: 0
                                    Layout.alignment: Qt.AlignHCenter

                                    QQC2.Label {
                                        text: Localizer.formatTime(sectionItem.section, "scheduledDepartureTime")
                                        visible: sectionItem.hasDepartureDelay
                                        font: Kirigami.Theme.smallFont
                                        color: Kirigami.Theme.disabledTextColor
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    QQC2.Label {
                                        text: Localizer.formatTime(sectionItem.section, sectionItem.section.hasExpectedDepartureTime ? "expectedDepartureTime" : "scheduledDepartureTime")
                                        color: sectionItem.section.departureDelay > 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                        font.weight: Font.DemiBold
                                        font.strikeout: journeyColumn.isCanceled
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }

                                // line badge, as long as the ride takes but at least big enough to be readable
                                Rectangle {
                                    id: badge

                                    readonly property var line: sectionItem.section.route.line
                                    readonly property bool isRental: sectionItem.section.mode === JourneySection.RentedVehicle
                                    readonly property var rentalNetwork: sectionItem.section.rentalVehicle.network
                                    readonly property bool isDarkTheme: Kirigami.Theme.backgroundColor.hslLightness < 0.4

                                    radius: Kirigami.Units.cornerRadius
                                    color: badge.isRental && badge.rentalNetwork.hasBrandColor ? badge.rentalNetwork.brandColor
                                        : badge.line.hasColor ? badge.line.color : Kirigami.Theme.textColor
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.max(badgeContent.implicitHeight + 2 * Kirigami.Units.smallSpacing,
                                        root.yFor(root.arrivalOf(sectionItem.section)) - sectionItem.badgeTop)

                                    // same logic as KPublicTransport.TransportNameControl
                                    readonly property color foregroundColor: {
                                        const backgroundIsDark = badge.color.hslLightness < 0.4;
                                        if (badge.line.hasTextColor && (badge.line.textColor.hslLightness >= 0.4) === backgroundIsDark) {
                                            return badge.line.textColor;
                                        }
                                        if (backgroundIsDark) {
                                            return badge.isDarkTheme ? Kirigami.Theme.textColor : Kirigami.Theme.backgroundColor;
                                        }
                                        return badge.isDarkTheme ? Kirigami.Theme.backgroundColor : Kirigami.Theme.textColor;
                                    }

                                    ColumnLayout {
                                        id: badgeContent

                                        anchors.centerIn: parent
                                        width: parent.width - 2 * Kirigami.Units.smallSpacing
                                        spacing: 0

                                        KPublicTransport.TransportIcon {
                                            source: sectionItem.section.iconName
                                            isMask: true
                                            color: badge.foregroundColor
                                            iconHeight: Kirigami.Units.iconSizes.smallMedium
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                        }
                                        QQC2.Label {
                                            text: sectionItem.section.mode === JourneySection.PublicTransport ? badge.line.name
                                                : badge.isRental && badge.rentalNetwork.name !== "" ? badge.rentalNetwork.name
                                                : Localizer.formatDuration(sectionItem.section.duration)
                                            visible: text.length > 0 && !badge.line.hasLogo
                                            color: badge.foregroundColor
                                            font.weight: Font.DemiBold
                                            wrapMode: Text.Wrap
                                            horizontalAlignment: Text.AlignHCenter
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                QQC2.Label {
                                    text: Localizer.formatTime(sectionItem.section, sectionItem.section.hasExpectedArrivalTime ? "expectedArrivalTime" : "scheduledArrivalTime")
                                    color: sectionItem.section.arrivalDelay > 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                    font.weight: Font.DemiBold
                                    font.strikeout: journeyColumn.isCanceled
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }
        }

        // current time marker
        Rectangle {
            readonly property bool inRange: root.now.getTime() >= root.startTime && root.now.getTime() <= root.endTime

            visible: inRange
            y: root.yFor(root.now)
            width: timeAxis.width
            height: 2
            color: Kirigami.Theme.neutralTextColor

            QQC2.Label {
                anchors.verticalCenter: parent.verticalCenter
                x: Kirigami.Units.smallSpacing
                leftPadding: Kirigami.Units.smallSpacing
                rightPadding: Kirigami.Units.smallSpacing
                text: root.now.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                font.weight: Font.DemiBold
                color: Kirigami.Theme.backgroundColor
                background: Rectangle {
                    color: Kirigami.Theme.neutralTextColor
                    radius: Kirigami.Units.cornerRadius
                }
            }
        }
    }

    VerticalNavigationButton {
        visible: root.canQueryNext
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.gridUnit
        iconName: "go-down-symbolic"
        text: i18nc("@action:button", "Load later connections")
        onClicked: root.queryNext()
    }
}
