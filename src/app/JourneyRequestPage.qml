/*
    SPDX-FileCopyrightText: 2021 Volker Krause <vkrause@kde.org>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard
import org.kde.kirigamiaddons.dateandtime as Addon
import org.kde.kpublictransport
import org.kde.kpublictransport.ui as KPublicTransport
import org.kde.itinerary

FormCard.FormCardPage {
    id: root

    property KPublicTransport.Manager publicTransportManager

    /** Preselected departure time. */
    property date initialDateTime: new Date()

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Window

    property var departureStop
    property var arrivalStop

    /** The line modes to search for, flights only if enabled, see Settings.includeFlights. */
    property var lineModes: [
        Line.LongDistanceTrain, Line.Train,
        Line.LocalTrain,
        Line.RapidTransit, Line.Metro, Line.Tramway, Line.RailShuttle, Line.Funicular, Line.AerialLift,
        Line.Bus, Line.Coach, Line.Shuttle, Line.Taxi,
        Line.Ferry, Line.Boat,
    ].concat(Settings.includeFlights ? [Line.Air] : [])

    /** Line modes not usable with tickets valid for local public transport only.
     *  Like in JourneyFilterPage, unspecified trains count as long distance trains, as some backends use that for those.
     */
    readonly property var nonLocalLineModes: [Line.LongDistanceTrain, Line.Train, Line.Coach, Line.Air]
    /** The line modes to search for, considering the selected ticket type. */
    readonly property var effectiveLineModes: Settings.localTransportOnly
        ? root.lineModes.filter((mode) => root.nonLocalLineModes.indexOf(mode) === -1)
        : root.lineModes

    title: i18n("Select Journey")

    actions: [
        Kirigami.Action {
            icon.name: "map-symbolic"
            text: i18nc("@action:button pick departure and arrival on a map", "Pick on Map")
            onTriggered: {
                const map = pagepool.loadPage(Qt.resolvedUrl("MapPage.qml"));
                map.journeyFrom = root.departureStop;
                map.journeyTo = root.arrivalStop;
                map.plannerShown = true;
                applicationWindow().pageStack.clear();
                applicationWindow().pageStack.push(map);
                map.showJourneyEndpoints();
            }
        }
    ]

    /** Search departures from @p from to @p to starting now, regardless of the time selected in the form. */
    function searchJourneyNow(from: var, to: var): void {
        root.departureStop = PublicTransport.copyLocation(from);
        root.arrivalStop = PublicTransport.copyLocation(to);
        departureArrivalSelector.selectedIndex = 0;
        dateTimeInput.value = new Date();
        root.searchJourney();
    }

    /** Search the journey entered on this page, and return the page with the results. */
    function searchJourney(): var {
        JourneyRequestHistoryModel.addJourneyRequest(root.departureStop, root.arrivalStop);

        applicationWindow().pageStack.push(journeyQueryPage);
        const queryPage = applicationWindow().pageStack.currentItem;
        queryPage.allLineModes = root.lineModes;
        queryPage.localLineModes = root.lineModes.filter((mode) => root.nonLocalLineModes.indexOf(mode) === -1);
        const req = queryPage.journeyRequest;
        req.from = root.departureStop;
        req.to = root.arrivalStop;

        console.log(dateTimeInput.value);
        req.dateTime = dateTimeInput.value;
        req.maximumResults = 6;
        req.downloadAssets = Settings.wikimediaOnlineContentEnabled;
        req.includePaths = true;
        req.modes = JourneySection.PublicTransport | JourneySection.Walking;
        if (Settings.rentalBikes) {
            // to and from public transport, or all the way
            const rentalBike = [{ mode: IndividualTransport.Bike, qualifier: IndividualTransport.Rent }];
            req.modes |= JourneySection.IndividualTransport;
            req.individualTransportModes = rentalBike;
            req.accessModes = rentalBike;
            req.egressModes = rentalBike;
        }

        req.lineModes = root.effectiveLineModes;

        if (departureArrivalSelector.selectedIndex === 0) {
            req.dateTimeMode = JourneyRequest.Departure
        } else if (departureArrivalSelector.selectedIndex === 1) {
            req.dateTimeMode = JourneyRequest.Arrival
        }

        console.log(req);
        queryPage.journeyRequest = req;
        return queryPage;
    }

    // This is used if we are creating the first trip group
    Component {
        id: newTripGroupDialogComponent

        TripGroupEditorDialog {
            id: createTripDialog
            tripGroupName: root.arrivalStop ? root.arrivalStop.name : ""

            signal tripGroupSelected(string id)

            onAccepted: {
                const tgId = TripGroupManager.createEmptyGroup(createTripDialog.tripGroupName);
                createTripDialog.tripGroupSelected(tgId)
            }
        }
    }

    Component {
        id: tripGroupDialogComponent

        TripGroupSelectorDialog {
            id: tripGroupDialog

            suggestedName: root.arrivalStop ? root.arrivalStop.name : ""
        }
    }

    data: [
        Component {
            id: departurePicker
            StopPickerPage {
                title: i18nc("departure train station", "Select Departure Stop")
                publicTransportManager: root.publicTransportManager
                // force a deep copy, otherwise this breaks as soon as the other stop picker page is shown...
                onLocationChanged: root.departureStop = PublicTransport.copyLocation(location);
                historySortRoleName: Settings.read("StopPicker/historySortMode", "lastUsed")
                onHistorySortRoleChanged: (sortRoleName) => Settings.write("StopPicker/historySortMode", sortRoleName)
                showUseCurrentLocationButton: true
            }
        },
        Component {
            id: arrivalPicker
            StopPickerPage {
                title: i18nc("arrival train station", "Select Arrival Stop")
                publicTransportManager: root.publicTransportManager
                onLocationChanged: root.arrivalStop = PublicTransport.copyLocation(location)
                historySortRoleName: Settings.read("StopPicker/historySortMode", "lastUsed")
                onHistorySortRoleChanged: (sortRoleName) => Settings.write("StopPicker/historySortMode", sortRoleName)
            }
        },
        Component {
            id: journeyQueryPage
            JourneyQueryPage {
                id: queryPage

                publicTransportManager: root.publicTransportManager
                title: i18n("Select Journey")
                selectText: i18nc("@action:button add the selected journey to a trip", "Add to Itinerary")
                onJourneyChanged: {
                    // reset when the dialog is closed, so the same journey can be selected again
                    if (!queryPage.journey) {
                        return;
                    }
                    // popups need a parent with a window to be shown at all
                    const dialogParent = root.QQC2.Overlay.overlay;
                    let tripGroupDialog = TripGroupModel.rowCount() < 1 ? newTripGroupDialogComponent.createObject(dialogParent) : tripGroupDialogComponent.createObject(dialogParent);

                    tripGroupDialog.tripGroupSelected.connect((tgId) => {
                        for (const section of queryPage.journey.sections) {
                            if (section.mode != JourneySection.PublicTransport) {
                                continue;
                                }
                            const res = PublicTransport.reservationFromJourneySection(section);
                            const resId = ApplicationController.addNewReservation(res, tgId);
                            LiveDataManager.setJourney(resId, section);
                        }
                        ApplicationController.contextTripGroupId = tgId;
                        tripGroupDialog.close()
                        pageStack.clear()
                        pageStack.push(pagepool.loadPage(Qt.resolvedUrl("TripGroupsPage.qml")))
                    })
                    tripGroupDialog.closed.connect(() => {
                        if (queryPage) {
                            queryPage.journey = undefined;
                        }
                        tripGroupDialog.destroy()
                    })

                    tripGroupDialog.open()
                }
            }
        },
        Component {
            id: journeyFilterPage
            JourneyFilterPage {
                initialLineModes: root.lineModes
            }
        }

    ]

    FormCard.FormCard {
        id: requestCard

        Layout.topMargin: Kirigami.Units.gridUnit

        FormCard.FormButtonDelegate {
            id: fromButton

            text: i18nc("departure train station", "From:")
            description: departureStop ? departureStop.name : i18nc("departure train station", "Select Departure Stop")
            onClicked: applicationWindow().pageStack.push(departurePicker)
        }


        FormCard.FormDelegateSeparator {
            below: fromButton
            above: toButton
        }

        FormCard.FormButtonDelegate {
            id: toButton

            text: i18nc("arrival train station", "To:")
            description: arrivalStop ? arrivalStop.name : i18nc("arrival train station", "Select Arrival Stop")
            onClicked: applicationWindow().pageStack.push(arrivalPicker)
        }
        Item{
            width:parent.width
            height: 0
            QQC2.RoundButton{
                icon.name: "reverse"
                y: -fromButton.height - height/2
                z: toButton.z + 10000
                x: fromButton.width - width/2 - Kirigami.Units.gridUnit *3
                onClicked:{
                    var oldDepartureStop = departureStop
                    departureStop = arrivalStop
                    arrivalStop = oldDepartureStop
                }

                Accessible.name: i18nc("departure and arrival stops", "Swap departure and arrival")
            }
        }
        FormCard.FormDelegateSeparator {
            below: toButton
            above: departureArrivalSelector
        }

        FormCard.FormRadioSelectorDelegate {
            id: departureArrivalSelector

            consistentWidth: true

            actions: [
                Kirigami.Action {
                    text: i18nc("train or bus departure", "Departure")
                },
                Kirigami.Action {
                    text: i18nc("train or bus arrival", "Arrival")
                }
            ]
        }

        FormCard.FormDelegateSeparator {
            below: departureArrivalSelector
            above: dateTimeInput
        }

        FormCard.FormDateTimeDelegate {
            id: dateTimeInput
            value: root.initialDateTime
            Accessible.name: departureArrivalSelector.selectedIndex === 0 ? i18nc("train or bus departure", "Departure time") : i18nc("train or bus arrival", "Arrival time")
        }

        FormCard.FormDelegateSeparator {
            below: dateTimeInput
            above: ticketTypeSelector
        }

        FormCard.FormComboBoxDelegate {
            id: ticketTypeSelector

            text: i18nc("@label:listbox the kind of ticket to find journeys for", "Ticket")
            model: [
                { text: i18nc("@item:inlistbox ticket type", "All connections (e.g. BahnCard 100)"), value: false },
                { text: i18nc("@item:inlistbox ticket type", "Local transport only (e.g. Deutschlandticket)"), value: true },
            ]
            textRole: "text"
            valueRole: "value"
            currentIndex: Settings.localTransportOnly ? 1 : 0
            onActivated: Settings.localTransportOnly = currentValue
        }

        FormCard.FormDelegateSeparator {
            below: ticketTypeSelector
            above: rentalBikesSwitch
        }

        FormCard.FormSwitchDelegate {
            id: rentalBikesSwitch

            text: i18nc("@option:check consider bike sharing in the journey search", "Rental bikes")
            description: i18nc("@info", "To and from stations, or all the way, where bike sharing is known")
            checked: Settings.rentalBikes
            onToggled: Settings.rentalBikes = rentalBikesSwitch.checked
        }

        FormCard.FormDelegateSeparator {
            below: rentalBikesSwitch
            above: flightsSwitch
        }

        FormCard.FormSwitchDelegate {
            id: flightsSwitch

            text: i18nc("@option:check consider flights in the journey search", "Include flights")
            description: i18nc("@info", "Flight data is only available in a few regions so far")
            checked: Settings.includeFlights
            onToggled: {
                Settings.includeFlights = flightsSwitch.checked;
                // also when the line modes were changed in the filter, flights only in addition to other modes
                const modes = root.lineModes.filter((mode) => mode !== Line.Air);
                root.lineModes = flightsSwitch.checked && modes.length > 0 ? modes.concat([Line.Air]) : modes;
            }
        }

        FormCard.FormDelegateSeparator {
            below: flightsSwitch
            above: filterButton
        }

        FormCard.FormButtonDelegate {
            id: filterButton

            text: i18nc("filter journeys by mode of transportation etc.", "Filter")
            icon.name: "filter-symbolic"

            onClicked: {
                let page = pageStack.push(journeyFilterPage)
                root.lineModes = Qt.binding(() => page.lineModes)
            }
        }

        FormCard.FormDelegateSeparator {
            below: filterButton
            above: searchButton
        }

        FormCard.FormButtonDelegate {
            id: searchButton
            icon.name: "search"
            text: i18n("Search Journey")
            enabled: root.departureStop != undefined && root.arrivalStop != undefined && root.effectiveLineModes.length != 0
            onClicked: root.searchJourney()
        }
    }

    FormCard.FormHeader {
        title: i18nc("@title:group previously searched journeys", "Recent Journeys")
        visible: historyRepeater.count > 0
    }

    FormCard.FormCard {
        visible: historyRepeater.count > 0

        Repeater {
            id: historyRepeater

            model: JourneyRequestHistoryModel
            delegate: FormCard.AbstractFormDelegate {
                id: historyDelegate

                required property int index
                required property var from
                required property var to
                required property int useCount

                text: i18nc("journey from departure to arrival stop", "%1 → %2", historyDelegate.from.name, historyDelegate.to.name)
                onClicked: root.searchJourneyNow(historyDelegate.from, historyDelegate.to)

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    QQC2.ToolButton {
                        icon.name: "reverse"
                        text: i18nc("@action:button search the journey in the opposite direction", "Search return journey")
                        display: QQC2.AbstractButton.IconOnly
                        onClicked: root.searchJourneyNow(historyDelegate.to, historyDelegate.from)

                        QQC2.ToolTip.text: text
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }

                    ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Layout.fillWidth: true

                        QQC2.Label {
                            text: historyDelegate.text
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        QQC2.Label {
                            text: i18ncp("number of times a journey was searched", "Searched once", "Searched %1 times", historyDelegate.useCount)
                            font: Kirigami.Theme.smallFont
                            color: Kirigami.Theme.disabledTextColor
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    QQC2.ToolButton {
                        icon.name: "edit-delete"
                        text: i18nc("@action:button", "Remove from history")
                        display: QQC2.AbstractButton.IconOnly
                        onClicked: JourneyRequestHistoryModel.removeEntry(historyDelegate.index)

                        QQC2.ToolTip.text: text
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
