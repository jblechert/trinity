/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#include "placecategories.h"

#include <KLazyLocalizedString>

#include <QFile>

#include <algorithm>
#include <vector>

using namespace Qt::Literals;

namespace
{
struct CategoryData {
    const char *id;
    KLazyLocalizedString name;
    // OSM tags as "key=value", separated by commas
    const char *osmTags;
    // icon file name from KOSMIndoorMap
    const char *icon;
    // other names of this category users might search for, in English and German, separated by commas
    const char *keywords;
};

// the most commonly needed categories first, these are also offered first for quick access
// clang-format off
static const CategoryData categoryData[] = {
    {"bakery", kli18nc("@item place category", "Bakery"), "shop=bakery", "bakery",
        "bakery,baker,bread,bäckerei,bäcker,backwaren,brot,brötchen,backshop"},
    {"supermarket", kli18nc("@item place category", "Supermarket"), "shop=supermarket", "supermarket",
        "supermarket,grocery,groceries,grocery store,food store,supermarkt,lebensmittel,lebensmittelmarkt,lebensmittelgeschäft,discounter"},
    {"pharmacy", kli18nc("@item place category", "Pharmacy"), "amenity=pharmacy", "pharmacy",
        "pharmacy,apotheke"},
    {"cafe", kli18nc("@item place category", "Café"), "amenity=cafe", "cafe",
        "cafe,coffee,coffee shop,coffeehouse,café,kaffee,kaffeehaus,konditorei"},
    {"restaurant", kli18nc("@item place category", "Restaurant"), "amenity=restaurant", "restaurant",
        "restaurant,dining,eatery,gaststätte,gasthaus,gasthof,wirtshaus,lokal,essen gehen"},
    {"fast_food", kli18nc("@item place category", "Fast Food"), "amenity=fast_food", "fast_food",
        "fast food,takeaway,take away,snack bar,burger,kebab,schnellimbiss,imbiss,imbissbude,döner,dönerladen,pommesbude"},
    {"atm", kli18nc("@item place category", "ATM"), "amenity=atm", "atm",
        "atm,cash machine,cashpoint,cash,geldautomat,bankautomat,bargeld,geld"},
    {"toilets", kli18nc("@item place category", "Toilets"), "amenity=toilets", "toilets",
        "toilet,public toilet,wc,loo,bathroom,washroom,toilette,öffentliche toilette,klo"},
    {"fuel", kli18nc("@item place category", "Fuel Station"), "amenity=fuel", "fuel",
        "fuel,gas station,petrol station,filling station,petrol,diesel,tankstelle,tanken,benzin"},
    {"charging_station", kli18nc("@item place category", "Charging Station"), "amenity=charging_station", "charging_station",
        "charging station,charging point,ev charger,charger,ladestation,ladesäule,ladepunkt,stromtankstelle,e tankstelle,elektrotankstelle"},
    {"parking", kli18nc("@item place category", "Parking"), "amenity=parking", "parking",
        "parking,car park,parking lot,parking garage,parkplatz,parkhaus,tiefgarage,parken"},
    {"hotel", kli18nc("@item place category", "Hotel"), "tourism=hotel,tourism=guest_house,tourism=hostel,tourism=motel", "hotel",
        "hotel,guest house,guesthouse,hostel,motel,bed and breakfast,accommodation,lodging,pension,gästehaus,jugendherberge,herberge,unterkunft,übernachtung,ferienwohnung"},
    {"bar", kli18nc("@item place category", "Bar or Pub"), "amenity=bar,amenity=pub,amenity=biergarten", "bar",
        "bar,pub,beer garden,tavern,kneipe,biergarten,schänke,gaststube,weinstube"},
    {"ice_cream", kli18nc("@item place category", "Ice Cream"), "amenity=ice_cream,shop=ice_cream", "ice_cream",
        "ice cream,ice cream parlor,gelato,gelateria,eis,eiscafé,eisdiele,eisladen"},
    {"kiosk", kli18nc("@item place category", "Kiosk"), "shop=kiosk,shop=newsagent", "newsagent",
        "kiosk,newsagent,newspapers,trinkhalle,büdchen,zeitschriften,zeitungen"},
    {"convenience", kli18nc("@item place category", "Convenience Store"), "shop=convenience", "convenience",
        "convenience store,corner shop,minimarket,späti,spätkauf,minimarkt,tante emma laden"},
    {"post_office", kli18nc("@item place category", "Post Office"), "amenity=post_office", "post_office",
        "post office,post,postamt,postfiliale,postagentur,postbank"},
    {"parcel_locker", kli18nc("@item place category", "Parcel Locker"), "amenity=parcel_locker", "luggage_locker",
        "parcel locker,parcel station,packstation,paketstation,paketautomat"},
    {"bank", kli18nc("@item place category", "Bank"), "amenity=bank", "bank",
        "bank,banks,geldinstitut"},
    {"doctors", kli18nc("@item place category", "Doctor"), "amenity=doctors", "doctors",
        "doctor,doctors,physician,general practitioner,medical practice,arzt,ärztin,hausarzt,hausärztin,arztpraxis,praxis"},
    {"dentist", kli18nc("@item place category", "Dentist"), "amenity=dentist", "dentist",
        "dentist,dental practice,zahnarzt,zahnärztin,zahnarztpraxis"},
    {"hospital", kli18nc("@item place category", "Hospital"), "amenity=hospital", "hospital",
        "hospital,clinic,emergency room,krankenhaus,klinik,klinikum,spital,notaufnahme"},
    {"drinking_water", kli18nc("@item place category", "Drinking Water"), "amenity=drinking_water", "drinking_water",
        "drinking water,water fountain,water,trinkwasser,trinkbrunnen,wasserspender,wasser"},
    {"butcher", kli18nc("@item place category", "Butcher"), "shop=butcher", "butcher",
        "butcher,butchery,meat,metzgerei,metzger,fleischerei,fleischer"},
    {"beverages", kli18nc("@item place category", "Beverage Store"), "shop=beverages", "beverages",
        "beverage store,beverages,drinks store,getränkemarkt,getränke,getränkehandel"},
    {"chemist", kli18nc("@item place category", "Drugstore"), "shop=chemist", "chemist",
        "chemist,toiletries,drogerie,drogeriemarkt"},
    {"bicycle_parking", kli18nc("@item place category", "Bicycle Parking"), "amenity=bicycle_parking", "bicycle_parking",
        "bicycle parking,bike parking,bike rack,fahrradparkplatz,fahrradständer,radständer,fahrradabstellanlage,fahrradgarage"},
    {"bicycle_rental", kli18nc("@item place category", "Bicycle Rental"), "amenity=bicycle_rental", "bicycle_rental",
        "bicycle rental,bike rental,bike sharing,bike share,rental bike,fahrradverleih,radverleih,fahrradvermietung,leihfahrrad,leihrad"},
    {"bicycle_shop", kli18nc("@item place category", "Bicycle Shop"), "shop=bicycle", "bicycle",
        "bicycle shop,bike shop,bicycle repair,bike repair,fahrradladen,fahrradgeschäft,radladen,fahrradhändler,fahrradwerkstatt"},
    {"car_rental", kli18nc("@item place category", "Car Rental"), "amenity=car_rental", "car_rental",
        "car rental,car hire,rental car,autovermietung,autoverleih,mietwagen,leihwagen"},
    {"taxi", kli18nc("@item place category", "Taxi Stand"), "amenity=taxi", "taxi",
        "taxi,taxi stand,taxi rank,cab,taxistand"},
    {"car_repair", kli18nc("@item place category", "Car Repair"), "shop=car_repair", "car_repair",
        "car repair,mechanic,auto repair,autowerkstatt,kfz werkstatt,werkstatt"},
    {"camping", kli18nc("@item place category", "Campground"), "tourism=camp_site,tourism=caravan_site", "caravan_site",
        "campground,campsite,camp site,camping,caravan site,rv park,campingplatz,zeltplatz,wohnmobilstellplatz,stellplatz"},
    {"museum", kli18nc("@item place category", "Museum"), "tourism=museum", "museum",
        "museum,gallery,museen,ausstellung"},
    {"tourist_information", kli18nc("@item place category", "Tourist Information"), "tourism=information", "information",
        "tourist information,tourist info,visitor center,visitor centre,information,touristinformation,touristeninformation,touristinfo,verkehrsamt,fremdenverkehrsamt"},
    {"attraction", kli18nc("@item place category", "Tourist Attraction"), "tourism=attraction", "artwork",
        "attraction,tourist attraction,sight,sights,sightseeing,landmark,sehenswürdigkeit,attraktion"},
    {"viewpoint", kli18nc("@item place category", "Viewpoint"), "tourism=viewpoint", "viewpoint",
        "viewpoint,lookout,scenic view,aussichtspunkt,aussicht,aussichtsturm"},
    {"playground", kli18nc("@item place category", "Playground"), "leisure=playground", "playground",
        "playground,play area,spielplatz,kinderspielplatz"},
    {"park", kli18nc("@item place category", "Park"), "leisure=park", "tree",
        "park,public garden,grünanlage,stadtpark"},
    {"swimming", kli18nc("@item place category", "Swimming Pool"), "leisure=swimming_pool,amenity=public_bath,leisure=water_park", "public_bath",
        "swimming pool,swimming,pool,public bath,lido,water park,schwimmbad,hallenbad,freibad,spaßbad,erlebnisbad,badesee"},
    {"cinema", kli18nc("@item place category", "Cinema"), "amenity=cinema", "cinema",
        "cinema,movie theater,movies,kino,filmtheater,lichtspielhaus"},
    {"theatre", kli18nc("@item place category", "Theater"), "amenity=theatre", "theatre",
        "theater,theatre,playhouse,schauspielhaus,oper,opera"},
    {"library", kli18nc("@item place category", "Library"), "amenity=library", "library",
        "library,bibliothek,bücherei,stadtbibliothek,stadtbücherei"},
    {"place_of_worship", kli18nc("@item place category", "Place of Worship"), "amenity=place_of_worship", "place_of_worship",
        "place of worship,church,chapel,mosque,synagogue,temple,kirche,kapelle,dom,moschee,synagoge,tempel,gotteshaus"},
    {"police", kli18nc("@item place category", "Police"), "amenity=police", "police",
        "police,police station,polizei,polizeiwache,polizeistation,polizeirevier"},
    {"townhall", kli18nc("@item place category", "Town Hall"), "amenity=townhall", "townhall",
        "town hall,city hall,citizens office,rathaus,bürgeramt,bürgerbüro,gemeindeverwaltung,stadtverwaltung"},
    {"veterinary", kli18nc("@item place category", "Veterinarian"), "amenity=veterinary", "veterinary",
        "veterinarian,veterinary,vet,animal clinic,tierarzt,tierärztin,tierklinik"},
    {"optician", kli18nc("@item place category", "Optician"), "shop=optician", "optician",
        "optician,glasses,optiker,brillen,augenoptiker"},
    {"hairdresser", kli18nc("@item place category", "Hairdresser"), "shop=hairdresser", "hairdresser",
        "hairdresser,barber,hair salon,friseur,frisör,friseursalon,coiffeur"},
    {"laundry", kli18nc("@item place category", "Laundry"), "shop=laundry", "laundry",
        "laundry,laundromat,launderette,waschsalon,wäscherei"},
    {"diy", kli18nc("@item place category", "Hardware Store"), "shop=doityourself,shop=hardware", "doityourself",
        "hardware store,diy store,home improvement,baumarkt,eisenwaren,eisenwarenhandlung"},
    {"garden_centre", kli18nc("@item place category", "Garden Center"), "shop=garden_centre", "garden_centre",
        "garden center,garden centre,gartencenter,gärtnerei,gartenmarkt"},
    {"electronics", kli18nc("@item place category", "Electronics Store"), "shop=electronics", "electronics",
        "electronics,electronics store,elektronik,elektronikmarkt,elektrofachmarkt"},
    {"recycling", kli18nc("@item place category", "Recycling"), "amenity=recycling", "recycling",
        "recycling,recycling center,recycling centre,bottle bank,wertstoffhof,recyclinghof,glascontainer,altglas,altkleider,altkleidercontainer"},
};
// clang-format on

// categories whose places usually have no name, such as most toilets or charging stations
constexpr const char *mostlyUnnamedCategories[] = {
    "atm", "bicycle_parking", "charging_station", "drinking_water", "parcel_locker", "parking", "recycling", "taxi", "toilets",
};

// words that don't change what is searched for, e.g. in "nearest bakeries" or "Apotheke in der Nähe"
constexpr const char *ignoredWords[] = {
    // English
    "a", "an", "any", "are", "around", "close", "closest", "find", "here", "in", "is", "me", "my", "near", "nearby", "nearest", "next",
    "show", "some", "the", "there", "to", "where",
    // German
    "bei", "das", "dem", "den", "der", "des", "die", "ein", "eine", "einen", "einer", "es", "finde", "gibt", "herum", "hier",
    "im", "in", "ist", "meiner", "mir", "nachste", "nachsten", "nachster", "nachstes", "nachstgelegene", "nachstgelegenen", "nahe",
    "naher", "suche", "sind", "um", "umgebung", "wo", "zeige",
};

struct Category {
    const CategoryData *data;
    bool mostlyUnnamed = false;
    QString name;
    QStringList osmTags;
    QString iconSource;
    // names and keywords in matching form, without spaces
    QStringList terms;
};

QString termForm(const QString &text)
{
    return PlaceCategories::normalize(text).remove(' '_L1);
}

const std::vector<Category> &categories()
{
    static std::vector<Category> s_categories;
    if (!s_categories.empty()) {
        return s_categories;
    }

    s_categories.reserve(std::size(categoryData));
    for (const auto &data : categoryData) {
        Category c;
        c.data = &data;
        c.mostlyUnnamed = std::any_of(std::begin(mostlyUnnamedCategories), std::end(mostlyUnnamedCategories), [&data](auto id) {
            return qstrcmp(id, data.id) == 0;
        });
        c.name = data.name.toString();
        c.osmTags = QString::fromLatin1(data.osmTags).split(','_L1);
        const auto iconFile = ":/org.kde.kosmindoormap/assets/icons/"_L1 + QLatin1StringView(data.icon) + ".svg"_L1;
        // as URL, a plain path would be taken as relative to the QML file it is used in
        c.iconSource = QFile::exists(iconFile) ? "qrc"_L1 + iconFile : u"map-symbolic"_s;

        const auto addTerm = [&c](const QString &text) {
            const auto term = termForm(text);
            if (!term.isEmpty() && !c.terms.contains(term)) {
                c.terms.push_back(term);
            }
        };
        addTerm(c.name);
        addTerm(QString::fromUtf8(data.name.untranslatedText()));
        for (const auto &keyword : QString::fromUtf8(data.keywords).split(','_L1)) {
            addTerm(keyword);
        }
        s_categories.push_back(std::move(c));
    }
    return s_categories;
}

QVariantMap toVariant(const Category &c)
{
    return {
        {u"id"_s, QString::fromLatin1(c.data->id)},
        {u"name"_s, c.name},
        {u"osmTags"_s, c.osmTags},
        {u"iconSource"_s, c.iconSource},
        {u"mostlyUnnamed"_s, c.mostlyUnnamed},
    };
}

// checks whether @p text is @p term or a plural of it, in English or German
bool isWordForm(QStringView text, QStringView term)
{
    if (text == term) {
        return true;
    }
    if (!text.startsWith(term)) {
        // English plurals of words ending in y ("pharmacies") and German plurals of words ending in um ("Museen")
        return (term.endsWith('y'_L1) && text.size() == term.size() + 2 && text.startsWith(term.chopped(1)) && text.endsWith("ies"_L1))
            || (term.endsWith("um"_L1) && text.size() == term.size() && text.startsWith(term.chopped(2)) && text.endsWith("en"_L1));
    }
    const auto suffix = text.mid(term.size());
    // short words have few plurals but many look-alikes ("bar" and "Bären")
    if (term.size() < 4) {
        return suffix == "s"_L1;
    }
    constexpr const QLatin1StringView pluralSuffixes[] = {"s"_L1, "e"_L1, "n"_L1, "en"_L1, "er"_L1, "es"_L1, "nen"_L1};
    return std::any_of(std::begin(pluralSuffixes), std::end(pluralSuffixes), [suffix](auto s) {
        return suffix == s;
    });
}
}

PlaceCategories::PlaceCategories(QObject *parent)
    : QObject(parent)
{
}

PlaceCategories::~PlaceCategories() = default;

QString PlaceCategories::normalize(const QString &text)
{
    const auto decomposed = text.toCaseFolded().normalized(QString::NormalizationForm_KD);
    QString s;
    s.reserve(decomposed.size());
    for (const auto c : decomposed) {
        if (c.isMark()) {
            continue;
        }
        if (c.isLetterOrNumber()) {
            s.push_back(c);
        } else if (!s.isEmpty() && !s.endsWith(' '_L1)) {
            s.push_back(' '_L1);
        }
    }
    if (s.endsWith(' '_L1)) {
        s.chop(1);
    }
    // not covered by case folding
    s.replace(u'ß', "ss"_L1);
    // "Bäckerei", "Backerei" and "Baeckerei" are all the same
    s.replace("ae"_L1, "a"_L1);
    s.replace("oe"_L1, "o"_L1);
    s.replace("ue"_L1, "u"_L1);
    return s;
}

QString PlaceCategories::matchText(const QString &text)
{
    static const auto ignored = []() {
        QStringList words;
        for (const auto word : ignoredWords) {
            words.push_back(normalize(QString::fromLatin1(word)));
        }
        return words;
    }();

    auto words = normalize(text).split(' '_L1, Qt::SkipEmptyParts);
    words.removeIf([](const auto &word) {
        return ignored.contains(word);
    });
    const auto query = words.join(QString());
    if (query.isEmpty()) {
        return {};
    }

    const auto &cats = categories();
    for (const auto &c : cats) {
        if (std::any_of(c.terms.begin(), c.terms.end(), [&query](const auto &term) {
                return isWordForm(query, term);
            })) {
            return QString::fromLatin1(c.data->id);
        }
    }

    // the beginning of a name, if it matches the shortest name of only one category
    if (query.size() < 3) {
        return {};
    }
    const Category *best = nullptr;
    qsizetype bestLength = 0;
    bool ambiguous = false;
    for (const auto &c : cats) {
        for (const auto &term : c.terms) {
            if (!term.startsWith(query)) {
                continue;
            }
            if (!best || term.size() < bestLength) {
                best = &c;
                bestLength = term.size();
                ambiguous = false;
            } else if (term.size() == bestLength && best != &c) {
                ambiguous = true;
            }
        }
    }
    return best && !ambiguous ? QString::fromLatin1(best->data->id) : QString();
}

QVariantMap PlaceCategories::category(const QString &id)
{
    const auto &cats = categories();
    const auto it = std::find_if(cats.begin(), cats.end(), [&id](const auto &c) {
        return QLatin1StringView(c.data->id) == id;
    });
    return it != cats.end() ? toVariant(*it) : QVariantMap();
}

QVariantMap PlaceCategories::categoryForText(const QString &text)
{
    const auto id = matchText(text);
    return id.isEmpty() ? QVariantMap() : category(id);
}

QVariantMap PlaceCategories::categoryForTag(const QString &key, const QString &value)
{
    const auto tag = key + '='_L1 + value;
    for (const auto &c : categories()) {
        if (c.osmTags.contains(tag) || c.osmTags.contains(key)) {
            return toVariant(c);
        }
    }
    return {};
}

QVariantList PlaceCategories::categoriesVariant()
{
    QVariantList l;
    for (const auto &c : categories()) {
        l.push_back(toVariant(c));
    }
    return l;
}

#include "moc_placecategories.cpp"
