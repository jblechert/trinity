/*
    SPDX-FileCopyrightText: 2019-2021 Volker Krause <vkrause@kde.org>
    SPDX-FileCopyrightText: 2023 Carl Schwan <carl@carlschwan.eu>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels
import org.kde.kpublictransport
import org.kde.itinerary
import org.kde.kirigamiaddons.formcard as FormCard

Kirigami.ScrollablePage {
    id: root

    /** The journey selected by the user on this page. */
    property var journey
    /** The journey to query for. */
    property alias journeyRequest: journeyModel.request
    property alias publicTransportManager: journeyModel.manager
    /** Label of the button for selecting a journey, describing what selecting it does. */
    property string selectText: i18n("Select")

    /** Showing results for an arrival query. */
    readonly property bool isArrival: root.journeyRequest.dateTimeMode == JourneyRequest.Arrival

    /** Also show journeys departing before the requested time.
     *  Backends tend to include a few of those, which aren't useful unless explicitly asked for.
     */
    property bool showEarlierJourneys: false
    onShowEarlierJourneysChanged: sortedJourneyModel.invalidateFilter()

    /** Show the results on a time axis rather than as a list.
     *  The timeline also shows journeys that already departed.
     */
    readonly property bool showTimeline: Settings.journeyResultsAsTimeline
    onShowTimelineChanged: {
        root.applyViewMode();
        sortedJourneyModel.invalidateFilter();
    }
    Component.onCompleted: root.applyViewMode()

    /** Switch the view between list and timeline.
     *  Done imperatively and in this order, as changing model and delegate of a view
     *  that is reusing items at the same time crashes.
     */
    function applyViewMode(): void {
        journeyView.model = null;
        journeyView.reuseItems = !root.showTimeline;
        journeyView.header = root.showTimeline ? null : earlierButtonComponent;
        journeyView.delegate = root.showTimeline ? timelineComponent : listDelegate;
        // the timeline is a single item showing all journeys
        journeyView.model = root.showTimeline ? 1 : sortedJourneyModel;
    }

    /** All line modes to search for, and those usable with local transport tickets.
     *  If set, the results can be switched between both.
     */
    property var allLineModes: []
    property var localLineModes: []

    /** Repeat the query with the line modes for the currently selected ticket type. */
    function requery(): void {
        const req = root.journeyRequest;
        req.lineModes = Settings.localTransportOnly ? root.localLineModes : root.allLineModes;
        root.showEarlierJourneys = false;
        root.journeyRequest = req;
    }

    /** Show @p journey on the map, with a way back to these results. */
    function showOnMap(journey: var): void {
        const pageStack = root.QQC2.ApplicationWindow.window.pageStack;
        const map = pagepool.loadPage(Qt.resolvedUrl("MapPage.qml"));
        map.showJourney(journey, root);
        pageStack.layers.clear();
        // the map goes on top of these results, so going back returns to them, also when it was open before
        // (going back to it would close the pages after it); if the search was started on the map, going back
        // from the first page returns to it then, see JourneyRequestPage.returnsToMap
        if (pageStack.columnView.containsItem(map)) {
            pageStack.removePage(map);
        }
        pageStack.currentIndex = pageStack.depth - 1;
        pageStack.push(map);
    }

    /** Show the best journey found on the map once the search is done, see bestJourney(). */
    property bool showBestOnMap: false

    /** When the first train, bus, etc. of @p journey leaves, or when it starts if it has none. */
    function departureOf(journey: var): var {
        // what matters is when the first train, bus, etc. leaves, not when walking to it would have to start
        let departing = journey;
        for (const section of journey.sections) {
            if (section.mode === JourneySection.PublicTransport) {
                departing = section;
                break;
            }
        }
        return departing.hasExpectedDepartureTime ? departing.expectedDepartureTime : departing.scheduledDepartureTime;
    }

    /** Whether @p journey departs at or after the requested time. */
    function departsInTime(journey: var): bool {
        // the requested time is picked with minute precision, so compare with that
        const requested = new Date(root.journeyRequest.dateTime);
        requested.setSeconds(0, 0);
        return root.departureOf(journey).getTime() >= requested.getTime();
    }

    /** The journey found that gets there first, of those departing at or after the requested time,
     *  the one departing last if several arrive at the same time.
     *  For an arrival query, the one departing last of those arriving in time. Undefined if there is none.
     */
    function bestJourney(): var {
        const requested = new Date(root.journeyRequest.dateTime);
        let best = undefined;
        for (let i = 0; i < journeyModel.rowCount(); ++i) {
            const journey = journeyModel.data(journeyModel.index(i, 0), JourneyQueryModel.JourneyRole);
            if (journey.disruptionEffect === Disruption.NoService) {
                continue;
            }
            const departure = root.departureOf(journey).getTime();
            const arrival = (journey.hasExpectedArrivalTime ? journey.expectedArrivalTime : journey.scheduledArrivalTime).getTime();
            if (root.isArrival ? arrival > requested.getTime() : !root.departsInTime(journey)) {
                continue;
            }
            if (!best) {
                best = { journey: journey, departure: departure, arrival: arrival };
                continue;
            }
            const better = root.isArrival
                ? departure > best.departure || (departure === best.departure && arrival < best.arrival)
                : arrival < best.arrival || (arrival === best.arrival && departure > best.departure);
            if (better) {
                best = { journey: journey, departure: departure, arrival: arrival };
            }
        }
        return best?.journey;
    }

    /** Where searches are logged, see searchFinished(). */
    readonly property LoggingCategory searchLog: LoggingCategory {
        name: "org.kde.itinerary.journeysearch"
        defaultLogLevel: LoggingCategory.Info
    }

    /** Log the outcome of a search, e.g. for automated tests, and show the best journey on the map if requested. */
    function searchFinished(): void {
        const best = root.bestJourney();
        let summary = "none";
        if (best) {
            const lines = best.sections.map((section) => {
                switch (section.mode) {
                case JourneySection.PublicTransport:
                    return section.route.line.name !== "" ? section.route.line.name : "?";
                case JourneySection.Walking:
                    return "walk";
                case JourneySection.Transfer:
                    return "transfer";
                case JourneySection.Waiting:
                    return "wait";
                case JourneySection.RentedVehicle:
                    return "rental";
                case JourneySection.IndividualTransport:
                    return "individual";
                default:
                    return "other";
                }
            });
            const arrival = best.hasExpectedArrivalTime ? best.expectedArrivalTime : best.scheduledArrivalTime;
            summary = "departure=" + Qt.formatDateTime(root.departureOf(best), "yyyy-MM-ddTHH:mm")
                + " arrival=" + Qt.formatDateTime(arrival, "yyyy-MM-ddTHH:mm")
                + " duration=" + best.duration + " changes=" + best.numberOfChanges
                + " sections=" + JSON.stringify(lines.join(","));
        }
        console.info(root.searchLog, "journey search finished: results=" + journeyModel.rowCount()
            + " shown=" + sortedJourneyModel.count
            + " error=" + JSON.stringify(journeyModel.errorMessage)
            + " best: " + summary);
        if (root.showBestOnMap && best) {
            root.showBestOnMap = false;
            // not while the model is still emitting its signals
            Qt.callLater(root.showOnMap, best);
        }
    }

    Connections {
        target: journeyModel
        function onLoadingChanged(): void {
            if (!journeyModel.loading) {
                root.searchFinished();
            }
        }
    }

    /** Load one more batch of earlier or later journeys, unless a query is still running. */
    function loadMore(earlier: bool): void {
        if (journeyModel.loading) {
            return;
        }
        if (earlier && journeyModel.canQueryPrevious) {
            root.showEarlierJourneys = true;
            journeyModel.queryPrevious();
        } else if (!earlier && journeyModel.canQueryNext) {
            journeyModel.queryNext();
        }
    }

    // load more when scrolling to the end of the timeline, one query each time the edge is reached
    Connections {
        target: journeyView
        enabled: root.showTimeline
        function onAtYEndChanged(): void {
            if (journeyView.atYEnd && journeyView.moving) {
                root.loadMore(false);
            }
        }
        function onAtYBeginningChanged(): void {
            if (journeyView.atYBeginning && journeyView.moving) {
                root.loadMore(true);
            }
        }
    }

    actions: [
        Kirigami.Action {
            text: i18nc("@option:check only show journeys usable with local transport tickets", "Local Transport Only")
            icon.name: "filter-symbolic"
            checkable: true
            checked: Settings.localTransportOnly
            visible: root.allLineModes.length > 0
            onTriggered: {
                Settings.localTransportOnly = checked;
                root.requery();
            }
        },
        Kirigami.Action {
            icon.name: root.showTimeline ? "view-list-details" : "view-calendar-day"
            text: root.showTimeline ? i18nc("@action:button", "Show as List") : i18nc("@action:button", "Show as Timeline")
            onTriggered: Settings.journeyResultsAsTimeline = !Settings.journeyResultsAsTimeline
        }
    ]

    /** Details of a single journey, with the actions for it. */
    component JourneyDetailsLayout: ColumnLayout {
        id: detailsLayout

        required property var journey
        required property string selectText

        signal selected()

        spacing: 0

        Repeater {
            id: sectionRepeater
            delegate: JourneySectionDelegate {
                Layout.fillWidth: true
                modelLength: sectionRepeater.count - 1
            }
            model: detailsLayout.journey.sections
        }

        FormCard.FormDelegateSeparator {}
        FormCard.FormButtonDelegate {
            text: i18nc("@action:button show a journey on the map", "Show on Map")
            description: i18nc("@info", "All sections of the connection, with walks and stops")
            icon.name: "map-symbolic"
            onClicked: root.showOnMap(detailsLayout.journey)
            Layout.fillWidth: true
        }

        /** The first section using public transport, e.g. to walk to its departure stop. */
        readonly property var firstTransportSection: {
            for (const section of detailsLayout.journey.sections) {
                if (section.mode === JourneySection.PublicTransport) {
                    return section;
                }
            }
            return null;
        }

        FormCard.FormDelegateSeparator {
            visible: walkButton.visible
        }
        FormCard.FormButtonDelegate {
            id: walkButton

            readonly property var stop: detailsLayout.firstTransportSection ? detailsLayout.firstTransportSection.from : null

            text: walkButton.stop ? i18nc("@action:button walking directions to a departure stop", "Walk to %1", walkButton.stop.name) : ""
            description: i18nc("@info", "Directions from your current location, with voice guidance")
            icon.name: "map-symbolic"
            visible: walkButton.stop !== null && walkButton.stop.hasCoordinate
            onClicked: detailsLayout.QQC2.ApplicationWindow.window.pageStack.layers.push(Qt.createComponent("org.kde.itinerary", "WalkingNavigationPage"), {
                journey: detailsLayout.journey,
                destination: walkButton.stop,
            })
            Layout.fillWidth: true
        }

        /** Where to buy a ticket for this journey.
         *  Preferably a direct booking link for the entire journey, otherwise for its individual sections,
         *  otherwise the websites of the operators running them.
         */
        readonly property var ticketLinks: {
            if (detailsLayout.journey.disruptionEffect === Disruption.NoService) {
                return [];
            }
            let links = [];
            let seen = new Set();
            // bike sharing, at the station to rent from if known
            for (const section of detailsLayout.journey.sections) {
                if (section.mode !== JourneySection.RentedVehicle) {
                    continue;
                }
                const rental = section.rentalVehicle;
                const rentalUrl = [String(section.bookingUrl), String(rental.network.url)].find((url) => url !== "");
                if (rentalUrl && !seen.has(rentalUrl)) {
                    seen.add(rentalUrl);
                    links.push({ text: i18nc("@action:button rent a bike from a bike sharing service", "Rent at %1", rental.network.name), url: rentalUrl, isDirect: true, iconName: section.iconName });
                }
            }
            // the link for the entire journey is the rental one if that's all to book
            const journeyUrl = String(detailsLayout.journey.bookingUrl);
            if (journeyUrl !== "" && !seen.has(journeyUrl)) {
                links.unshift({ text: i18nc("@action:button purchase a ticket", "Buy Ticket"), url: journeyUrl, isDirect: true });
            }
            for (const section of detailsLayout.journey.sections) {
                if (section.mode !== JourneySection.PublicTransport || journeyUrl !== "") {
                    continue;
                }
                const line = section.route.line;
                const sectionUrl = String(section.bookingUrl);
                const operatorUrl = String(line.operatorUrl);
                if (sectionUrl !== "" && !seen.has(sectionUrl)) {
                    seen.add(sectionUrl);
                    links.push({ text: i18nc("@action:button purchase a ticket for a train, bus, etc.", "Buy Ticket for %1", line.name), url: sectionUrl, isDirect: true });
                } else if (sectionUrl === "" && operatorUrl !== "" && !seen.has(operatorUrl)) {
                    seen.add(operatorUrl);
                    const name = line.operatorName !== "" ? line.operatorName : new URL(operatorUrl).hostname;
                    links.push({ text: i18nc("@action:button website of a transport company to buy tickets at", "Tickets from %1", name), url: operatorUrl, isDirect: false });
                }
            }
            return links;
        }

        Repeater {
            model: detailsLayout.ticketLinks

            delegate: ColumnLayout {
                id: ticketLink

                required property var modelData
                required property int index

                spacing: 0
                Layout.fillWidth: true

                FormCard.FormDelegateSeparator {}
                FormCard.FormButtonDelegate {
                    text: ticketLink.modelData.text
                    description: ticketLink.modelData.isDirect
                        ? new URL(ticketLink.modelData.url).hostname
                        : i18nc("@info %1 is a host name", "Website of the transport company, %1", new URL(ticketLink.modelData.url).hostname)
                    icon.name: ticketLink.modelData.iconName ?? "view-financial-account-cash-symbolic"
                    onClicked: Qt.openUrlExternally(ticketLink.modelData.url)
                    Layout.fillWidth: true
                }
            }
        }

        FormCard.FormDelegateSeparator {
            above: selectButton
            visible: selectButton.visible
        }

        FormCard.FormButtonDelegate {
            id: selectButton

            text: detailsLayout.selectText
            icon.name: "checkmark"
            // only public transport ends up in the itinerary, so there's nothing to add without
            visible: detailsLayout.firstTransportSection !== null
            enabled: detailsLayout.journey.disruptionEffect !== Disruption.NoService
            onClicked: detailsLayout.selected()
        }
    }

    readonly property KSortFilterProxyModel journeyProxyModel: KSortFilterProxyModel {
        id: sortedJourneyModel

        sourceModel: JourneyQueryModel {
            id: journeyModel
        }
        sortRole: JourneyQueryModel.ScheduledDepartureTime
        dynamicSortFilter: true
        filterRowCallback: function(sourceRow, sourceParent) {
            if (root.isArrival || root.showEarlierJourneys || root.showTimeline) {
                return true;
            }
            const journey = sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), JourneyQueryModel.JourneyRole);
            return root.departsInTime(journey);
        }
        Component.onCompleted: Util.sortModel(sortedJourneyModel, 0, Qt.Ascending)
    }

    Component {
        id: journeyDetailsPage

        FormCard.FormCardPage {
            id: detailsPage

            property var journey

            title: i18nc("@title", "Connection Details")

            FormCard.FormCard {
                Layout.topMargin: Kirigami.Units.largeSpacing

                JourneyDetailsLayout {
                    journey: detailsPage.journey
                    selectText: root.selectText
                    onSelected: root.journey = detailsPage.journey
                }
            }
        }
    }

    Component {
        id: earlierButtonComponent

        VerticalNavigationButton {
            visible: journeyModel.canQueryPrevious
            width: journeyView.width
            text: i18nc("@action:button", "Load earlier connections")
            iconName: "go-up-symbolic"
            onClicked: {
                root.showEarlierJourneys = true;
                journeyModel.queryPrevious();
            }
        }
    }

    Component {
        id: daySectionDelegate
        TimelineSectionDelegate {
            required property string section
            day: section
        }
    }

    Component {
        id: timelineComponent

        JourneyTimelineView {
            width: journeyView.width
            journeys: sortedJourneyModel
            verticalFlickable: journeyView
            // open at the current time, or at the requested time if that is on another day
            focusTime: new Date()
            fallbackFocusTime: root.journeyRequest.dateTime
            canQueryPrevious: journeyModel.canQueryPrevious
            canQueryNext: journeyModel.canQueryNext
            onQueryPrevious: root.loadMore(true)
            onQueryNext: root.loadMore(false)
            onJourneyClicked: (journey) => root.QQC2.ApplicationWindow.window.pageStack.push(journeyDetailsPage, { journey: journey })
        }
    }

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Window

    // summary of what we are searching for, so it's clear which results these are
    header: QQC2.Control {
        visible: root.journeyRequest.from.name !== "" && root.journeyRequest.to.name !== ""
        padding: Kirigami.Units.largeSpacing

        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: Kirigami.Theme.Header

        background: Rectangle {
            color: Kirigami.Theme.backgroundColor

            Kirigami.Separator {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: 0

            QQC2.Label {
                text: i18nc("journey from departure to arrival stop", "%1 → %2", root.journeyRequest.from.name, root.journeyRequest.to.name)
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            QQC2.Label {
                readonly property string dateTime: root.journeyRequest.dateTime.toLocaleString(Qt.locale(), Locale.ShortFormat)
                text: root.isArrival ? i18nc("@info journey search, arrival time", "Arriving by %1", dateTime)
                                     : i18nc("@info journey search, departure time", "Departing from %1", dateTime)
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    ListView {
        id: journeyView

        clip: true
        cacheBuffer: height

        Component {
            id: listDelegate

            FormCard.FormCard {
                id: topDelegate

                required property int index
                required property var journey
                width: ListView.view.width
                height: loader.status === Loader.Ready ? loader.item.implicitHeight : 100 // TODO can we predict the height accurately?

                Loader {
                    id: loader
                    Layout.fillWidth: true

                    Rectangle {
                        id: loadingAnimationItem
                        color: Kirigami.Theme.backgroundColor
                        anchors.fill: parent

                        z: 1000

                        OpacityAnimator {
                            target: loadingAnimationItem
                            from: 1
                            to: 0
                            duration: Kirigami.Units.shortDuration
                            running: loader.status === Loader.Ready
                        }
                    }

                    visible: loader.status === Loader.Ready
                    asynchronous: true
                    sourceComponent: Loader {
                        Layout.fillWidth: true

                        Component {
                            id: expanded

                            JourneyDetailsLayout {
                                journey: topDelegate.journey
                                selectText: root.selectText
                                onSelected: root.journey = topDelegate.journey
                            }
                        }

                        Component {
                            id: compact

                            JourneySummaryDelegate {
                                id: summaryButton

                                journey: topDelegate.journey

                                onClicked: journeyView.currentIndex = topDelegate.index

                                Layout.fillWidth: true
                            }
                        }

                        sourceComponent: journeyView.currentIndex == topDelegate.index ? expanded : compact
                    }
                }
            }
        }

        section {
            property: root.showTimeline ? "" : (root.isArrival ? "scheduledArrivalDate" : "scheduledDepartureDate")
            // the timeline shows the date itself, an empty section header would remain otherwise
            delegate: root.showTimeline ? null : daySectionDelegate
        }

        spacing: Kirigami.Units.largeSpacing

        footer: ColumnLayout {
            width: journeyView.width
            spacing: 0

            VerticalNavigationButton {
                visible: journeyModel.canQueryNext && !root.showTimeline
                Layout.fillWidth: true
                iconName: "go-down-symbolic"
                text: i18nc("@action:button", "Load later connections")
                onClicked: journeyModel.queryNext()
            }

            FormCard.FormCard {
                visible: journeyModel.attributions.length > 0

                FormCard.FormTextDelegate {
                    text: i18n("Data providers:")
                    description: PublicTransport.attributionSummary(journeyModel.attributions)
                    onLinkActivated: (link) => { Qt.openUrlExternally(link); }
                }
            }
        }

        Kirigami.LoadingPlaceholder {
            text: if (journeyModel.loading) {
                return i18nc("@info:placeholder", "Loading");
            } else if (journeyModel.errorMessage.length > 0) {
                return i18nc("@info:status", "Error")
            } else {
                return i18nc("@info:placeholder", "No journeys found")
            }
            visible: sortedJourneyModel.count === 0

            icon.name: journeyModel.errorMessage.length > 0 ? "network-disconnect-symbolic" : ""
            explanation: journeyModel.errorMessage
            progressBar.visible: journeyModel.loading
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 4
        }

        // when searching for arrivals the closest result is at the bottom of the list
        // so jump there once the first result batch has been added
        // ideally we'd want to automatically move there also for subsequent batches *unless*
        // the user has meanwhile altered the scroll position manually, but that's hard to detect reliably
        property int previousCount: 0
        onCountChanged: {
            if (root.isArrival && previousCount === 0) {
                Qt.callLater(positionViewAtEnd);
            }
            previousCount = count;
        }
    }

    footer: ColumnLayout {
        spacing: 0
        height: indicator.running ? layout.implicitHeight : 0
        visible: journeyModel.loading && sortedJourneyModel.count !== 0

        Behavior on height {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        RowLayout {
            id: layout

            QQC2.BusyIndicator {
                id: indicator
                running: journeyModel.loading && sortedJourneyModel.count !== 0
            }

            QQC2.Label {
                text: i18n("Still fetching results…")
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
