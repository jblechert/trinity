/*
    SPDX-FileCopyrightText: 2023 Mathis Brüchert <mbb@kaidan.im>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.itinerary

Kirigami.NavigationTabBar {
    id: root

    // nor while typing, it would sit on top of the on-screen keyboard taking room from what is typed into
    visible: pageStack.layers.depth < 2 && !(Kirigami.Settings.isMobile && Qt.inputMethod.visible)
    actions: [
        Kirigami.PagePoolAction {
            icon.name: "format-list-unordered"
            text: i18nc("@title:tab This isn't the app name, but the English noun", "Itinerary")
            pagePool: pagepool
            page: Qt.resolvedUrl("TripGroupsPage.qml")
        },
        Kirigami.Action {
            icon.name: "search"
            text: i18nc("@title:tab", "Plan Trip")
            onTriggered: {
                if (pageStack.currentItem as JourneyRequestPage) {
                    return;
                }
                if (pageStack.currentItem as TripGroupPage) {
                    pageStack.currentItem.searchConnection();
                } else {
                    pageStack.clear();
                    pageStack.push(Qt.resolvedUrl("JourneyRequestPage.qml"), {
                        publicTransportManager: LiveDataManager.publicTransportManager,
                    });
                }
            }
        },
        Kirigami.PagePoolAction {
            icon.name: "map-symbolic"
            text: i18nc("@title:tab", "Map")
            pagePool: pagepool
            page: Qt.resolvedUrl("MapPage.qml")
        },
        Kirigami.PagePoolAction {
            id: currentTicketAction

            readonly property bool hasCurrentReservation: TripGroupModel.currentBatchId !== ""

            text: i18nc("@title:tab", "Current Ticket")
            icon.name: "view-barcode-qr"
            pagePool: pagepool
            // with an empty page the page pool action does nothing, and we show the current reservation instead
            page: currentTicketAction.hasCurrentReservation ? "" : Qt.resolvedUrl("TicketsPage.qml")
            onTriggered: {
                if (currentTicketAction.hasCurrentReservation) {
                    currentTicketAction.checked = false;
                    pagepool.loadPage(Qt.resolvedUrl("TripGroupsPage.qml")).openCurrentReservation();
                }
            }
        },
        Kirigami.PagePoolAction {
            icon.name: "user-identity-symbolic"
            text: i18nc("@title:tab", "My Data")
            pagePool: pagepool
            page: Qt.resolvedUrl("MyDataPage.qml")
        }
    ]
}
