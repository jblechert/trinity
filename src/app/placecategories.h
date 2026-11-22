/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#ifndef PLACECATEGORIES_H
#define PLACECATEGORIES_H

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <qqmlregistration.h>

/** Categories of places to search for on the map, such as bakeries, pharmacies or ATMs,
 *  with their OpenStreetMap tags.
 *
 *  Categories are represented in QML as objects with the following keys:
 *  - id: an untranslated identifier, e.g. "bakery"
 *  - name: the translated name, e.g. "Bakery"
 *  - osmTags: the OSM tags of places in this category, any of which has to match, e.g. ["shop=bakery"]
 *  - iconSource: an icon for places in this category
 *  - mostlyUnnamed: places in this category usually have no name, such as toilets or charging stations
 */
class PlaceCategories : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    /** All categories, the most commonly needed ones first. */
    Q_PROPERTY(QVariantList categories READ categoriesVariant CONSTANT)

public:
    explicit PlaceCategories(QObject *parent = nullptr);
    ~PlaceCategories() override;

    /** The category with the identifier @p id, an empty object if there is none. */
    Q_INVOKABLE [[nodiscard]] static QVariantMap category(const QString &id);

    /** The category a search text typed by the user refers to, an empty object if it refers to none.
     *  This matches names of categories and common synonyms in English, German and the language
     *  of the user interface. Case, diacritics and plurals don't matter, neither do phrases
     *  such as "nearest" or "in der Nähe". A beginning of a name matches as well if
     *  it is unambiguous.
     */
    Q_INVOKABLE [[nodiscard]] static QVariantMap categoryForText(const QString &text);

    /** The category of a place with the OSM tag @p key = @p value, an empty object if there is none. */
    Q_INVOKABLE [[nodiscard]] static QVariantMap categoryForTag(const QString &key, const QString &value);

    /** Identifier of the category matching @p text, empty if none.
     *  @see categoryForText()
     */
    [[nodiscard]] static QString matchText(const QString &text);

    /** @p text in the form used for matching: lower case, without diacritics and punctuation,
     *  with German umlauts and their transliterations ("ae", "oe", "ue") mapped to the same letters.
     *  Words are separated by a single space.
     *  @internal exposed for unit tests
     */
    [[nodiscard]] static QString normalize(const QString &text);

private:
    [[nodiscard]] static QVariantList categoriesVariant();
};

#endif // PLACECATEGORIES_H
