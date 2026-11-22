/*
    SPDX-FileCopyrightText: 2018 Volker Krause <vkrause@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#include "settings.h"

#include <KCountry>

#include <QDebug>
#include <QLocale>
#include <QSettings>

#include <algorithm>

using namespace Qt::Literals::StringLiterals;

Settings::Settings(QObject *parent)
    : QObject(parent)
{
    m_homeCountry = KCountry::fromQLocale(QLocale().territory()).alpha2();
    load();
}

Settings::~Settings() = default;

void Settings::load()
{
    QSettings s;
    s.beginGroup("Settings"_L1);
    m_weatherEnabled = s.value("WeatherForecastEnabled"_L1, m_weatherEnabled).toBool();

    m_homeCountry = s.value("HomeCountry"_L1, m_homeCountry).toString();
    m_forceMetricUnits = s.value("ForceMetricUnits"_L1, m_forceMetricUnits).toBool();

    m_queryLiveData = s.value("QueryLiveData"_L1, m_queryLiveData).toBool();

    m_preloadMapData = s.value("PreloadMapData"_L1, m_preloadMapData).toBool();

    m_startPage = static_cast<StartPage>(std::clamp(s.value("StartPage"_L1, static_cast<int>(m_startPage)).toInt(),
                                                    static_cast<int>(ItineraryStartPage),
                                                    static_cast<int>(MyDataStartPage)));
    m_localTransportOnly = s.value("LocalTransportOnly"_L1, m_localTransportOnly).toBool();
    m_rentalBikes = s.value("RentalBikes"_L1, m_rentalBikes).toBool();
    m_includeFlights = s.value("IncludeFlights"_L1, m_includeFlights).toBool();
    m_journeyResultsAsTimeline = s.value("JourneyResultsAsTimeline"_L1, m_journeyResultsAsTimeline).toBool();
    m_welcomePageShown = s.value("WelcomePageShown"_L1, m_welcomePageShown).toBool();
    m_currencyConversion = s.value("PerformCurrencyConversion"_L1, m_currencyConversion).toBool();
    m_wikimediaOnlineContentEnabled = s.value("WikimediaOnlineContent"_L1, m_wikimediaOnlineContentEnabled).toBool();

    m_autoAddTransfers = s.value("AutoAddTransfers"_L1, m_autoAddTransfers).toBool();
    m_autoFillTransfers = s.value("AutoFillTransfers"_L1, m_autoFillTransfers).toBool() && m_queryLiveData && m_autoAddTransfers;

    m_showNotificationOnLockScreen = s.value("ShowNotificationOnLockScreen"_L1, m_showNotificationOnLockScreen).toBool();

    m_osmContributorMode = s.value("OsmContributorMode"_L1, m_osmContributorMode).toBool();
    m_developmentMode = s.value("DevelopmentMode"_L1, m_developmentMode).toBool();

    connect(this, &Settings::homeCountryIsoCodeChanged, this, &Settings::useFahrenheitChanged);
    connect(this, &Settings::forceMetricUnitsChanged, this, &Settings::useFahrenheitChanged);
}

void Settings::reloadSettings()
{
    load();

    Q_EMIT weatherForecastEnabledChanged(m_weatherEnabled);
    Q_EMIT homeCountryIsoCodeChanged(m_homeCountry);
    Q_EMIT forceMetricUnitsChanged(m_forceMetricUnits);
    Q_EMIT queryLiveDataChanged(m_queryLiveData);
    Q_EMIT preloadMapDataChanged(m_preloadMapData);
    Q_EMIT startPageChanged(m_startPage);
    Q_EMIT localTransportOnlyChanged(m_localTransportOnly);
    Q_EMIT rentalBikesChanged(m_rentalBikes);
    Q_EMIT includeFlightsChanged(m_includeFlights);
    Q_EMIT journeyResultsAsTimelineChanged(m_journeyResultsAsTimeline);
    Q_EMIT welcomePageShownChanged(m_welcomePageShown);
    Q_EMIT performCurrencyConversionChanged(m_currencyConversion);
    Q_EMIT wikimediaOnlineContentEnabledChanged(m_wikimediaOnlineContentEnabled);
    Q_EMIT autoAddTransfersChanged(m_autoAddTransfers);
    Q_EMIT autoFillTransfersChanged(m_autoFillTransfers);
    Q_EMIT showNotificationOnLockScreenChanged(m_showNotificationOnLockScreen);
    Q_EMIT developmentModeChanged(m_developmentMode);
    Q_EMIT osmContributorModeChanged(m_osmContributorMode);
}

QVariant Settings::read(const QString &key, const QVariant &defaultValue)
{
    QSettings s;
    return s.value(key, defaultValue);
}

void Settings::write(const QString &key, const QVariant &value)
{
    QSettings s;
    s.setValue(key, value);
}

QUrl Settings::readFileDialogFolder(const QString &key, const QUrl &defaultUrl)
{
    QSettings s;
    s.beginGroup("FileDialog"_L1);
    return QUrl(s.value(key, defaultUrl.toString(QUrl::FullyEncoded)).toString());
}

void Settings::writeFileDialogFolder(const QString &key, const QUrl &url)
{
    QSettings s;
    s.beginGroup("FileDialog"_L1);
    s.setValue(key, url.resolved(QUrl("."_L1)).toString(QUrl::FullyEncoded)); // drop the file name
}

bool Settings::weatherForecastEnabled() const
{
    return m_weatherEnabled;
}

void Settings::setWeatherForecastEnabled(bool enabled)
{
    if (m_weatherEnabled == enabled) {
        return;
    }

    m_weatherEnabled = enabled;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("WeatherForecastEnabled"_L1, enabled);

    Q_EMIT weatherForecastEnabledChanged(enabled);
}

QString Settings::homeCountryIsoCode() const
{
    return m_homeCountry;
}

void Settings::setHomeCountryIsoCode(const QString &isoCode)
{
    if (m_homeCountry == isoCode) {
        return;
    }

    m_homeCountry = isoCode;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("HomeCountry"_L1, isoCode);

    Q_EMIT homeCountryIsoCodeChanged(isoCode);
}

bool Settings::forceMetricUnits() const
{
    return m_forceMetricUnits;
}

void Settings::setForceMetricUnits(bool force)
{
    if (m_forceMetricUnits == force) {
        return;
    }

    m_forceMetricUnits = force;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("ForceMetricUnits"_L1, force);

    Q_EMIT forceMetricUnitsChanged(force);
}

bool Settings::queryLiveData() const
{
    return m_queryLiveData;
}

void Settings::setQueryLiveData(bool queryLiveData)
{
    if (!queryLiveData) {
        setAutoFillTransfers(false);
    }

    if (m_queryLiveData == queryLiveData) {
        return;
    }

    m_queryLiveData = queryLiveData;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("QueryLiveData"_L1, queryLiveData);

    Q_EMIT queryLiveDataChanged(queryLiveData);
}

bool Settings::preloadMapData() const
{
    return m_preloadMapData;
}

void Settings::setPreloadMapData(bool preload)
{
    if (m_preloadMapData == preload) {
        return;
    }

    m_preloadMapData = preload;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("PreloadMapData"_L1, preload);

    Q_EMIT preloadMapDataChanged(preload);
}

Settings::StartPage Settings::startPage() const
{
    return m_startPage;
}

void Settings::setStartPage(StartPage startPage)
{
    if (m_startPage == startPage) {
        return;
    }

    m_startPage = startPage;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("StartPage"_L1, static_cast<int>(startPage));

    Q_EMIT startPageChanged(startPage);
}

bool Settings::localTransportOnly() const
{
    return m_localTransportOnly;
}

void Settings::setLocalTransportOnly(bool localOnly)
{
    if (m_localTransportOnly == localOnly) {
        return;
    }

    m_localTransportOnly = localOnly;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("LocalTransportOnly"_L1, localOnly);

    Q_EMIT localTransportOnlyChanged(localOnly);
}

bool Settings::rentalBikes() const
{
    return m_rentalBikes;
}

void Settings::setRentalBikes(bool rentalBikes)
{
    if (m_rentalBikes == rentalBikes) {
        return;
    }

    m_rentalBikes = rentalBikes;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("RentalBikes"_L1, rentalBikes);

    Q_EMIT rentalBikesChanged(rentalBikes);
}

bool Settings::includeFlights() const
{
    return m_includeFlights;
}

void Settings::setIncludeFlights(bool includeFlights)
{
    if (m_includeFlights == includeFlights) {
        return;
    }

    m_includeFlights = includeFlights;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("IncludeFlights"_L1, includeFlights);

    Q_EMIT includeFlightsChanged(includeFlights);
}

bool Settings::journeyResultsAsTimeline() const
{
    return m_journeyResultsAsTimeline;
}

void Settings::setJourneyResultsAsTimeline(bool asTimeline)
{
    if (m_journeyResultsAsTimeline == asTimeline) {
        return;
    }

    m_journeyResultsAsTimeline = asTimeline;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("JourneyResultsAsTimeline"_L1, asTimeline);

    Q_EMIT journeyResultsAsTimelineChanged(asTimeline);
}

bool Settings::welcomePageShown() const
{
    return m_welcomePageShown;
}

void Settings::setWelcomePageShown(bool shown)
{
    if (m_welcomePageShown == shown) {
        return;
    }

    m_welcomePageShown = shown;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("WelcomePageShown"_L1, shown);

    Q_EMIT welcomePageShownChanged(shown);
}

QString Settings::ticketViewImage(const QString &passTypeIdentifier) const
{
    QSettings s;
    s.beginGroup("TicketViewImage"_L1);
    return s.value(passTypeIdentifier).toString();
}

void Settings::setTicketViewImage(const QString &passTypeIdentifier, const QString &assetName)
{
    QSettings s;
    s.beginGroup("TicketViewImage"_L1);
    s.setValue(passTypeIdentifier, assetName);
}

bool Settings::performCurrencyConversion() const
{
    return m_currencyConversion;
}

void Settings::setPerformCurrencyConversion(bool enable)
{
    if (m_currencyConversion == enable) {
        return;
    }

    m_currencyConversion = enable;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("PerformCurrencyConversion"_L1, enable);

    Q_EMIT performCurrencyConversionChanged(enable);
}

bool Settings::wikimediaOnlineContentEnabled() const
{
    return m_wikimediaOnlineContentEnabled;
}

void Settings::setWikimediaOnlineContentEnabled(bool enable)
{
    if (m_wikimediaOnlineContentEnabled == enable) {
        return;
    }

    m_wikimediaOnlineContentEnabled = enable;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("WikimediaOnlineContent"_L1, m_wikimediaOnlineContentEnabled);
    Q_EMIT wikimediaOnlineContentEnabledChanged(enable);
}

bool Settings::autoAddTransfers() const
{
    return m_autoAddTransfers;
}

void Settings::setAutoAddTransfers(bool autoAdd)
{
    if (!autoAdd) {
        setAutoFillTransfers(false);
    }

    if (m_autoAddTransfers == autoAdd) {
        return;
    }

    m_autoAddTransfers = autoAdd;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("AutoAddTransfers"_L1, autoAdd);

    Q_EMIT autoAddTransfersChanged(autoAdd);
}

bool Settings::autoFillTransfers() const
{
    return m_autoFillTransfers && m_queryLiveData && m_autoAddTransfers;
}

void Settings::setAutoFillTransfers(bool autoFill)
{
    if (m_autoFillTransfers == autoFill) {
        return;
    }

    m_autoFillTransfers = autoFill;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("AutoFillTransfers"_L1, autoFill);

    Q_EMIT autoFillTransfersChanged(autoFill);
}

bool Settings::showNotificationOnLockScreen() const
{
    return m_showNotificationOnLockScreen;
}

void Settings::setShowNotificationOnLockScreen(bool enabled)
{
    if (m_showNotificationOnLockScreen == enabled) {
        return;
    }

    m_showNotificationOnLockScreen = enabled;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("ShowNotificationOnLockScreen"_L1, m_showNotificationOnLockScreen);

    Q_EMIT showNotificationOnLockScreenChanged(m_showNotificationOnLockScreen);
}

void Settings::setOsmContributorMode(bool enabled)
{
    if (m_osmContributorMode == enabled) {
        return;
    }

    m_osmContributorMode = enabled;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("OsmContributorMode"_L1, m_osmContributorMode);

    Q_EMIT osmContributorModeChanged(m_osmContributorMode);
}

bool Settings::developmentMode() const
{
    return m_developmentMode;
}

void Settings::setDevelopmentMode(bool enabled)
{
    if (m_developmentMode == enabled) {
        return;
    }

    m_developmentMode = enabled;
    QSettings s;
    s.beginGroup("Settings"_L1);
    s.setValue("DevelopmentMode"_L1, m_developmentMode);
    Q_EMIT developmentModeChanged(m_developmentMode);
}

bool Settings::useFahrenheit() const
{
    return m_homeCountry == "US"_L1 && !m_forceMetricUnits;
}

KFormat::DistanceFormatOptions Settings::distanceFormat() const
{
    if (QLocale().measurementSystem() != QLocale::MetricSystem && m_forceMetricUnits) {
        return KFormat::MetricDistanceUnits;
    }
    return KFormat::LocaleDistanceUnits;
}

bool Settings::imperialDistances() const
{
    return QLocale().measurementSystem() != QLocale::MetricSystem && !m_forceMetricUnits;
}

#include "moc_settings.cpp"
