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
import "../components"

// Telegram-style sticker panel, shown where the keyboard would be: a tab strip with
// "recent" and one tab per installed set, over one scrolling list of every set as a grid.
Item {
    id: stickerPanel

    signal stickerPicked(var stickerId)

    property var recentStickers: stickerManager.getRecentStickers()
    property var installedStickerSets: stickerManager.getInstalledStickerSets()
    readonly property int columns: Math.max(4, Math.floor(width / Theme.itemSizeExtraLarge))
    readonly property real cellSize: Math.floor(width / columns)

    // Sections of the list: recent stickers first (when there are any), then each set.
    readonly property var sections: {
        var result = [];
        var recent = (recentStickers || []).filter(function(s) { return s && s.sticker; });
        if (recent.length > 0) {
            result.push({ "isRecent": true, "title": qsTr("Recently used"), "stickers": recent });
        }
        for (var i = 0; i < (installedStickerSets ? installedStickerSets.length : 0); i++) {
            var set = installedStickerSets[i];
            result.push({ "isRecent": false, "id": set.id, "title": set.title, "stickers": set.stickers || [],
                          "thumbnail": set.thumbnail ? set.thumbnail : (set.stickers && set.stickers.length > 0 ? set.stickers[0].thumbnail : null) });
        }
        return result;
    }

    function reload() {
        recentStickers = stickerManager.getRecentStickers();
        installedStickerSets = stickerManager.getInstalledStickerSets();
    }

    Connections {
        target: stickerManager
        onStickerSetsReceived: stickerPanel.installedStickerSets = stickerManager.getInstalledStickerSets()
    }

    Connections {
        target: tdLibWrapper
        onOkReceived: {
            if (request === "removeStickerSet") {
                appNotification.show(qsTr("Sticker set successfully removed!"));
                tdLibWrapper.getInstalledStickerSets();
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.rgba(Theme.overlayBackgroundColor, 0.6)
    }

    // --- Tabs ---
    SilicaListView {
        id: tabStrip
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: Theme.itemSizeSmall
        orientation: ListView.Horizontal
        clip: true
        model: stickerPanel.sections
        currentIndex: stickerList.currentSection
        highlightFollowsCurrentItem: true
        highlightMoveDuration: 150
        highlight: Rectangle {
            color: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
            radius: Theme.paddingSmall
        }

        delegate: BackgroundItem {
            id: tabItem
            width: Theme.itemSizeSmall
            height: tabStrip.height
            onClicked: stickerList.positionViewAtIndex(index, ListView.Beginning)
            onPressAndHold: {
                if (!modelData.isRecent) {
                    var stickerSetId = modelData.id;
                    Remorse.popupAction(chatPage, qsTr("Removing sticker set"), function() {
                        tdLibWrapper.changeStickerSet(stickerSetId, false);
                    });
                }
            }
            Icon {
                visible: modelData.isRecent
                anchors.centerIn: parent
                source: "image://theme/icon-m-clock"
                highlighted: tabItem.highlighted
            }
            TDLibThumbnail {
                visible: !modelData.isRecent && !!modelData.thumbnail
                thumbnail: modelData.isRecent ? null : modelData.thumbnail
                anchors.centerIn: parent
                width: Theme.iconSizeMedium
                height: Theme.iconSizeMedium
                highlighted: tabItem.highlighted
            }
        }
    }

    Separator {
        id: tabSeparator
        anchors.top: tabStrip.bottom
        width: parent.width
        color: Theme.primaryColor
        horizontalAlignment: Qt.AlignHCenter
    }

    // --- All sets, one grid each ---
    SilicaListView {
        id: stickerList
        anchors {
            top: tabSeparator.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        clip: true
        model: stickerPanel.sections
        cacheBuffer: height
        // The section whose header is at (or above) the top edge, for the tab highlight.
        readonly property int currentSection: {
            var i = indexAt(0, contentY + Theme.paddingSmall);
            return i < 0 ? 0 : i;
        }

        delegate: Column {
            width: stickerList.width

            Label {
                width: parent.width
                leftPadding: Theme.paddingMedium
                topPadding: Theme.paddingSmall
                bottomPadding: Theme.paddingSmall
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                color: Theme.secondaryHighlightColor
                truncationMode: TruncationMode.Fade
                text: modelData.title
            }

            Grid {
                columns: stickerPanel.columns
                Repeater {
                    model: modelData.stickers
                    delegate: BackgroundItem {
                        id: stickerItem
                        width: stickerPanel.cellSize
                        height: stickerPanel.cellSize
                        onClicked: stickerPanel.stickerPicked(modelData.sticker.remote.id)
                        TDLibThumbnail {
                            thumbnail: modelData.thumbnail
                            anchors.fill: parent
                            anchors.margins: Theme.paddingSmall
                            highlighted: stickerItem.highlighted
                        }
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: stickerList.count === 0
            text: qsTr("No stickers")
        }

        VerticalScrollDecorator {}
    }
}
