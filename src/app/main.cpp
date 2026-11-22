/*
    SPDX-FileCopyrightText: 2018 Volker Krause <vkrause@kde.org>
    SPDX-FileCopyrightText: 2025 Carl Schwan <carl@carlschwan.eu>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#include "config-itinerary.h"
#include "itinerary_version.h"
#include "logging.h"

#include "applicationcontroller.h"
#include "developmentmodecontroller.h"
#include "documentmanager.h"
#include "documentsmodel.h"
#include "factory.h"
#include "favoritelocationmodel.h"
#include "genericpkpass.h"
#include "healthcertificatemanager.h"
#include "importcontroller.h"
#include "intenthandler.h"
#include "livedatamanager.h"
#include "localizer.h"
#include "mapdownloadmanager.h"
#include "matrixcontroller.h"
#include "migrator.h"
#include "navigationcontroller.h"
#include "notificationconfigcontroller.h"
#include "markedroutecontroller.h"
#include "onlineticketimporter.h"
#include "passmanager.h"
#include "pkpassimageprovider.h"
#include "pkpassmanager.h"
#include "publictransport.h"
#include "qmlsingletons.h"
#include "reservationhelper.h"
#include "reservationmanager.h"
#include "reservationonlinepostprocessor.h"
#include "scamwarningmanager.h"
#include "settings.h"
#include "statisticsmodel.h"
#include "statisticstimerangemodel.h"
#include "tickettokenmodel.h"
#include "timelinedelegatecontroller.h"
#include "timelinemodel.h"
#include "timelinesectiondelegatecontroller.h"
#include "traewellingcontroller.h"
#include "transfermanager.h"
#include "tripgroupmanager.h"
#include "tripgroupmodel.h"
#include "tripgroupsplitmodel.h"
#include "unitconversion.h"
#include "util.h"
#include "weatherforecastmodel.h"

#include "weatherforecastmanager.h"

#include <KItinerary/CountryDb>
#include <KItinerary/DocumentUtil>
#include <KItinerary/JsonLdDocument>
#include <KItinerary/PriceUtil>
#include <KItinerary/Ticket>

#include <KPkPass/Barcode>
#include <KPkPass/BoardingPass>
#include <KPkPass/Field>

#if defined(Q_OS_ANDROID) || defined(Q_OS_IOS)
#include <KColorSchemeManager>
#else
#include <KDBusService>
#include <KWindowSystem>
#endif

#include <KLocalizedQmlContext>
#include <KLocalizedString>

#include <KAboutData>
#if HAVE_KCRASH
#include <KCrash>
#endif

#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

#ifdef Q_OS_ANDROID
#include "kandroidextras/activity.h"
#include "kandroidextras/intent.h"
#elif !defined(Q_OS_IOS)
#include <QApplication>
#endif

#include <QCommandLineParser>
#include <QDebug>
#include <QDesktopServices>
#include <QDir>
#include <QGuiApplication>
#include <QIcon>
#include <QNetworkAccessManager>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QWindow>

#ifdef Q_OS_IOS
#include <QLocale>
#include <QTranslator>
#endif

#if HAVE_MAPLIBRE
#include <QMapLibre/Utils>
#include <QVulkanInstance>
#include <QtQuick/QSGRendererInterface>
#endif

using namespace Qt::Literals::StringLiterals;

#ifdef Q_OS_IOS
// The Qt translations of the libraries (e.g. Kirigami's) are loaded by ECM's loaders, which the linker drops in
// a static build as nothing references them. Load the catalogs bundled with the app the same way instead.
static void loadBundledQtTranslations()
{
    const QDir localeDir(QCoreApplication::applicationDirPath() + "/locale"_L1);
    const auto load = [&localeDir](const QString &lang) {
        const QDir dir(localeDir.filePath(lang + "/LC_MESSAGES"_L1));
        const auto files = dir.entryList({u"*_qt.qm"_s}, QDir::Files);
        for (const auto &file : files) {
            auto translator = new QTranslator(QCoreApplication::instance());
            if (translator->load(dir.filePath(file))) {
                QCoreApplication::installTranslator(translator);
            } else {
                delete translator;
            }
        }
        return !files.isEmpty();
    };

    // the English catalogs contain the plural forms, the ones loaded later take precedence
    load(u"en"_s);
    // LANGUAGE takes precedence, as for KI18n
    auto langs = qEnvironmentVariable("LANGUAGE").split(u':', Qt::SkipEmptyParts);
    if (langs.isEmpty()) {
        langs = QLocale::system().uiLanguages(QLocale::TagSeparator::Underscore);
    }
    for (const auto &lang : std::as_const(langs)) {
        const auto generic = lang.section(u'_', 0, 0);
        if (generic == "en"_L1) {
            // e.g. British English, where translated
            if (lang != generic) {
                load(lang);
            }
            break;
        }
        if (load(lang) || (lang != generic && load(generic))) {
            break;
        }
    }
}
#endif

static void registerKItineraryTypes()
{
    qRegisterMetaType<KItinerary::KnowledgeDb::DrivingSide>();
    qmlRegisterUncreatableMetaObject(KItinerary::Ticket::staticMetaObject, "org.kde.kitinerary", 1, 0, "Ticket", {});
    qmlRegisterUncreatableMetaObject(KItinerary::KnowledgeDb::staticMetaObject, "org.kde.kitinerary", 1, 0, "KnowledgeDb", {});
    qmlRegisterSingletonType("org.kde.itinerary", 1, 0, "PriceUtil", [](QQmlEngine *, QJSEngine *engine) -> QJSValue {
        return engine->toScriptValue(KItinerary::PriceUtil());
    });
}

#define REGISTER_SINGLETON_GADGET_FACTORY(Class)                                                                                                               \
    qmlRegisterSingletonType("org.kde.itinerary", 1, 0, #Class, [](QQmlEngine *, QJSEngine *engine) -> QJSValue {                                              \
        return engine->toScriptValue(Class());                                                                                                                 \
    });

static void registerApplicationSingletons()
{
    REGISTER_SINGLETON_GADGET_FACTORY(DevelopmentModeController)
    REGISTER_SINGLETON_GADGET_FACTORY(Factory)
    REGISTER_SINGLETON_GADGET_FACTORY(Localizer)
    REGISTER_SINGLETON_GADGET_FACTORY(NavigationController)
    REGISTER_SINGLETON_GADGET_FACTORY(NotificationConfigController)
    REGISTER_SINGLETON_GADGET_FACTORY(PublicTransport)
    REGISTER_SINGLETON_GADGET_FACTORY(ReservationHelper)
    REGISTER_SINGLETON_GADGET_FACTORY(ScamWarningManager)
    REGISTER_SINGLETON_GADGET_FACTORY(UnitConversion)
    REGISTER_SINGLETON_GADGET_FACTORY(Util)
}

#undef REGISTER_SINGLETON_GADGET_FACTORY

static QNetworkAccessManager *namFactory()
{
    static QNetworkAccessManager *s_nam = nullptr;
    if (!s_nam) {
        s_nam = new QNetworkAccessManager(QCoreApplication::instance());
        s_nam->setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);
        s_nam->setStrictTransportSecurityEnabled(true);
        s_nam->enableStrictTransportSecurityStore(true, QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QLatin1StringView("/hsts/"));
    }
    return s_nam;
}

static void handleCommandLineArguments(ApplicationController *appController,
                                ImportController *importController,
                                const QStringList &args,
                                bool isTemporary,
                                const QString &page)
{
    for (const auto &file : args) {
        const auto localUrl = QUrl::fromLocalFile(file);
        if (QFile::exists(localUrl.toLocalFile())) {
            importController->importFromUrl(localUrl);
            if (isTemporary) {
                QFile::remove(localUrl.toLocalFile());
            }
        } else {
            const auto url = QUrl::fromUserInput(file);
            if (url.scheme() == "geo"_L1) {
                // User wants to go there
                appController->handleGeoUrl(url);
            } else {
                importController->importFromUrl(QUrl::fromUserInput(file));
            }
        }
    }

    if (!page.isEmpty()) {
        // the same as a page: URL, so properties can be given as query, e.g. "map?to=50.11,8.68"
        appController->handlePageUrl(QUrl(u"page:///"_s + page));
    }
}

#ifdef Q_OS_ANDROID
Q_DECL_EXPORT
#endif
int main(int argc, char **argv)
{
#if HAVE_MAPLIBRE
    const QMapLibre::RendererType rendererType = QMapLibre::supportedRendererType();
    auto graphicsApi = static_cast<QSGRendererInterface::GraphicsApi>(rendererType);
    QQuickWindow::setGraphicsApi(graphicsApi);
#endif

    QCoreApplication::setApplicationName(QStringLiteral("itinerary"));
    QCoreApplication::setOrganizationName(QStringLiteral("KDE"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("kde.org"));
    QCoreApplication::setApplicationVersion(QStringLiteral(ITINERARY_VERSION_STRING));
#if defined(Q_OS_ANDROID) || defined(Q_OS_IOS)
    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle(QStringLiteral("org.kde.breeze"));
    KColorSchemeManager::instance(); // enables automatic dark mode handling
#ifdef Q_OS_IOS
    loadBundledQtTranslations();
#endif
#else
    QIcon::setFallbackThemeName(QStringLiteral("breeze"));
    QApplication app(argc, argv); // for native file dialogs

    // Default to org.kde.desktop style unless the user forces another style
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    }
#endif
    QGuiApplication::setApplicationDisplayName(u"Trinity"_s);
    QGuiApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("org.kde.itinerary")));

    auto aboutData = KAboutData::applicationData();
    aboutData.setBugAddress("https://github.com/jblechert/trinity/issues");
    aboutData.setLicense(KAboutLicense::LGPL_V2, KAboutLicense::OrLaterVersions);
    aboutData.setHomepage(QStringLiteral("https://github.com/jblechert/trinity"));
    aboutData.setShortDescription(i18nc("@info", "Tickets, connections and maps in one app, based on KDE Itinerary"));
    aboutData.setCopyrightStatement(i18n("Copyright © The KDE Community"));
    aboutData.setDesktopFileName(QStringLiteral("org.kde.itinerary"));

    aboutData.addComponent(i18nc("@info:credit", "KDE Itinerary"), i18nc("@info:credit", "The digital travel assistant by the KDE Community, which Trinity is based on."), {}, u"https://apps.kde.org/itinerary"_s, KAboutLicense::LGPL_V2);
    aboutData.addComponent(i18nc("@info:credit", "Wikidata"), i18nc("@info:credit", "Provides various metadata like train station names, driving side, and power plug types."), {}, u"https://www.wikidata.org/"_s, KAboutLicense::CC0_V1);
    aboutData.addComponent(i18nc("@info:credit", "OpenStreetMap"), i18nc("@info:credit", "Provides both indoor and outdoor maps. ©OpenStreetMap contributors"), {}, u"https://www.openstreetmap.org/"_s, KAboutLicense::ODbL_V1);
    aboutData.addComponent(i18nc("@info:credit", "OpenSSL"), i18nc("@info:credit", "Secure network interaction with TLS. © 1998-2018 The OpenSSL Project"), {}, u"https://www.openssl.org/"_s, KAboutLicense::Apache_V2);
    aboutData.addComponent(i18nc("@info:credit", "ZXing"), i18nc("@info:credit", "QR-Code scanning. © 2016 ZXing Authors, © 2016 Nu-book Inc."), {}, u"https://github.com/nu-book/zxing-cpp"_s, KAboutLicense::Apache_V2);
#ifndef Q_OS_IOS // built without Poppler on iOS
    aboutData.addComponent(i18nc("@info:credit", "Poppler"), i18nc("@info:credit", "PDF parsing"), {}, u"https://poppler.freedesktop.org/"_s, KAboutLicense::GPL_V2);
#endif

#if HAVE_MAPLIBRE
    aboutData.addComponent(i18nc("@info:credit", "MapLibre Native Qt"), i18nc("@info:credit", "Copyright © MapLibre contributors."), {}, u"https://github.com/maplibre/maplibre-native-qt"_s, KAboutLicense::LGPL_V3);
    aboutData.addComponent(i18nc("@info:credit", "MapLibre Native"), i18nc("@info:credit", "Copyright © MapLibre contributors."), {}, u"https://www.maplibre.org/"_s, KAboutLicense::BSD_2_Clause);
#endif

#ifdef Q_OS_ANDROID
    aboutData.addComponent(i18nc("@info:credit", "FreeType"), i18nc("@info:credit", "Copyright (C) 2006-2020 by David Turner, Robert Wilhelm, and Werner Lemberg."), {}, u"https://www.freetype.org/"_s, KAboutLicense::FTL);
#endif
#if defined(Q_OS_ANDROID) || defined(Q_OS_IOS)
    aboutData.addComponent(i18nc("@info:credit", "libintl lite"), i18nc("@info:credit", "Internalisation"), {}, u"https://github.com/j-jorge/libintl-lite"_s, KAboutLicense::BSL_V1);
#endif

    aboutData.addComponent(i18nc("@info:credit", "libqrencode"), i18nc("@info:credit", "QR-Code Generation. © 2006-2018 Kentaro Fukuchi"), {}, u"https://github.com/fukuchi/libqrencode"_s, KAboutLicense::LGPL_V2_1);
    aboutData.addComponent(i18nc("@info:credit", "libical"), i18nc("@info:credit", "© The libical developers"), {}, u"https://github.com/libical/libical"_s, KAboutLicense::LGPL_V2_1);
    aboutData.addComponent(i18nc("@info:credit", "libxml2"), i18nc("@info:credit", "Copyright (C) 1998-2012 Daniel Veillard"), {}, u"https://gitlab.gnome.org/GNOME/libxml2/-/wikis/home"_s, KAboutLicense::MIT);

#if HAVE_MATRIX
    aboutData.addComponent(i18nc("@info:credit", "libQuotient"), i18nc("@info:credit", "Matrix integration."), {}, u"https://github.com/quotient-im/libquotient"_s, KAboutLicense::LGPL_V2_1);
    aboutData.addComponent(i18nc("@info:credit", "QtKeychain"), i18nc("@info:credit", "Secure password storage."), {}, u"https://github.com/frankosterfeld/qtkeychain/"_s, KAboutLicense::BSD_3_Clause);
    aboutData.addComponent(i18nc("@info:credit", "Olm"), i18nc("@info:credit", "Matrix crypto library."), {}, u"https://gitlab.matrix.org/matrix-org/olm"_s, KAboutLicense::Apache_V2);
#endif

    KAboutData::setApplicationData(aboutData);

    QCommandLineParser parser;
    QCommandLineOption isTemporaryOpt(QStringLiteral("tempfile"), QStringLiteral("Input file is a temporary file and will be deleted after importing."));
    parser.addOption(isTemporaryOpt);
    QCommandLineOption pageOpt(QStringLiteral("page"), i18nc("@info:shell", "Open Itinerary on the given page"), QStringLiteral("page"));
    parser.addOption(pageOpt);
    QCommandLineOption selfTestOpt(QStringLiteral("self-test"), QStringLiteral("internal, for automated testing"));
    selfTestOpt.setFlags(QCommandLineOption::HiddenFromHelp);
    parser.addOption(selfTestOpt);
    aboutData.setupCommandLine(&parser);
    parser.addPositionalArgument(QStringLiteral("file"), i18nc("@info:shell", "Files or URLs to import."));
    parser.process(app);
    aboutData.processCommandLine(&parser);
#if HAVE_KCRASH
    KCrash::initialize();
#endif

#if !defined(Q_OS_ANDROID) && !defined(Q_OS_IOS) && !defined(Q_OS_HAIKU)
    KDBusService service(KDBusService::Unique);
#endif

    Migrator::run();

    IntentHandler intentHandler;

    Settings settings;
    SettingsInstance::instance = &settings;

    PkPassManager pkPassMgr;
    pkPassMgr.setNetworkAccessManagerFactory(namFactory);
    PkPassManagerInstance::instance = &pkPassMgr;

    ReservationManager resMgr;
    ReservationManagerInstance::instance = &resMgr;

    DocumentManager docMgr;
    DocumentManagerInstance::instance = &docMgr;

    FavoriteLocationModel favLocModel;
    FavoriteLocationModelInstance::instance = &favLocModel;

    TicketValidityManager ticketValidityMgr;
    TicketValidityManagerInstance::instance = &ticketValidityMgr;

    JourneyRequestHistoryModel journeyRequestHistoryModel;
    JourneyRequestHistoryModelInstance::instance = &journeyRequestHistoryModel;

    TripGroupManager tripGroupMgr;
    tripGroupMgr.setReservationManager(&resMgr);
    TripGroupManagerInstance::instance = &tripGroupMgr;
    QObject::connect(&tripGroupMgr, &TripGroupManager::tripGroupRemoved, &ScamWarningManager::tripRemoved);

    LiveDataManager liveDataMgr;
    liveDataMgr.setPkPassManager(&pkPassMgr);
    liveDataMgr.setReservationManager(&resMgr);
    liveDataMgr.setPollingEnabled(settings.queryLiveData());
    liveDataMgr.setShowNotificationsOnLockScreen(settings.showNotificationOnLockScreen());
    liveDataMgr.setDownloadAssetsEnabled(settings.wikimediaOnlineContentEnabled());
    QObject::connect(&settings, &Settings::queryLiveDataChanged, &liveDataMgr, &LiveDataManager::setPollingEnabled);
    QObject::connect(&settings, &Settings::showNotificationOnLockScreenChanged, &liveDataMgr, &LiveDataManager::setShowNotificationsOnLockScreen);
    QObject::connect(&settings, &Settings::wikimediaOnlineContentEnabledChanged, &liveDataMgr, &LiveDataManager::setDownloadAssetsEnabled);
    LiveDataManagerInstance::instance = &liveDataMgr;

    ReservationOnlinePostprocessor resOnlinePostproc(&resMgr, &settings, namFactory);

    WeatherForecastManager::setAllowNetworkAccess(settings.weatherForecastEnabled());
    QObject::connect(&settings, &Settings::weatherForecastEnabledChanged, &WeatherForecastManager::setAllowNetworkAccess);

    TransferManager transferManager;
    transferManager.setReservationManager(&resMgr);
    transferManager.setFavoriteLocationModel(&favLocModel);
    transferManager.setLiveDataManager(&liveDataMgr);
    transferManager.setAutoAddTransfers(settings.autoAddTransfers());
    transferManager.setAutoFillTransfers(settings.autoFillTransfers());
    transferManager.setDownloadAssetsEnabled(settings.wikimediaOnlineContentEnabled());
    QObject::connect(&settings, &Settings::autoAddTransfersChanged, &transferManager, &TransferManager::setAutoAddTransfers);
    QObject::connect(&settings, &Settings::autoFillTransfersChanged, &transferManager, &TransferManager::setAutoFillTransfers);
    QObject::connect(&settings, &Settings::wikimediaOnlineContentEnabledChanged, &transferManager, &TransferManager::setDownloadAssetsEnabled);
    TransferManagerInstance::instance = &transferManager;

    tripGroupMgr.setTransferManager(&transferManager);

    TripGroupModel tripGroupModel;
    tripGroupModel.setTripGroupManager(&tripGroupMgr);
    TripGroupModelInstance::instance = &tripGroupModel;

    MapDownloadManager mapDownloadMgr;
    mapDownloadMgr.setReservationManager(&resMgr);
    mapDownloadMgr.setAutomaticDownloadEnabled(settings.preloadMapData());
    QObject::connect(&settings, &Settings::preloadMapDataChanged, &mapDownloadMgr, &MapDownloadManager::setAutomaticDownloadEnabled);
    MapDownloadManagerInstance::instance = &mapDownloadMgr;

    KItinerary::JsonLdDocument::registerType<GenericPkPass>();
    PassManager passMgr;
    PassManagerInstance::instance = &passMgr;

    ImportController importController;
    importController.setNetworkAccessManagerFactory(namFactory);
    importController.setReservationManager(&resMgr);
    QObject::connect(&intentHandler, &IntentHandler::handleIntent, &importController, &ImportController::importFromIntent);
    ImportControllerInstance::instance = &importController;
#ifdef Q_OS_IOS
    // files opened with the app from other apps (e.g. the share sheet) are passed on as file URLs to open
    QDesktopServices::setUrlHandler(u"file"_s, &importController, "importFromUrl");
#endif

    TraewellingController traewellingController(namFactory);
    TraewellingControllerInstance::instance = &traewellingController;

    ApplicationController appController;
    appController.setNetworkAccessManagerFactory(namFactory);
    appController.setReservationManager(&resMgr);
    appController.setPkPassManager(&pkPassMgr);
    appController.setDocumentManager(&docMgr);
    appController.setFavoriteLocationModel(&favLocModel);
    appController.setTransferManager(&transferManager);
    appController.setLiveDataManager(&liveDataMgr);
    appController.setTripGroupManager(&tripGroupMgr);
    appController.setPassManager(&passMgr);
    appController.setContextTripGroupId(tripGroupModel.currentTripGroupId());
#if !defined(Q_OS_ANDROID) && !defined(Q_OS_IOS) && !defined(Q_OS_HAIKU)
    QObject::connect(&service, &KDBusService::activateRequested, [&](const QStringList &args, const QString &workingDir) {
        qCDebug(Log) << "remote activation" << args << workingDir;
        if (!args.isEmpty()) {
            QDir::setCurrent(workingDir);
            parser.parse(args);
            handleCommandLineArguments(&appController, &importController, parser.positionalArguments(), parser.isSet(isTemporaryOpt), parser.value(pageOpt));
        }
        if (!QGuiApplication::allWindows().isEmpty()) {
            QWindow *window = QGuiApplication::allWindows().at(0);
            KWindowSystem::updateStartupId(window);
            KWindowSystem::activateWindow(window);
        }
    });
#endif
    QObject::connect(&intentHandler, &IntentHandler::handleIntent, &appController, &ApplicationController::handleIntent);
    QObject::connect(&importController, &ImportController::infoMessage, &appController, &ApplicationController::infoMessage);
    QObject::connect(&appController, &ApplicationController::reloadSettings, &settings, &Settings::reloadSettings);

    OnlineTicketImporter::setNetworkAccessManagerFactory(namFactory);
    MarkedRouteController::setNetworkAccessManagerFactory(namFactory);

    MatrixController matrixController;
    MatrixControllerInstance::instance = &matrixController;

    registerKItineraryTypes();
    registerApplicationSingletons();

    QQmlApplicationEngine engine;

    auto pkPassImageProvider = new PkPassImageProvider;
    pkPassImageProvider->registerPassProvider([&pkPassMgr](const QString &passTypeId, const QString &serialNum) -> KPkPass::Pass * {
        return pkPassMgr.pass(passTypeId + '/'_L1 + QString::fromUtf8(serialNum.toUtf8().toBase64(QByteArray::Base64UrlEncoding)));
    });
    pkPassImageProvider->registerPassProvider([&importController](const QString &passTypeId, const QString &serialNum) -> KPkPass::Pass * {
        if (const auto it = importController.pkPasses().find(KItinerary::DocumentUtil::idForPkPass(passTypeId, serialNum));
            it != importController.pkPasses().end()) {
            if (!(*it).second.pass) {
                (*it).second.pass.reset(KPkPass::Pass::fromData((*it).second.data));
            }
            return (*it).second.pass.get();
        }
        return nullptr;
    });
    engine.addImageProvider(u"org.kde.pkpass"_s, pkPassImageProvider);

    KLocalization::setupLocalizedContext(&engine);
    engine.loadFromModule("org.kde.itinerary", "Main");

    // Exit on QML load error.
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }

#if HAVE_MAPLIBRE
    engine.rootObjects().front()->setProperty("hasMapLibre", true);
#else
    engine.rootObjects().front()->setProperty("hasMapLibre", false);
#endif

    handleCommandLineArguments(&appController, &importController, parser.positionalArguments(), parser.isSet(isTemporaryOpt), parser.value(pageOpt));

#ifdef Q_OS_ANDROID
    using namespace KAndroidExtras;
    intentHandler.handleIntent(Activity::getIntent());
#endif

    if (parser.isSet(selfTestOpt)) {
        QTimer::singleShot(std::chrono::milliseconds(250), &app, &QCoreApplication::quit);
    }

    return app.exec();
}
