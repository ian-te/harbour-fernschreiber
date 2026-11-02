/*
    Copyright (C) 2026 Fernschreiber contributors

    This file is part of Fernschreiber.

    Fernschreiber is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Fernschreiber is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Fernschreiber. If not, see <http://www.gnu.org/licenses/>.
*/
#ifndef IDFILTERMODEL_H
#define IDFILTERMODEL_H

#include <QSortFilterProxyModel>
#include <QHash>
#include <QVariantList>

// Shows only the rows whose id (idRoleName) is in ids, in the order of ids.
// Used for search: TDLib does the matching (word prefixes, transliteration,
// usernames) the way Telegram's own apps do, and returns the matching ids.
// While inactive, every row is shown in the source order.
class IdFilterModel : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(QObject* sourceModel READ sourceModel WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(QString idRoleName READ idRoleName WRITE setIdRoleName NOTIFY idRoleNameChanged)
    Q_PROPERTY(QVariantList ids READ ids WRITE setIds NOTIFY idsChanged)
    Q_PROPERTY(bool active READ isActive WRITE setActive NOTIFY activeChanged)

public:
    IdFilterModel(QObject *parent = Q_NULLPTR);

    void setSource(QObject *model);
    QString idRoleName() const { return m_idRoleName; }
    void setIdRoleName(const QString &role);
    QVariantList ids() const { return m_ids; }
    void setIds(const QVariantList &ids);
    bool isActive() const { return m_active; }
    void setActive(bool active);

signals:
    void sourceChanged();
    void idRoleNameChanged();
    void idsChanged();
    void activeChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const Q_DECL_OVERRIDE;
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const Q_DECL_OVERRIDE;

private:
    void updateRole();
    void refresh();

    QString m_idRoleName;
    int m_idRole;
    QVariantList m_ids;
    QHash<qlonglong, int> m_rank;
    bool m_active;
};

#endif // IDFILTERMODEL_H
