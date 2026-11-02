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
import "../"
import "../../pages"
import "../../js/twemoji.js" as Emoji
import "../../js/functions.js" as Functions

// Shared media of a chat, like Telegram's profile tabs: photos and videos as a grid,
// files, links and voice messages as lists. filter (from the tab model) is a TDLib
// searchMessagesFilter type. Loads 60 at a time, more when scrolled to the end.
ChatInformationTabItemBase {
    id: tabBase

    readonly property string filterType: filter
    readonly property bool isGrid: filterType === "searchMessagesFilterPhotoAndVideo"
    readonly property string requestTag: "sharedMedia:" + filterType + ":" + chatInformationPage.chatInformation.id
    property var mediaMessages: []
    property bool requested: false
    property bool finished: false
    property string nextFromMessageId: "0"

    loading: !finished && mediaMessages.length === 0
    loadingText: qsTr("Loading…")

    function loadMore() {
        if (requested || finished) {
            return;
        }
        requested = true;
        tdLibWrapper.searchChatSharedMedia(chatInformationPage.chatInformation.id, filterType, nextFromMessageId, 60);
    }

    // Jump to the message in the chat this profile belongs to.
    function showInChat(messageId) {
        var chatPageItem = pageStack.previousPage(chatInformationPage);
        if (chatPageItem && chatPageItem.chatInformation && chatPageItem.chatInformation.id === chatInformationPage.chatInformation.id
                && typeof chatPageItem.showMessage === "function") {
            pageStack.navigateBack();
            chatPageItem.showMessage(String(messageId), true);
        }
    }

    function firstUrl(message) {
        var content = message.content;
        if (content.web_page && content.web_page.url) {
            return content.web_page.url;
        }
        var formatted = content.text || content.caption;
        if (!formatted) {
            return "";
        }
        var entities = formatted.entities || [];
        for (var i = 0; i < entities.length; i++) {
            var type = entities[i].type["@type"];
            if (type === "textEntityTypeTextUrl") {
                return entities[i].type.url;
            }
            if (type === "textEntityTypeUrl") {
                return formatted.text.substr(entities[i].offset, entities[i].length);
            }
        }
        return "";
    }

    function formatDuration(seconds) {
        var s = seconds % 60;
        return Math.floor(seconds / 60) + ":" + (s < 10 ? "0" : "") + s;
    }

    onActiveChanged: {
        if (active && mediaMessages.length === 0) {
            loadMore();
        }
    }
    Component.onCompleted: {
        if (active) {
            loadMore();
        }
    }

    Connections {
        target: tdLibWrapper
        onSharedMediaReceived: {
            if (extra !== tabBase.requestTag) {
                return;
            }
            tabBase.requested = false;
            tabBase.mediaMessages = tabBase.mediaMessages.concat(messages);
            if (messages.length === 0 || !nextFromMessageId) {
                tabBase.finished = true;
            } else {
                tabBase.nextFromMessageId = String(nextFromMessageId);
            }
        }
        onErrorReceived: {
            if (extra === tabBase.requestTag) {
                tabBase.requested = false;
                tabBase.finished = true;
            }
        }
    }

    // Same header collapse behaviour as the members tab.
    function handleScrollIntoView(view, force) {
        if (!tabBase.loading && !view.dragging && !view.quickScrollAnimating) {
            if (!view.atYBeginning) {
                pageContent.scrollDown();
            } else {
                pageContent.scrollUp(force);
            }
        }
    }

    // --- Photos and videos ---
    SilicaGridView {
        id: mediaGrid
        visible: tabBase.isGrid
        width: tabBase.width
        height: tabBase.height
        clip: true
        model: tabBase.isGrid ? tabBase.mediaMessages : []
        readonly property int columns: tabBase.width > tabBase.height ? 5 : 3
        cellWidth: Math.floor(width / columns)
        cellHeight: cellWidth
        onDraggingChanged: tabBase.handleScrollIntoView(mediaGrid)
        onAtYBeginningChanged: tabBase.handleScrollIntoView(mediaGrid)
        onQuickScrollAnimatingChanged: tabBase.handleScrollIntoView(mediaGrid, true)
        onAtYEndChanged: if (atYEnd && count > 0) tabBase.loadMore()

        delegate: BackgroundItem {
            id: mediaItem
            width: mediaGrid.cellWidth
            height: mediaGrid.cellHeight
            readonly property bool isVideo: modelData.content["@type"] === "messageVideo"
            onClicked: pageStack.push(Qt.resolvedUrl("../../pages/MediaAlbumPage.qml"), {
                                          "messages": tabBase.mediaMessages,
                                          "index": index
                                      })
            Loader {
                anchors.fill: parent
                anchors.margins: 1
                sourceComponent: mediaItem.isVideo ? videoThumbnail : photoThumbnail
                Component {
                    id: photoThumbnail
                    TDLibPhoto {
                        photo: modelData.content.photo
                        highlighted: mediaItem.highlighted
                    }
                }
                Component {
                    id: videoThumbnail
                    TDLibThumbnail {
                        thumbnail: modelData.content.video.thumbnail
                        minithumbnail: modelData.content.video.minithumbnail
                        highlighted: mediaItem.highlighted
                    }
                }
            }
            Rectangle {
                visible: mediaItem.isVideo
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                    margins: Theme.paddingSmall
                }
                width: durationLabel.width + Theme.paddingSmall * 2
                height: durationLabel.height
                radius: height / 2
                color: Theme.rgba("black", 0.6)
                Label {
                    id: durationLabel
                    anchors.centerIn: parent
                    font.pixelSize: Theme.fontSizeTiny
                    color: "white"
                    text: mediaItem.isVideo ? tabBase.formatDuration(modelData.content.video.duration) : ""
                }
            }
        }

        ViewPlaceholder {
            enabled: tabBase.isGrid && tabBase.finished && mediaGrid.count === 0
            text: qsTr("No photos or videos yet")
        }
        VerticalScrollDecorator {}
    }

    // --- Files, links, voice messages ---
    SilicaListView {
        id: mediaList
        visible: !tabBase.isGrid
        width: tabBase.width
        height: tabBase.height
        clip: true
        model: tabBase.isGrid ? [] : tabBase.mediaMessages
        onDraggingChanged: tabBase.handleScrollIntoView(mediaList)
        onAtYBeginningChanged: tabBase.handleScrollIntoView(mediaList)
        onQuickScrollAnimatingChanged: tabBase.handleScrollIntoView(mediaList, true)
        onAtYEndChanged: if (atYEnd && count > 0) tabBase.loadMore()

        delegate: ListItem {
            id: listItem
            contentHeight: Theme.itemSizeMedium
            readonly property string contentType: modelData.content["@type"]
            readonly property string url: tabBase.filterType === "searchMessagesFilterUrl" ? tabBase.firstUrl(modelData) : ""

            onClicked: {
                if (url !== "") {
                    Qt.openUrlExternally(url.indexOf("://") < 0 ? "https://" + url : url);
                } else {
                    tabBase.showInChat(modelData.id);
                }
            }
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Show in chat")
                    onClicked: tabBase.showInChat(modelData.id)
                }
                MenuItem {
                    visible: listItem.url !== ""
                    text: qsTr("Copy link")
                    onClicked: Clipboard.text = listItem.url
                }
            }

            Icon {
                id: typeIcon
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                source: listItem.contentType === "messageVoiceNote" ? "image://theme/icon-m-mic"
                        : (listItem.contentType === "messageAudio" ? "image://theme/icon-m-music"
                        : (listItem.url !== "" ? "image://theme/icon-m-link" : "image://theme/icon-m-document"))
                highlighted: listItem.highlighted
            }
            Column {
                anchors {
                    left: typeIcon.right
                    leftMargin: Theme.paddingLarge
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    color: listItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    text: {
                        var c = modelData.content;
                        if (listItem.contentType === "messageDocument") {
                            return c.document.file_name;
                        }
                        if (listItem.contentType === "messageVoiceNote") {
                            return qsTr("Voice message") + "  " + tabBase.formatDuration(c.voice_note.duration);
                        }
                        if (listItem.contentType === "messageAudio") {
                            return (c.audio.performer ? c.audio.performer + " – " : "") + (c.audio.title || c.audio.file_name);
                        }
                        if (c.web_page && c.web_page.title) {
                            return Emoji.emojify(c.web_page.title, Theme.fontSizeMedium);
                        }
                        return listItem.url;
                    }
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    text: {
                        var parts = [];
                        var c = modelData.content;
                        if (listItem.contentType === "messageDocument") {
                            parts.push(Format.formatFileSize(c.document.document.size));
                        } else if (listItem.url !== "" && c.web_page && c.web_page.title) {
                            parts.push(listItem.url);
                        }
                        parts.push(Functions.getDateTimeTranslated(modelData.date));
                        return parts.join(" · ");
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: !tabBase.isGrid && tabBase.finished && mediaList.count === 0
            text: tabBase.filterType === "searchMessagesFilterDocument" ? qsTr("No files yet")
                  : (tabBase.filterType === "searchMessagesFilterUrl" ? qsTr("No links yet") : qsTr("No voice messages yet"))
        }
        VerticalScrollDecorator {}
    }
}
