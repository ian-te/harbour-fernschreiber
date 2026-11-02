/*
    Copyright (C) 2026 Fernschreiber contributors

    This file is part of Fernschreiber and is licensed under the GNU General
    Public License v3.0 (see LICENSE).

    Records Telegram video notes ("circles"): the front camera through
    CallCameraGrabber, centre-cropped to a square, scaled to 480x480 and turned
    upright, encoded to H.264 with openh264 (Sailfish's GStreamer has no H.264
    encoder for plain memory frames), muxed with AAC audio from the microphone
    into MP4 by GStreamer. A VideoRenderer shows the frames for the round preview.
*/
#ifndef FERNSCHREIBER_VIDEONOTERECORDER_H
#define FERNSCHREIBER_VIDEONOTERECORDER_H

#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QMutex>
#include <QElapsedTimer>
#include <atomic>
#include <memory>

typedef struct _GstElement GstElement;
class ISVCEncoder;
namespace webrtc { class VideoFrame; }

namespace fernschreiber {

class CallCameraGrabber;
class VideoRenderer;

class VideoNoteRecorder : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QObject *preview READ preview CONSTANT)
    Q_PROPERTY(bool recording READ isRecording NOTIFY recordingChanged)
    Q_PROPERTY(int duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(int maximumDuration READ maximumDuration CONSTANT)

public:
    explicit VideoNoteRecorder(QObject *parent = nullptr);
    ~VideoNoteRecorder() override;

    QObject *preview() const;
    bool isRecording() const { return m_recording; }
    int duration() const { return m_durationMs.load(); }   // milliseconds
    int maximumDuration() const { return 60000; }

    Q_INVOKABLE bool start();
    // keep = false throws the recording away.
    Q_INVOKABLE void stop(bool keep);

signals:
    void recordingChanged();
    void durationChanged();
    void finished(const QString &path, int durationSeconds, int length, const QString &thumbnailPath);
    void cancelled();
    void failed(const QString &reason);

private slots:
    void poll();

private:
    void handleFrame(const webrtc::VideoFrame &frame);
    void finish(bool success, const QString &error = QString());
    void teardown();

    static const int SIZE = 480;

    CallCameraGrabber *m_grabber;
    VideoRenderer *m_renderer;
    GstElement *m_pipeline;
    GstElement *m_videoSrc;
    ISVCEncoder *m_encoder;
    QMutex m_encodeMutex;
    QTimer m_pollTimer;
    QElapsedTimer m_stopTimer;
    QString m_path;
    QString m_thumbnailPath;
    bool m_recording;
    bool m_stopping;
    bool m_keep;
    std::atomic<bool> m_acceptFrames;
    std::atomic<bool> m_thumbnailSaved;
    std::atomic<int> m_durationMs;
    std::atomic<qint64> m_firstFrameNs;
};

} // namespace fernschreiber

#endif // FERNSCHREIBER_VIDEONOTERECORDER_H
