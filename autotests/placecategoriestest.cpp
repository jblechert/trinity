/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#include "placecategories.h"

#include <KLocalizedString>

#include <QStandardPaths>
#include <QtTest/qtest.h>

using namespace Qt::Literals;

class PlaceCategoriesTest : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
        KLocalizedString::setApplicationDomain("kde-itinerary");
    }

    void testNormalize_data()
    {
        QTest::addColumn<QString>("text");
        QTest::addColumn<QString>("normalized");

        QTest::newRow("empty") << QString() << QString();
        QTest::newRow("case") << u"Bakery"_s << u"bakery"_s;
        QTest::newRow("umlaut") << u"Bäckerei"_s << u"backerei"_s;
        QTest::newRow("umlaut transliterated") << u"Baeckerei"_s << u"backerei"_s;
        QTest::newRow("sharp s") << u"Imbiß"_s << u"imbiss"_s;
        QTest::newRow("accent") << u"Café"_s << u"cafe"_s;
        QTest::newRow("punctuation") << u"  Fast-Food?! "_s << u"fast food"_s;
        QTest::newRow("spaces") << u"Öffentliche   Toilette"_s << u"offentliche toilette"_s;
    }

    void testNormalize()
    {
        QFETCH(QString, text);
        QFETCH(QString, normalized);
        QCOMPARE(PlaceCategories::normalize(text), normalized);
    }

    void testMatch_data()
    {
        QTest::addColumn<QString>("text");
        QTest::addColumn<QString>("category");

        // names, in English and German
        QTest::newRow("bakery") << u"Bakery"_s << u"bakery"_s;
        QTest::newRow("Bäckerei") << u"Bäckerei"_s << u"bakery"_s;
        QTest::newRow("bäckerei lower case") << u"bäckerei"_s << u"bakery"_s;
        QTest::newRow("BÄCKEREI") << u"BÄCKEREI"_s << u"bakery"_s;
        QTest::newRow("Backerei") << u"Backerei"_s << u"bakery"_s;
        QTest::newRow("Baeckerei") << u"Baeckerei"_s << u"bakery"_s;
        QTest::newRow("Apotheke") << u"Apotheke"_s << u"pharmacy"_s;
        QTest::newRow("Supermarkt") << u"Supermarkt"_s << u"supermarket"_s;
        QTest::newRow("Tankstelle") << u"Tankstelle"_s << u"fuel"_s;
        QTest::newRow("Geldautomat") << u"Geldautomat"_s << u"atm"_s;
        QTest::newRow("ATM") << u"ATM"_s << u"atm"_s;
        QTest::newRow("Restaurant") << u"Restaurant"_s << u"restaurant"_s;
        QTest::newRow("Café") << u"Café"_s << u"cafe"_s;
        QTest::newRow("Cafe") << u"Cafe"_s << u"cafe"_s;
        QTest::newRow("Post") << u"Post"_s << u"post_office"_s;
        QTest::newRow("Paketstation") << u"Paketstation"_s << u"parcel_locker"_s;
        QTest::newRow("Wertstoffhof") << u"Wertstoffhof"_s << u"recycling"_s;

        // plurals
        QTest::newRow("Bäckereien") << u"Bäckereien"_s << u"bakery"_s;
        QTest::newRow("bakeries") << u"bakeries"_s << u"bakery"_s;
        QTest::newRow("Apotheken") << u"Apotheken"_s << u"pharmacy"_s;
        QTest::newRow("pharmacies") << u"pharmacies"_s << u"pharmacy"_s;
        QTest::newRow("Supermärkte") << u"Supermärkte"_s << u"supermarket"_s;
        QTest::newRow("Tankstellen") << u"Tankstellen"_s << u"fuel"_s;
        QTest::newRow("Geldautomaten") << u"Geldautomaten"_s << u"atm"_s;
        QTest::newRow("ATMs") << u"ATMs"_s << u"atm"_s;
        QTest::newRow("Restaurants") << u"Restaurants"_s << u"restaurant"_s;
        QTest::newRow("Cafés") << u"Cafés"_s << u"cafe"_s;
        QTest::newRow("Ärzte") << u"Ärzte"_s << u"doctors"_s;
        QTest::newRow("Museen") << u"Museen"_s << u"museum"_s;
        QTest::newRow("Toiletten") << u"Toiletten"_s << u"toilets"_s;
        QTest::newRow("Metzgereien") << u"Metzgereien"_s << u"butcher"_s;
        QTest::newRow("bars") << u"bars"_s << u"bar"_s;

        // synonyms
        QTest::newRow("Bäcker") << u"Bäcker"_s << u"bakery"_s;
        QTest::newRow("Metzger") << u"Metzger"_s << u"butcher"_s;
        QTest::newRow("Kneipe") << u"Kneipe"_s << u"bar"_s;
        QTest::newRow("pub") << u"pub"_s << u"bar"_s;
        QTest::newRow("Eisdiele") << u"Eisdiele"_s << u"ice_cream"_s;
        QTest::newRow("Imbiss") << u"Imbiss"_s << u"fast_food"_s;
        QTest::newRow("Imbiß") << u"Imbiß"_s << u"fast_food"_s;
        QTest::newRow("fast-food") << u"fast-food"_s << u"fast_food"_s;
        QTest::newRow("fastfood") << u"fastfood"_s << u"fast_food"_s;
        QTest::newRow("WC") << u"WC"_s << u"toilets"_s;
        QTest::newRow("gas station") << u"gas station"_s << u"fuel"_s;
        QTest::newRow("Packstation") << u"Packstation"_s << u"parcel_locker"_s;
        QTest::newRow("Ladesäule") << u"Ladesäule"_s << u"charging_station"_s;
        QTest::newRow("E-Tankstelle") << u"E-Tankstelle"_s << u"charging_station"_s;
        QTest::newRow("Krankenhaus") << u"Krankenhaus"_s << u"hospital"_s;
        QTest::newRow("Zahnarzt") << u"Zahnarzt"_s << u"dentist"_s;
        QTest::newRow("Jugendherberge") << u"Jugendherberge"_s << u"hotel"_s;
        QTest::newRow("Campingplatz") << u"Campingplatz"_s << u"camping"_s;
        QTest::newRow("Spielplatz") << u"Spielplatz"_s << u"playground"_s;
        QTest::newRow("Polizei") << u"Polizei"_s << u"police"_s;
        QTest::newRow("Fahrradverleih") << u"Fahrradverleih"_s << u"bicycle_rental"_s;

        // phrases around the category
        QTest::newRow("nearest bakeries") << u"nearest bakeries"_s << u"bakery"_s;
        QTest::newRow("where is the nearest bakery?") << u"Where is the nearest bakery?"_s << u"bakery"_s;
        QTest::newRow("Apotheke in der Nähe") << u"Apotheke in der Nähe"_s << u"pharmacy"_s;
        QTest::newRow("Wo ist die nächste Tankstelle?") << u"Wo ist die nächste Tankstelle?"_s << u"fuel"_s;
        QTest::newRow("nächste Bäckereien") << u"nächste Bäckereien"_s << u"bakery"_s;

        // beginnings of names
        QTest::newRow("Bäck") << u"Bäck"_s << u"bakery"_s;
        QTest::newRow("Apo") << u"Apo"_s << u"pharmacy"_s;
        QTest::newRow("Superm") << u"Superm"_s << u"supermarket"_s;
        QTest::newRow("Tank") << u"Tank"_s << u"fuel"_s;
        QTest::newRow("Geldaut") << u"Geldaut"_s << u"atm"_s;

        // no category
        QTest::newRow("empty") << QString() << QString();
        QTest::newRow("only filler words") << u"in der Nähe"_s << QString();
        QTest::newRow("too short") << u"Ap"_s << QString();
        QTest::newRow("a name") << u"Pappert"_s << QString();
        QTest::newRow("a name with a category") << u"Bäckerei Pappert"_s << QString();
        QTest::newRow("Bären is no bar") << u"Bären"_s << QString();
        QTest::newRow("Burger King") << u"Burger King"_s << QString();
        QTest::newRow("Sparkasse") << u"Sparkasse"_s << QString();
    }

    void testMatch()
    {
        QFETCH(QString, text);
        QFETCH(QString, category);
        QCOMPARE(PlaceCategories::matchText(text), category);
        QCOMPARE(PlaceCategories::categoryForText(text).value(u"id"_s).toString(), category);
    }

    void testCategory()
    {
        const auto bakery = PlaceCategories::category(u"bakery"_s);
        QCOMPARE(bakery.value(u"name"_s).toString(), u"Bakery"_s);
        QCOMPARE(bakery.value(u"osmTags"_s).toStringList(), QStringList{u"shop=bakery"_s});
        QVERIFY(!bakery.value(u"iconSource"_s).toString().isEmpty());
        QCOMPARE(bakery.value(u"mostlyUnnamed"_s).toBool(), false);
        QCOMPARE(PlaceCategories::category(u"toilets"_s).value(u"mostlyUnnamed"_s).toBool(), true);

        QVERIFY(PlaceCategories::category(u"nonexistent"_s).isEmpty());
    }

    void testCategoryForTag()
    {
        QCOMPARE(PlaceCategories::categoryForTag(u"shop"_s, u"bakery"_s).value(u"id"_s).toString(), u"bakery"_s);
        QCOMPARE(PlaceCategories::categoryForTag(u"amenity"_s, u"pub"_s).value(u"id"_s).toString(), u"bar"_s);
        QCOMPARE(PlaceCategories::categoryForTag(u"tourism"_s, u"hostel"_s).value(u"id"_s).toString(), u"hotel"_s);
        QVERIFY(PlaceCategories::categoryForTag(u"shop"_s, u"florist"_s).isEmpty());
    }

    void testCatalogue()
    {
        // every category can be found by its own name, with tags in the form understood by KPublicTransport
        PlaceCategories categories;
        const auto all = categories.property("categories").toList();
        QVERIFY(all.size() >= 40);
        QStringList ids;
        for (const auto &v : all) {
            const auto c = v.toMap();
            const auto id = c.value(u"id"_s).toString();
            QVERIFY(!ids.contains(id));
            ids.push_back(id);
            QCOMPARE(PlaceCategories::matchText(c.value(u"name"_s).toString()), id);
            const auto tags = c.value(u"osmTags"_s).toStringList();
            QVERIFY(!tags.isEmpty());
            for (const auto &tag : tags) {
                QVERIFY2(tag.count('='_L1) == 1 && !tag.startsWith('='_L1) && !tag.endsWith('='_L1), qPrintable(tag));
                QCOMPARE(tag.trimmed(), tag);
            }
        }
    }
};

QTEST_GUILESS_MAIN(PlaceCategoriesTest)

#include "placecategoriestest.moc"
