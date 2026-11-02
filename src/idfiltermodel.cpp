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
#include "idfiltermodel.h"
#include <climits>

IdFilterModel::IdFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent)
    , m_idRole(-1)
    , m_active(false)
{
    setDynamicSortFilter(true);
}

void IdFilterModel::setSource(QObject *model)
{
    QAbstractItemModel *itemModel = qobject_cast<QAbstractItemModel*>(model);
    if (sourceModel() != itemModel) {
        setSourceModel(itemModel);
        updateRole();
        refresh();
        emit sourceChanged();
    }
}

void IdFilterModel::setIdRoleName(const QString &role)
{
    if (m_idRoleName != role) {
        m_idRoleName = role;
        updateRole();
        refresh();
        emit idRoleNameChanged();
    }
}

void IdFilterModel::setIds(const QVariantList &ids)
{
    m_ids = ids;
    m_rank.clear();
    for (int i = 0; i < ids.size(); i++) {
        const qlonglong id = ids.at(i).toLongLong();
        if (!m_rank.contains(id)) {
            m_rank.insert(id, i);
        }
    }
    refresh();
    emit idsChanged();
}

void IdFilterModel::setActive(bool active)
{
    if (m_active != active) {
        m_active = active;
        refresh();
        emit activeChanged();
    }
}

bool IdFilterModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    if (!m_active) {
        return true;
    }
    if (m_idRole < 0 || !sourceModel()) {
        return false;
    }
    const QModelIndex index = sourceModel()->index(sourceRow, 0, sourceParent);
    return m_rank.contains(sourceModel()->data(index, m_idRole).toLongLong());
}

bool IdFilterModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    if (!m_active || m_idRole < 0) {
        return left.row() < right.row();
    }
    const int l = m_rank.value(sourceModel()->data(left, m_idRole).toLongLong(), INT_MAX);
    const int r = m_rank.value(sourceModel()->data(right, m_idRole).toLongLong(), INT_MAX);
    return (l != r) ? (l < r) : (left.row() < right.row());
}

void IdFilterModel::updateRole()
{
    m_idRole = -1;
    if (sourceModel() && !m_idRoleName.isEmpty()) {
        const QHash<int, QByteArray> roles = sourceModel()->roleNames();
        for (auto it = roles.constBegin(); it != roles.constEnd(); ++it) {
            if (it.value() == m_idRoleName.toUtf8()) {
                m_idRole = it.key();
                break;
            }
        }
    }
}

void IdFilterModel::refresh()
{
    invalidate();
    // Sorted by search rank while active, source order otherwise.
    sort(m_active ? 0 : -1);
}
