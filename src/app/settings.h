/*
    SPDX-FileCopyrightText: 2018 Volker Krause <vkrause@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#ifndef SETTINGS_H
#define SETTINGS_H

#include <KFormat>

#include <QObject>
#include <QUrl>

/** Application settings accessible by QML. */
class Settings : public QObject
{
    Q_OBJECT
    /** The page shown when the application starts. */
    Q_PROPERTY(StartPage startPage READ startPage WRITE setStartPage NOTIFY startPageChanged)
    /** Only search for journeys using local public transport, e.g. for flat rate tickets like the Deutschlandticket. */
    Q_PROPERTY(bool localTransportOnly READ localTransportOnly WRITE setLocalTransportOnly NOTIFY localTransportOnlyChanged)
    /** Consider rental bikes for getting to and from public transport, or for the entire journey. */
    Q_PROPERTY(bool rentalBikes READ rentalBikes WRITE setRentalBikes NOTIFY rentalBikesChanged)
    /** Also search for journeys by plane. Off by default, as flight data is only available in a few regions so far. */
    Q_PROPERTY(bool includeFlights READ includeFlights WRITE setIncludeFlights NOTIFY includeFlightsChanged)
    /** Show journey search results on a time axis rather than as a list. */
    Q_PROPERTY(bool journeyResultsAsTimeline READ journeyResultsAsTimeline WRITE setJourneyResultsAsTimeline NOTIFY journeyResultsAsTimelineChanged)
    Q_PROPERTY(bool weatherForecastEnabled READ weatherForecastEnabled WRITE setWeatherForecastEnabled NOTIFY weatherForecastEnabledChanged)
    Q_PROPERTY(QString homeCountryIsoCode READ homeCountryIsoCode WRITE setHomeCountryIsoCode NOTIFY homeCountryIsoCodeChanged)
    Q_PROPERTY(bool forceMetricUnits READ forceMetricUnits WRITE setForceMetricUnits NOTIFY forceMetricUnitsChanged)
    Q_PROPERTY(bool queryLiveData READ queryLiveData WRITE setQueryLiveData NOTIFY queryLiveDataChanged)
    Q_PROPERTY(bool preloadMapData READ preloadMapData WRITE setPreloadMapData NOTIFY preloadMapDataChanged)

    /** The welcome page has been shown and acknowledged by the user. */
    Q_PROPERTY(bool welcomePageShown READ welcomePageShown WRITE setWelcomePageShown NOTIFY welcomePageShownChanged)

    Q_PROPERTY(bool performCurrencyConversion READ performCurrencyConversion WRITE setPerformCurrencyConversion NOTIFY performCurrencyConversionChanged)
    Q_PROPERTY(bool wikimediaOnlineContentEnabled READ wikimediaOnlineContentEnabled WRITE setWikimediaOnlineContentEnabled NOTIFY
                   wikimediaOnlineContentEnabledChanged)

    Q_PROPERTY(bool autoAddTransfers READ autoAddTransfers WRITE setAutoAddTransfers NOTIFY autoAddTransfersChanged)
    Q_PROPERTY(bool autoFillTransfers READ autoFillTransfers WRITE setAutoFillTransfers NOTIFY autoFillTransfersChanged)

    Q_PROPERTY(
        bool showNotificationOnLockScreen READ showNotificationOnLockScreen WRITE setShowNotificationOnLockScreen NOTIFY showNotificationOnLockScreenChanged)

    Q_PROPERTY(bool osmContributorMode MEMBER m_osmContributorMode WRITE setOsmContributorMode NOTIFY osmContributorModeChanged)
    Q_PROPERTY(bool developmentMode READ developmentMode WRITE setDevelopmentMode NOTIFY developmentModeChanged)

    Q_PROPERTY(bool useFahrenheit READ useFahrenheit NOTIFY useFahrenheitChanged)
    Q_PROPERTY(KFormat::DistanceFormatOptions distanceFormat READ distanceFormat NOTIFY forceMetricUnitsChanged)

public:
    explicit Settings(QObject *parent = nullptr);
    ~Settings() override;

    Q_INVOKABLE [[nodiscard]] static QVariant read(const QString &key, const QVariant &defaultValue);
    Q_INVOKABLE static void write(const QString &key, const QVariant &value);

    /** Load/save file dialog directory. */
    Q_INVOKABLE [[nodiscard]] static QUrl readFileDialogFolder(const QString &key, const QUrl &defaultUrl);
    Q_INVOKABLE static void writeFileDialogFolder(const QString &key, const QUrl &url);

    [[nodiscard]] bool weatherForecastEnabled() const;
    void setWeatherForecastEnabled(bool enabled);

    [[nodiscard]] QString homeCountryIsoCode() const;
    void setHomeCountryIsoCode(const QString &isoCode);

    [[nodiscard]] bool forceMetricUnits() const;
    void setForceMetricUnits(bool force);

    [[nodiscard]] bool queryLiveData() const;
    void setQueryLiveData(bool queryLiveData);

    [[nodiscard]] bool preloadMapData() const;
    void setPreloadMapData(bool preload);

    enum StartPage {
        ItineraryStartPage,
        TicketsStartPage,
        MyDataStartPage,
    };
    Q_ENUM(StartPage)

    [[nodiscard]] StartPage startPage() const;
    void setStartPage(StartPage startPage);

    [[nodiscard]] bool localTransportOnly() const;
    void setLocalTransportOnly(bool localOnly);

    [[nodiscard]] bool rentalBikes() const;
    void setRentalBikes(bool rentalBikes);

    [[nodiscard]] bool includeFlights() const;
    void setIncludeFlights(bool includeFlights);

    [[nodiscard]] bool journeyResultsAsTimeline() const;
    void setJourneyResultsAsTimeline(bool asTimeline);

    [[nodiscard]] bool welcomePageShown() const;
    void setWelcomePageShown(bool shown);

    /** Name of the image asset the ticket view shows as moving image
     *  for Apple Wallet passes of type @p passTypeIdentifier.
     *  Empty if the user hasn't chosen one.
     */
    Q_INVOKABLE [[nodiscard]] QString ticketViewImage(const QString &passTypeIdentifier) const;
    Q_INVOKABLE void setTicketViewImage(const QString &passTypeIdentifier, const QString &assetName);

    [[nodiscard]] bool performCurrencyConversion() const;
    void setPerformCurrencyConversion(bool enable);

    [[nodiscard]] bool wikimediaOnlineContentEnabled() const;
    void setWikimediaOnlineContentEnabled(bool enable);

    [[nodiscard]] bool autoAddTransfers() const;
    void setAutoAddTransfers(bool autoAdd);
    [[nodiscard]] bool autoFillTransfers() const;
    void setAutoFillTransfers(bool autoFill);

    [[nodiscard]] bool showNotificationOnLockScreen() const;
    void setShowNotificationOnLockScreen(bool enabled);

    void setOsmContributorMode(bool enabled);

    [[nodiscard]] bool developmentMode() const;
    void setDevelopmentMode(bool enabled);

    /** Reload settings from disk and emit change notifications.
     *  For use during restoring backups.
     */
    void reloadSettings();

    [[nodiscard]] bool useFahrenheit() const;
    [[nodiscard]] KFormat::DistanceFormatOptions distanceFormat() const;

Q_SIGNALS:
    void weatherForecastEnabledChanged(bool enabled);
    void homeCountryIsoCodeChanged(const QString &isoCode);
    void forceMetricUnitsChanged(bool force);
    void queryLiveDataChanged(bool enabled);
    void preloadMapDataChanged(bool preload);
    void startPageChanged(Settings::StartPage startPage);
    void localTransportOnlyChanged(bool localOnly);
    void rentalBikesChanged(bool rentalBikes);
    void includeFlightsChanged(bool includeFlights);
    void journeyResultsAsTimelineChanged(bool asTimeline);
    void welcomePageShownChanged(bool shown);
    void performCurrencyConversionChanged(bool enabled);
    void wikimediaOnlineContentEnabledChanged(bool enabled);
    void autoAddTransfersChanged(bool autoAdd);
    void autoFillTransfersChanged(bool autoFill);
    void showNotificationOnLockScreenChanged(bool enabled);
    void developmentModeChanged(bool enabled);
    void osmContributorModeChanged(bool enabled);
    void useFahrenheitChanged();

private:
    void load();

    QString m_homeCountry;
    bool m_forceMetricUnits = false;
    bool m_weatherEnabled = false;
    bool m_queryLiveData = false;
    bool m_preloadMapData = false;
    StartPage m_startPage = TicketsStartPage;
    bool m_localTransportOnly = false;
    bool m_rentalBikes = false;
    bool m_includeFlights = false;
    bool m_journeyResultsAsTimeline = true;
    bool m_welcomePageShown = false;
    bool m_currencyConversion = false;
    bool m_wikimediaOnlineContentEnabled = false;
    bool m_autoAddTransfers = true;
    bool m_autoFillTransfers = false;
    bool m_showNotificationOnLockScreen = false;
    bool m_osmContributorMode = false;
    bool m_developmentMode = false;
};

#endif // SETTINGS_H
