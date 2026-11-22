/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#include "walkingnavigationcontroller.h"

#include "config-itinerary.h"
#include "logging.h"

#include <KLocalizedString>

#include <KPublicTransport/IndividualTransport>

#include <algorithm>
#include <cmath>
#include <limits>

#ifdef Q_OS_ANDROID
#include <QCoreApplication>
#include <QJniObject>
#endif

using namespace Qt::Literals;

constexpr inline int OffRouteUpdates = 3; // consecutive position updates
constexpr inline int RerouteIntervalSecs = 20;
constexpr inline double EarthRadius = 6371000.0;

static double toRadians(double degrees)
{
    return degrees * M_PI / 180.0;
}

static double haversineDistance(double lat1, double lon1, double lat2, double lon2)
{
    const auto dLat = toRadians(lat2 - lat1);
    const auto dLon = toRadians(lon2 - lon1);
    const auto a = std::sin(dLat / 2) * std::sin(dLat / 2) + std::cos(toRadians(lat1)) * std::cos(toRadians(lat2)) * std::sin(dLon / 2) * std::sin(dLon / 2);
    return 2.0 * EarthRadius * std::atan2(std::sqrt(a), std::sqrt(1.0 - a));
}

WalkingNavigationController::WalkingNavigationController(QObject *parent)
    : QObject(parent)
{
}

WalkingNavigationController::~WalkingNavigationController()
{
    stopNotification();
}

KPublicTransport::Path WalkingNavigationController::path() const
{
    return m_path;
}

void WalkingNavigationController::setPath(const KPublicTransport::Path &path)
{
    m_path = path;
    m_offRoute = false;
    m_offRouteCount = 0;
    m_announcedSection = -1;
    m_announcedNowSection = -1;
    m_currentSection = -1;
    m_beenOnRoute = false;
    m_approachDistance = 0.0;
    m_measureApproach = !path.isEmpty();
    rebuildGeometry();
    Q_EMIT pathChanged();
    Q_EMIT progressChanged();
}

int WalkingNavigationController::travelMode() const
{
    return m_travelMode;
}

void WalkingNavigationController::setTravelMode(int mode)
{
    if (m_travelMode == mode) {
        return;
    }
    m_travelMode = mode;
    Q_EMIT travelModeChanged();
}

WalkingNavigationController::Thresholds WalkingNavigationController::thresholds() const
{
    // similar to what Organic Maps and OsmAnd use; faster travel needs earlier announcements and more tolerance
    switch (m_travelMode) {
    case KPublicTransport::IndividualTransport::Bike:
        return {.announceAhead = 80.0, .announceNow = 15.0, .arrival = 20.0, .offRoute = 35.0, .backOnRoute = 20.0};
    case KPublicTransport::IndividualTransport::Car:
        return {.announceAhead = 300.0, .announceNow = 40.0, .arrival = 40.0, .offRoute = 50.0, .backOnRoute = 30.0};
    default:
        return {.announceAhead = 40.0, .announceNow = 10.0, .arrival = 15.0, .offRoute = 35.0, .backOnRoute = 20.0};
    }
}

KPublicTransport::Path WalkingNavigationController::trail() const
{
    return m_trail;
}

void WalkingNavigationController::setTrail(const KPublicTransport::Path &trail)
{
    m_trail = trail;
    m_rejoinSection = 0;
    m_rejoinSegment = 0;
    Q_EMIT trailChanged();
}

KPublicTransport::Location WalkingNavigationController::rejoinLocation(double latitude, double longitude)
{
    // project onto a local plane around the position, good enough for finding the closest point
    const auto lonScale = std::cos(toRadians(latitude));
    const auto project = [&](QPointF p) {
        return QPointF((p.x() - longitude) * lonScale, p.y() - latitude);
    };
    double best = std::numeric_limits<double>::max();
    const auto &sections = m_trail.sections();
    for (int s = 0; s < (int)sections.size(); ++s) {
        const auto points = sections[s].path();
        for (qsizetype i = 0; i + 1 < points.size(); ++i) {
            const auto a = project(points[i]);
            const auto b = project(points[i + 1]);
            const auto ab = b - a;
            const auto len2 = QPointF::dotProduct(ab, ab);
            const auto t = len2 > 0.0 ? std::clamp(QPointF::dotProduct(-a, ab) / len2, 0.0, 1.0) : 0.0;
            const auto c = a + t * ab;
            const auto d = QPointF::dotProduct(c, c);
            if (d < best) {
                best = d;
                m_rejoinSection = s;
                m_rejoinSegment = i;
                m_rejoinPoint = points[i] + t * (points[i + 1] - points[i]);
            }
        }
    }
    return locationAt(m_rejoinPoint.y(), m_rejoinPoint.x(), m_destination.name());
}

KPublicTransport::Path WalkingNavigationController::joinTrail(const KPublicTransport::Path &approach) const
{
    auto sections = approach.sections();
    const auto &trailSections = m_trail.sections();
    for (int s = m_rejoinSection; s < (int)trailSections.size(); ++s) {
        auto section = trailSections[s];
        if (s == m_rejoinSection) {
            auto points = section.path();
            points.remove(0, std::min(m_rejoinSegment + 1, points.size()));
            points.prepend(m_rejoinPoint);
            section.setPath(points);
        }
        sections.push_back(section);
    }
    KPublicTransport::Path path;
    path.setSections(std::move(sections));
    return path;
}

KPublicTransport::Location WalkingNavigationController::destination() const
{
    return m_destination;
}

void WalkingNavigationController::setDestination(const KPublicTransport::Location &destination)
{
    m_destination = destination;
    Q_EMIT destinationChanged();
}

void WalkingNavigationController::rebuildGeometry()
{
    m_points.clear();
    m_sectionStartDistance.clear();
    m_totalDistance = 0.0;

    for (const auto &section : m_path.sections()) {
        m_sectionStartDistance.push_back(m_totalDistance);
        for (const auto &p : section.path()) {
            // the polygons use x for the longitude and y for the latitude
            if (!m_points.empty()) {
                const auto &prev = m_points.back();
                const auto d = haversineDistance(prev.latitude, prev.longitude, p.y(), p.x());
                if (d < 0.01) {
                    continue; // section boundaries repeat the point
                }
                m_totalDistance += d;
            }
            m_points.push_back({p.y(), p.x(), m_totalDistance});
        }
    }
}

bool WalkingNavigationController::hasRoute() const
{
    return m_points.size() >= 2;
}

bool WalkingNavigationController::hasPosition() const
{
    return m_hasPosition;
}

// the instruction to follow a path section, such as "Turn left onto Bahnhofstraße"
static QString sectionInstruction(const KPublicTransport::PathSection &section)
{
#if HAVE_KPUBLICTRANSPORT_NAVIGATION_INSTRUCTIONS
    return section.instruction();
#else
    return section.description();
#endif
}

QString WalkingNavigationController::instruction() const
{
    if (!hasRoute()) {
        return {};
    }
    if (m_arrived) {
        return i18nc("@info walking navigation", "You have arrived at %1", m_destination.name());
    }
    const auto next = m_currentSection + 1;
    if (next >= 1 && next < (int)m_path.sections().size()) {
        const auto text = sectionInstruction(m_path.sections()[next]);
        if (!text.isEmpty()) {
            return text;
        }
        return i18nc("@info walking navigation", "Continue");
    }
    if (m_currentSection < 0 && !m_path.sections().empty()) {
        return sectionInstruction(m_path.sections().front());
    }
    switch (m_travelMode) {
    case KPublicTransport::IndividualTransport::Bike:
        return i18nc("@info navigation by bike, %1 is a place", "Cycle to %1", m_destination.name());
    case KPublicTransport::IndividualTransport::Car:
        return i18nc("@info navigation by car, %1 is a place", "Drive to %1", m_destination.name());
    default:
        return i18nc("@info walking navigation", "Walk to %1", m_destination.name());
    }
}

QString WalkingNavigationController::instructionIconName() const
{
    if (m_arrived || !hasRoute()) {
        return u"flag"_s;
    }
    const auto next = m_currentSection + 1;
    if (next >= 1 && next < (int)m_path.sections().size()) {
        const auto &section = m_path.sections()[next];
        // the icon of a plain move is a pedestrian, whatever the route is for
        if (section.maneuver() == KPublicTransport::PathSection::Move) {
            return KPublicTransport::IndividualTransport::modeIconName(static_cast<KPublicTransport::IndividualTransport::Mode>(m_travelMode));
        }
        return section.iconName();
    }
    return u"flag"_s;
}

double WalkingNavigationController::instructionTurnAngle() const
{
#if HAVE_KPUBLICTRANSPORT_NAVIGATION_INSTRUCTIONS
    const auto next = m_currentSection + 1;
    if (m_arrived || next < 1 || next >= (int)m_path.sections().size()) {
        return NAN;
    }
    const auto &section = m_path.sections()[next];
    if (section.maneuver() != KPublicTransport::PathSection::Move) {
        return NAN;
    }
    using KPublicTransport::PathSection;
    switch (section.turnDirection()) {
    case PathSection::Straight:
        return 0.0;
    case PathSection::SlightLeft:
        return -45.0;
    case PathSection::Left:
        return -90.0;
    case PathSection::SharpLeft:
        return -135.0;
    case PathSection::UTurnLeft:
        return -180.0;
    case PathSection::SlightRight:
        return 45.0;
    case PathSection::Right:
        return 90.0;
    case PathSection::SharpRight:
        return 135.0;
    case PathSection::UTurnRight:
        return 180.0;
    case PathSection::UnknownTurnDirection:
        break;
    }
#endif
    return NAN;
}

double WalkingNavigationController::distanceToInstruction() const
{
    const auto next = m_currentSection + 1;
    if (next >= 1 && next < (int)m_sectionStartDistance.size()) {
        return std::max(0.0, m_sectionStartDistance[next] - m_distanceAlong);
    }
    return distanceRemaining();
}

double WalkingNavigationController::distanceRemaining() const
{
    return std::max(0.0, m_totalDistance - m_distanceAlong);
}

bool WalkingNavigationController::offRoute() const
{
    return m_offRoute;
}

bool WalkingNavigationController::arrived() const
{
    return m_arrived;
}

void WalkingNavigationController::speak(const QString &text)
{
    if (m_speechEnabled && !text.isEmpty()) {
        m_speech.speak(text);
    }
}

void WalkingNavigationController::updatePosition(double latitude, double longitude, double accuracy)
{
    processPosition(latitude, longitude, accuracy);
    updateNotification();
}

void WalkingNavigationController::processPosition(double latitude, double longitude, double accuracy)
{
    const bool firstPosition = !m_hasPosition;
    m_hasPosition = true;

    if (!hasRoute()) {
        if (firstPosition || m_lastRerouteRequest.secsTo(QDateTime::currentDateTime()) >= RerouteIntervalSecs) {
            m_lastRerouteRequest = QDateTime::currentDateTime();
            Q_EMIT rerouteRequested(latitude, longitude);
        }
        Q_EMIT progressChanged();
        return;
    }

    // closest point on the path, using a local equirectangular projection around the current position
    const auto cosLat = std::cos(toRadians(latitude));
    const auto toX = [&](double lon) { return toRadians(lon - longitude) * cosLat * EarthRadius; };
    const auto toY = [&](double lat) { return toRadians(lat - latitude) * EarthRadius; };
    double bestDistance = std::numeric_limits<double>::max();
    double bestAlong = 0.0;
    for (std::size_t i = 0; i + 1 < m_points.size(); ++i) {
        const auto ax = toX(m_points[i].longitude), ay = toY(m_points[i].latitude);
        const auto bx = toX(m_points[i + 1].longitude), by = toY(m_points[i + 1].latitude);
        const auto dx = bx - ax, dy = by - ay;
        const auto lengthSquared = dx * dx + dy * dy;
        const auto t = lengthSquared > 0.0 ? std::clamp(-(ax * dx + ay * dy) / lengthSquared, 0.0, 1.0) : 0.0;
        const auto px = ax + t * dx, py = ay + t * dy;
        const auto distance = std::sqrt(px * px + py * py);
        if (distance < bestDistance) {
            bestDistance = distance;
            bestAlong = m_points[i].distance + t * (m_points[i + 1].distance - m_points[i].distance);
        }
    }

    // a route starts at the closest place it can be found from, e.g. the street next to a large square or a building,
    // so getting there is part of the way: until we have been on the route, only moving further away is leaving it
    if (m_measureApproach) {
        m_measureApproach = false;
        m_approachDistance = bestDistance;
    }
    if (m_beenOnRoute) {
        m_approachDistance = 0.0;
    }

    // off the route? GPS jitter is common, so require a few updates in a row, and consider the accuracy
    const auto limits = thresholds();
    const auto offRouteThreshold = std::max(limits.offRoute, 1.5 * accuracy) + m_approachDistance;
    if (bestDistance > offRouteThreshold) {
        ++m_offRouteCount;
    } else if (bestDistance < limits.backOnRoute) {
        m_offRouteCount = 0;
        m_offRoute = false;
        m_beenOnRoute = true;
    }
    if (m_offRouteCount >= OffRouteUpdates || (firstPosition && bestDistance > offRouteThreshold)) {
        if (!m_offRoute && !firstPosition && m_beenOnRoute) {
            speak(i18nc("@info:tts walking navigation", "You left the route, looking for a new one."));
        }
        m_offRoute = true;
        if (!m_lastRerouteRequest.isValid() || m_lastRerouteRequest.secsTo(QDateTime::currentDateTime()) >= RerouteIntervalSecs) {
            m_lastRerouteRequest = QDateTime::currentDateTime();
            Q_EMIT rerouteRequested(latitude, longitude);
        }
        Q_EMIT progressChanged();
        return;
    }

    // never move backwards along the path by more than GPS jitter, e.g. where the path passes the same place twice
    m_distanceAlong = bestAlong;
    int section = 0;
    for (std::size_t i = 0; i < m_sectionStartDistance.size(); ++i) {
        if (m_sectionStartDistance[i] <= m_distanceAlong + 0.5) {
            section = (int)i;
        }
    }
    m_currentSection = section;

    if (!m_announcedStart) {
        m_announcedStart = true;
        QString start;
        switch (m_travelMode) {
        case KPublicTransport::IndividualTransport::Bike:
            start = i18nc("@info:tts navigation by bike, %1 is the destination", "Cycling to %1.", m_destination.name());
            break;
        case KPublicTransport::IndividualTransport::Car:
            start = i18nc("@info:tts navigation by car, %1 is the destination", "Driving to %1.", m_destination.name());
            break;
        default:
            start = i18nc("@info:tts walking navigation, %1 is the destination", "Walking to %1.", m_destination.name());
            break;
        }
        const auto firstInstruction = sectionInstruction(m_path.sections().front());
        const bool sayInstruction = !firstInstruction.isEmpty() && firstInstruction != m_destination.name();
        speak(sayInstruction ? (start + QLatin1Char(' ') + firstInstruction) : start);
    }

    // announcements for the next maneuver
    if (!m_arrived && distanceRemaining() <= limits.arrival) {
        m_arrived = true;
        speak(i18nc("@info:tts walking navigation", "You have arrived at %1.", m_destination.name()));
    } else if (!m_arrived) {
        const auto next = m_currentSection + 1;
        const auto distance = distanceToInstruction();
        if (next < (int)m_path.sections().size()) {
            if (distance <= limits.announceNow && m_announcedNowSection != next) {
                m_announcedNowSection = next;
                m_announcedSection = next;
                speak(instruction());
            } else if (distance <= limits.announceAhead && distance > limits.announceNow && m_announcedSection != next) {
                m_announcedSection = next;
                speak(i18nc("@info:tts walking navigation, %1 is a distance, %2 an instruction", "In %1 meters: %2", (int)(std::round(distance / 5.0) * 5.0), instruction()));
            }
        }
    }

    Q_EMIT progressChanged();
}

void WalkingNavigationController::updateNotification()
{
    QString text;
    if (m_arrived) {
        text = instruction();
    } else if (m_offRoute || !hasRoute()) {
        text = i18nc("@info navigation notification", "Looking for a route…");
    } else {
        // round, so the notification isn't updated every second
        const auto distance = std::round(distanceToInstruction() / 10.0) * 10.0;
        text = i18nc("@info navigation notification, %1 is a distance in meters, %2 an instruction", "In %1 m: %2", (int)distance, instruction());
    }
    if (m_notificationShown && text == m_notificationText) {
        return;
    }
    m_notificationText = text;

#ifdef Q_OS_ANDROID
    const auto channelName = QJniObject::fromString(i18nc("@title notification channel", "Navigation"));
    const auto title = QJniObject::fromString(m_destination.name());
    const auto jtext = QJniObject::fromString(text);
    QJniObject::callStaticMethod<void>("org/kde/itinerary/NavigationService",
                                       m_notificationShown ? "update" : "start",
                                       "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V",
                                       QNativeInterface::QAndroidApplication::context().object(),
                                       channelName.object<jstring>(),
                                       title.object<jstring>(),
                                       jtext.object<jstring>());
#endif
    m_notificationShown = true;
}

void WalkingNavigationController::stopNotification()
{
    if (!m_notificationShown) {
        return;
    }
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>("org/kde/itinerary/NavigationService", "stop", "(Landroid/content/Context;)V", QNativeInterface::QAndroidApplication::context().object());
#endif
    m_notificationShown = false;
}

bool WalkingNavigationController::speechAvailable()
{
    return SpeechOutput::isAvailable();
}

void WalkingNavigationController::openSpeechSettings()
{
    SpeechOutput::openSettings();
}

void WalkingNavigationController::installSpeechEngine()
{
    // SherpaTTS: free, natural voices for many languages, working offline once a voice is downloaded
    SpeechOutput::installEngine(u"org.woheller69.ttsengine"_s);
}

bool WalkingNavigationController::speechVoiceMissing() const
{
    return m_speech.isLanguageMissing();
}

void WalkingNavigationController::installSpeechVoice()
{
    m_speech.installVoice();
}

KPublicTransport::JourneyRequest WalkingNavigationController::routeRequest(double latitude, double longitude, const KPublicTransport::Location &destination) const
{
    auto from = locationAt(latitude, longitude, i18nc("@info start of navigation", "Current location"));
    KPublicTransport::JourneyRequest req(from, destination);
    if (m_travelMode == KPublicTransport::IndividualTransport::Walk) {
        req.setModes(KPublicTransport::JourneySection::Walking);
    } else {
        req.setModes(KPublicTransport::JourneySection::IndividualTransport);
        req.setIndividualTransportModes({KPublicTransport::IndividualTransport(static_cast<KPublicTransport::IndividualTransport::Mode>(m_travelMode))});
    }
    req.setIncludePaths(true);
    req.setMaximumResults(1);
    req.setDownloadAssets(false);
    return req;
}

KPublicTransport::Path WalkingNavigationController::routePath(const KPublicTransport::Journey &journey)
{
    std::vector<KPublicTransport::PathSection> sections;
    for (const auto &section : journey.sections()) {
        if (section.mode() == KPublicTransport::JourneySection::PublicTransport) {
            break;
        }
        const auto pathSections = section.path().sections();
        sections.insert(sections.end(), pathSections.begin(), pathSections.end());
    }
    KPublicTransport::Path path;
    path.setSections(std::move(sections));
    return path;
}

KPublicTransport::Location WalkingNavigationController::locationAt(double latitude, double longitude, const QString &name)
{
    KPublicTransport::Location loc;
    loc.setCoordinate(latitude, longitude);
    loc.setName(name);
    return loc;
}

#include "moc_walkingnavigationcontroller.cpp"
