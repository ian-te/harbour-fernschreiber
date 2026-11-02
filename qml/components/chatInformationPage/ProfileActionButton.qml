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
import QtQuick 2.6
import Sailfish.Silica 1.0

// One of the round action buttons under the profile photo (Chat, Call, Video, Mute, Search).
BackgroundItem {
    id: actionButton
    property alias iconSource: actionIcon.source
    property alias text: actionLabel.text

    height: Theme.itemSizeLarge
    _backgroundColor: "transparent"

    Rectangle {
        id: actionCircle
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: Theme.paddingSmall
        }
        width: Theme.itemSizeSmall
        height: width
        radius: width / 2
        color: Theme.rgba(actionButton.highlighted ? Theme.highlightBackgroundColor : Theme.primaryColor,
                          actionButton.highlighted ? Theme.highlightBackgroundOpacity : 0.1)
        Icon {
            id: actionIcon
            anchors.centerIn: parent
            highlighted: actionButton.highlighted
        }
    }
    Label {
        id: actionLabel
        anchors {
            top: actionCircle.bottom
            topMargin: Theme.paddingSmall
            horizontalCenter: parent.horizontalCenter
        }
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        truncationMode: TruncationMode.Fade
        font.pixelSize: Theme.fontSizeTiny
        color: actionButton.highlighted ? Theme.highlightColor : Theme.secondaryColor
    }
}
