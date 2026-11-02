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
import WerkWolf.Fernschreiber 1.0
import "../js/debug.js" as Debug

// Telegram-style voice message button: hold to record, release to send,
// slide left to cancel, slide up to lock and keep recording hands-free.
// While recording, a bar of barWidth is drawn to the left of the button,
// over the space the text field normally takes.
Item {
    id: voiceRecordButton

    property real barWidth: 0
    // "idle", "pressed" (finger down, not recording yet), "holding", "locked", "stopping"
    property string phase: "idle"
    readonly property bool recording: phase === "holding" || phase === "locked" || phase === "stopping"
    property int recordingState: fernschreiberUtils.getVoiceNoteRecordingState()
    property int durationSeconds: 0
    property bool sendWhenStopped: false
    property real dragX: 0
    property real dragY: 0

    readonly property real cancelDistance: Theme.itemSizeHuge
    readonly property real lockDistance: Theme.itemSizeMedium * 1.5
    readonly property int minimumDurationMs: 700

    // Asks the page to send the finished recording. The page knows the chat and reply target.
    signal sendRequested(string path, int durationSeconds, string waveform)
    signal tapped()

    width: Theme.itemSizeSmall
    height: Theme.itemSizeSmall

    function formatDuration(seconds) {
        var s = seconds % 60;
        return Math.floor(seconds / 60) + ":" + (s < 10 ? "0" : "") + s;
    }

    function startRecording() {
        Debug.log("[VoiceRecordButton] start");
        durationSeconds = 0;
        dragX = 0;
        dragY = 0;
        phase = "holding";
        fernschreiberUtils.startRecordingVoiceNote();
    }

    function finish(send) {
        if (!recording || phase === "stopping") {
            return;
        }
        Debug.log("[VoiceRecordButton] finish, send: " + send);
        sendWhenStopped = send;
        phase = "stopping";
        dragX = 0;
        dragY = 0;
        fernschreiberUtils.stopRecordingVoiceNote();
        stopFallbackTimer.restart();
    }

    function cancel() {
        finish(false);
    }

    function handleStopped() {
        stopFallbackTimer.stop();
        var durationMs = fernschreiberUtils.getVoiceNoteDuration();
        if (sendWhenStopped && durationMs >= minimumDurationMs) {
            sendRequested(fernschreiberUtils.voiceNotePath(), Math.max(1, Math.round(durationMs / 1000)), fernschreiberUtils.getVoiceNoteWaveform());
        } else if (sendWhenStopped) {
            Debug.log("[VoiceRecordButton] too short, dropped: " + durationMs);
        }
        sendWhenStopped = false;
        phase = "idle";
    }

    Component.onDestruction: {
        if (recording) {
            sendWhenStopped = false;
            fernschreiberUtils.stopRecordingVoiceNote();
        }
    }

    Connections {
        target: fernschreiberUtils
        onVoiceNoteDurationChanged: {
            if (voiceRecordButton.recording) {
                voiceRecordButton.durationSeconds = Math.floor(duration / 1000);
            }
        }
        onVoiceNoteRecordingStateChanged: {
            voiceRecordButton.recordingState = state;
            if (voiceRecordButton.phase === "stopping" && state === FernschreiberUtilities.Ready) {
                voiceRecordButton.handleStopped();
            }
        }
    }

    // A recording stopped before it really started never reports Finalizing -> Ready.
    Timer {
        id: stopFallbackTimer
        interval: 3000
        onTriggered: {
            if (voiceRecordButton.phase === "stopping") {
                Debug.log("[VoiceRecordButton] no Ready after stop, state " + voiceRecordButton.recordingState);
                voiceRecordButton.handleStopped();
            }
        }
    }

    // A short press is a tap (shows a hint); only a hold starts recording.
    Timer {
        id: holdTimer
        interval: 200
        onTriggered: voiceRecordButton.startRecording()
    }

    // --- Recording bar, to the left of the button ---
    Item {
        id: recordingBar
        visible: voiceRecordButton.recording
        anchors {
            right: parent.left
            verticalCenter: parent.verticalCenter
        }
        width: voiceRecordButton.barWidth
        height: parent.height
        clip: true

        Rectangle {
            id: recordingDot
            width: Theme.paddingLarge
            height: width
            radius: width / 2
            color: "#e53935"
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            SequentialAnimation on opacity {
                running: recordingBar.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.2; duration: 600 }
                NumberAnimation { to: 1; duration: 600 }
            }
        }

        Label {
            id: durationLabel
            anchors {
                left: recordingDot.right
                leftMargin: Theme.paddingMedium
                verticalCenter: parent.verticalCenter
            }
            font.pixelSize: Theme.fontSizeMedium
            text: voiceRecordButton.formatDuration(voiceRecordButton.durationSeconds)
        }

        Label {
            id: slideToCancelLabel
            visible: voiceRecordButton.phase === "holding"
            anchors {
                verticalCenter: parent.verticalCenter
                horizontalCenter: parent.horizontalCenter
                horizontalCenterOffset: Theme.paddingLarge + Math.min(0, voiceRecordButton.dragX)
            }
            opacity: 1 - Math.min(1, -Math.min(0, voiceRecordButton.dragX) / voiceRecordButton.cancelDistance) * 0.8
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeSmall
            text: "‹  " + qsTr("Slide to cancel")
        }

        BackgroundItem {
            id: cancelLockedButton
            visible: voiceRecordButton.phase === "locked"
            anchors {
                verticalCenter: parent.verticalCenter
                horizontalCenter: parent.horizontalCenter
                horizontalCenterOffset: Theme.paddingLarge
            }
            width: cancelLockedLabel.width + 2 * Theme.paddingLarge
            height: parent.height
            onClicked: voiceRecordButton.cancel()
            Label {
                id: cancelLockedLabel
                anchors.centerIn: parent
                color: cancelLockedButton.highlighted ? Theme.highlightColor : Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                text: qsTr("Cancel")
            }
        }
    }

    // --- Lock hint above the button while holding ---
    Rectangle {
        id: lockHint
        visible: voiceRecordButton.phase === "holding"
        width: parent.width
        height: lockHintColumn.height + 2 * Theme.paddingMedium
        radius: width / 2
        color: Theme.rgba(Theme.overlayBackgroundColor, 0.85)
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.top
            bottomMargin: Theme.paddingLarge + Math.max(0, -voiceRecordButton.dragY) * 0.5
        }
        Column {
            id: lockHintColumn
            anchors.centerIn: parent
            spacing: Theme.paddingSmall
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "image://theme/icon-s-secure"
            }
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "image://theme/icon-m-page-up"
                width: Theme.iconSizeSmall
                height: Theme.iconSizeSmall
            }
        }
    }

    // --- The button itself ---
    Rectangle {
        id: recordingCircle
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: voiceRecordButton.phase === "holding" ? Math.max(-voiceRecordButton.cancelDistance, Math.min(0, voiceRecordButton.dragX)) * 0.3 : 0
        width: parent.width * 1.6
        height: width
        radius: width / 2
        color: Theme.highlightBackgroundColor
        visible: voiceRecordButton.recording
        scale: voiceRecordButton.recording ? 1 : 0.5
        Behavior on scale { NumberAnimation { duration: 150 } }
    }

    Icon {
        anchors.centerIn: recordingCircle.visible ? recordingCircle : parent
        source: voiceRecordButton.phase === "locked" ? "image://theme/icon-m-send" : "image://theme/icon-m-mic"
        highlighted: mouseArea.pressed && !voiceRecordButton.recording
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        // Keep the page stack and list views from taking over the slide gestures.
        preventStealing: true
        property real startX: 0
        property real startY: 0
        // The press that slid up into "locked" must not count as tapping send when it lifts.
        property bool lockedInThisPress: false

        onPressed: {
            lockedInThisPress = false;
            if (voiceRecordButton.phase !== "idle") {
                return;
            }
            startX = mouse.x;
            startY = mouse.y;
            voiceRecordButton.phase = "pressed";
            holdTimer.restart();
        }
        onPositionChanged: {
            if (voiceRecordButton.phase !== "holding") {
                return;
            }
            voiceRecordButton.dragX = mouse.x - startX;
            voiceRecordButton.dragY = mouse.y - startY;
            if (voiceRecordButton.dragX < -voiceRecordButton.cancelDistance) {
                voiceRecordButton.cancel();
            } else if (voiceRecordButton.dragY < -voiceRecordButton.lockDistance) {
                voiceRecordButton.dragX = 0;
                voiceRecordButton.dragY = 0;
                lockedInThisPress = true;
                voiceRecordButton.phase = "locked";
            }
        }
        onReleased: {
            if (voiceRecordButton.phase === "pressed") {
                holdTimer.stop();
                voiceRecordButton.phase = "idle";
                voiceRecordButton.tapped();
            } else if (voiceRecordButton.phase === "holding") {
                voiceRecordButton.finish(true);
            }
        }
        onClicked: {
            // Released after being locked: this tap is the send button.
            if (voiceRecordButton.phase === "locked" && !lockedInThisPress) {
                voiceRecordButton.finish(true);
            }
        }
        onCanceled: {
            holdTimer.stop();
            if (voiceRecordButton.phase === "pressed") {
                voiceRecordButton.phase = "idle";
            } else if (voiceRecordButton.phase === "holding") {
                // Lost the touch (e.g. the app went to the background): don't send by accident.
                voiceRecordButton.cancel();
            }
        }
    }
}
