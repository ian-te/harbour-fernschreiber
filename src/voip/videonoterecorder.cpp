/*
    Copyright (C) 2026 Fernschreiber contributors

    This file is part of Fernschreiber and is licensed under the GNU General
    Public License v3.0 (see LICENSE).
*/
#include "videonoterecorder.h"
#include "callcameragrabber.h"
#include "videorenderer.h"
#include "debuglog.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QImage>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QMetaObject>
#include <algorithm>
#include <cstring>
#include <vector>

#include <gst/gst.h>
#include <gst/app/gstappsrc.h>

#include <wels/codec_api.h>

#include "libyuv.h"
#include "api/video/video_frame.h"
#include "api/video/i420_buffer.h"

namespace fernschreiber {

namespace {

QString temporaryDirectory()
{
    const QString path = QStandardPaths::writableLocation(QStandardPaths::TempLocation) + "/harbour-fernschreiber";
    QDir().mkpath(path);
    return path;
}

GstClockTime runningTime(GstElement *pipeline)
{
    GstClock *clock = gst_element_get_clock(pipeline);
    if (!clock) {
        return GST_CLOCK_TIME_NONE;
    }
    const GstClockTime now = gst_clock_get_time(clock);
    gst_object_unref(clock);
    const GstClockTime base = gst_element_get_base_time(pipeline);
    return now > base ? now - base : 0;
}

} // namespace

VideoNoteRecorder::VideoNoteRecorder(QObject *parent)
    : QObject(parent)
    , m_grabber(nullptr)
    , m_renderer(new VideoRenderer(this))
    , m_pipeline(nullptr)
    , m_videoSrc(nullptr)
    , m_encoder(nullptr)
    , m_recording(false)
    , m_stopping(false)
    , m_keep(false)
    , m_acceptFrames(false)
    , m_thumbnailSaved(false)
    , m_durationMs(0)
    , m_firstFrameNs(-1)
{
    // Frames are already upright when they reach the renderer.
    m_renderer->setFixedRotation(0);
    m_pollTimer.setInterval(50);
    connect(&m_pollTimer, &QTimer::timeout, this, &VideoNoteRecorder::poll);
}

VideoNoteRecorder::~VideoNoteRecorder()
{
    m_keep = false;
    teardown();
}

QObject *VideoNoteRecorder::preview() const
{
    return m_renderer;
}

bool VideoNoteRecorder::start()
{
    if (m_recording) {
        return false;
    }
    if (!gst_is_initialized()) {
        gst_init(nullptr, nullptr);
    }

    const QString stamp = QDateTime::currentDateTime().toString("yyyy-MM-dd-HH-mm-ss");
    m_path = temporaryDirectory() + "/videonote-" + stamp + ".mp4";
    m_thumbnailPath = temporaryDirectory() + "/videonote-" + stamp + "-thumb.jpg";

    // --- openh264 ---
    if (WelsCreateSVCEncoder(&m_encoder) != 0 || !m_encoder) {
        emit failed("Couldn't create the H.264 encoder");
        m_encoder = nullptr;
        return false;
    }
    SEncParamBase params;
    std::memset(&params, 0, sizeof(params));
    params.iUsageType = CAMERA_VIDEO_REAL_TIME;
    params.fMaxFrameRate = 30;
    params.iPicWidth = SIZE;
    params.iPicHeight = SIZE;
    params.iTargetBitrate = 1000000;
    params.iRCMode = RC_BITRATE_MODE;
    if (m_encoder->Initialize(&params) != 0) {
        WelsDestroySVCEncoder(m_encoder);
        m_encoder = nullptr;
        emit failed("Couldn't set up the H.264 encoder");
        return false;
    }
    int videoFormat = videoFormatI420;
    m_encoder->SetOption(ENCODER_OPTION_DATAFORMAT, &videoFormat);
    int idrInterval = 60;
    m_encoder->SetOption(ENCODER_OPTION_IDR_INTERVAL, &idrInterval);

    // --- GStreamer: encoded video from us + microphone AAC -> MP4 ---
    const QString description = QString(
        "appsrc name=videosrc is-live=true format=time do-timestamp=false "
        "  caps=video/x-h264,stream-format=byte-stream,alignment=au,width=%1,height=%1,framerate=0/1 "
        "  ! h264parse ! queue ! mux. "
        "pulsesrc ! audioconvert ! audioresample ! audio/x-raw,rate=48000,channels=1 "
        "  ! avenc_aac bitrate=64000 ! aacparse ! queue ! mux. "
        "mp4mux name=mux faststart=true ! filesink name=sink").arg(SIZE);
    GError *error = nullptr;
    m_pipeline = gst_parse_launch(description.toUtf8().constData(), &error);
    if (!m_pipeline || error) {
        const QString reason = error ? QString::fromUtf8(error->message) : QString("unknown error");
        LOG("Video note pipeline failed:" << reason);
        if (error) {
            g_error_free(error);
        }
        teardown();
        emit failed(reason);
        return false;
    }
    GstElement *sink = gst_bin_get_by_name(GST_BIN(m_pipeline), "sink");
    g_object_set(sink, "location", m_path.toUtf8().constData(), nullptr);
    gst_object_unref(sink);
    m_videoSrc = gst_bin_get_by_name(GST_BIN(m_pipeline), "videosrc");

    if (gst_element_set_state(m_pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        teardown();
        emit failed("Couldn't start recording");
        return false;
    }

    // --- Camera ---
    m_durationMs.store(0);
    m_firstFrameNs.store(-1);
    m_thumbnailSaved.store(false);
    m_acceptFrames.store(true);
    m_grabber = new CallCameraGrabber(this);
    m_grabber->setFrameCallback([this](const webrtc::VideoFrame &frame) { handleFrame(frame); });
    m_grabber->start(true);

    m_recording = true;
    m_stopping = false;
    m_keep = false;
    m_pollTimer.start();
    emit recordingChanged();
    emit durationChanged();
    LOG("Video note recording to" << m_path);
    return true;
}

void VideoNoteRecorder::handleFrame(const webrtc::VideoFrame &frame)
{
    if (!m_acceptFrames.load()) {
        return;
    }
    rtc::scoped_refptr<webrtc::I420BufferInterface> in = frame.video_frame_buffer()->ToI420();
    if (!in) {
        return;
    }
    const int w = in->width();
    const int h = in->height();
    const int side = std::min(w, h);
    const int x = ((w - side) / 2) & ~1;
    const int y = ((h - side) / 2) & ~1;

    // Centre square, scaled to SIZE...
    auto scaled = webrtc::I420Buffer::Create(SIZE, SIZE);
    libyuv::I420Scale(in->DataY() + y * in->StrideY() + x, in->StrideY(),
                      in->DataU() + (y / 2) * in->StrideU() + x / 2, in->StrideU(),
                      in->DataV() + (y / 2) * in->StrideV() + x / 2, in->StrideV(),
                      side, side,
                      scaled->MutableDataY(), scaled->StrideY(),
                      scaled->MutableDataU(), scaled->StrideU(),
                      scaled->MutableDataV(), scaled->StrideV(),
                      SIZE, SIZE, libyuv::kFilterBilinear);
    // ...then turned upright (the frame carries the rotation the camera needs).
    rtc::scoped_refptr<webrtc::I420Buffer> upright = scaled;
    const int rotation = int(frame.rotation());
    if (rotation != 0) {
        upright = webrtc::I420Buffer::Rotate(*scaled, frame.rotation());
    }

    // Preview.
    webrtc::VideoFrame previewFrame = webrtc::VideoFrame::Builder()
            .set_video_frame_buffer(upright)
            .set_rotation(webrtc::kVideoRotation_0)
            .set_timestamp_us(frame.timestamp_us())
            .build();
    m_renderer->sink()->OnFrame(previewFrame);

    QMutexLocker lock(&m_encodeMutex);
    if (!m_encoder || !m_videoSrc || !m_pipeline) {
        return;
    }
    const GstClockTime pts = runningTime(m_pipeline);
    if (!GST_CLOCK_TIME_IS_VALID(pts)) {
        return;
    }
    if (m_firstFrameNs.load() < 0) {
        m_firstFrameNs.store(qint64(pts));
    }
    const qint64 elapsedMs = (qint64(pts) - m_firstFrameNs.load()) / 1000000;
    m_durationMs.store(int(elapsedMs));

    if (!m_thumbnailSaved.exchange(true)) {
        QImage image(SIZE, SIZE, QImage::Format_ARGB32);
        libyuv::I420ToARGB(upright->DataY(), upright->StrideY(), upright->DataU(), upright->StrideU(),
                           upright->DataV(), upright->StrideV(), image.bits(), image.bytesPerLine(), SIZE, SIZE);
        image.scaled(320, 320, Qt::KeepAspectRatio, Qt::SmoothTransformation).save(m_thumbnailPath, "JPG", 85);
    }

    SSourcePicture picture;
    std::memset(&picture, 0, sizeof(picture));
    picture.iColorFormat = videoFormatI420;
    picture.iPicWidth = SIZE;
    picture.iPicHeight = SIZE;
    picture.iStride[0] = upright->StrideY();
    picture.iStride[1] = upright->StrideU();
    picture.iStride[2] = upright->StrideV();
    picture.pData[0] = const_cast<unsigned char *>(upright->DataY());
    picture.pData[1] = const_cast<unsigned char *>(upright->DataU());
    picture.pData[2] = const_cast<unsigned char *>(upright->DataV());
    picture.uiTimeStamp = elapsedMs;

    SFrameBSInfo info;
    std::memset(&info, 0, sizeof(info));
    if (m_encoder->EncodeFrame(&picture, &info) != cmResultSuccess || info.eFrameType == videoFrameTypeSkip) {
        return;
    }
    gsize total = 0;
    for (int i = 0; i < info.iLayerNum; ++i) {
        const SLayerBSInfo &layer = info.sLayerInfo[i];
        for (int n = 0; n < layer.iNalCount; ++n) {
            total += layer.pNalLengthInByte[n];
        }
    }
    if (total == 0) {
        return;
    }
    GstBuffer *buffer = gst_buffer_new_allocate(nullptr, total, nullptr);
    GstMapInfo map;
    gst_buffer_map(buffer, &map, GST_MAP_WRITE);
    gsize offset = 0;
    for (int i = 0; i < info.iLayerNum; ++i) {
        const SLayerBSInfo &layer = info.sLayerInfo[i];
        gsize layerSize = 0;
        for (int n = 0; n < layer.iNalCount; ++n) {
            layerSize += layer.pNalLengthInByte[n];
        }
        std::memcpy(map.data + offset, layer.pBsBuf, layerSize);
        offset += layerSize;
    }
    gst_buffer_unmap(buffer, &map);
    GST_BUFFER_PTS(buffer) = pts;
    GST_BUFFER_DTS(buffer) = pts;
    if (info.eFrameType != videoFrameTypeIDR && info.eFrameType != videoFrameTypeI) {
        GST_BUFFER_FLAG_SET(buffer, GST_BUFFER_FLAG_DELTA_UNIT);
    }
    gst_app_src_push_buffer(GST_APP_SRC(m_videoSrc), buffer);   // takes ownership

    if (elapsedMs >= maximumDuration()) {
        // Telegram's limit; stop like the official apps do, keeping what we have.
        QMetaObject::invokeMethod(this, "stop", Qt::QueuedConnection, Q_ARG(bool, true));
    }
}

void VideoNoteRecorder::stop(bool keep)
{
    if (!m_recording || m_stopping) {
        return;
    }
    LOG("Video note stop, keep:" << keep << "duration" << m_durationMs.load());
    m_stopping = true;
    m_keep = keep;
    m_acceptFrames.store(false);
    if (m_grabber) {
        m_grabber->setFrameCallback(nullptr);
        m_grabber->stop();
        m_grabber->deleteLater();
        m_grabber = nullptr;
    }
    m_renderer->reset();
    {
        QMutexLocker lock(&m_encodeMutex);
        if (m_videoSrc) {
            gst_app_src_end_of_stream(GST_APP_SRC(m_videoSrc));
        }
    }
    // The microphone is a live source: it needs its own EOS for mp4mux to finish.
    if (m_pipeline) {
        gst_element_send_event(m_pipeline, gst_event_new_eos());
    }
    m_stopTimer.start();
}

void VideoNoteRecorder::poll()
{
    if (!m_pipeline) {
        m_pollTimer.stop();
        return;
    }
    if (!m_stopping) {
        emit durationChanged();
    }
    GstBus *bus = gst_element_get_bus(m_pipeline);
    GstMessage *message;
    while ((message = gst_bus_pop_filtered(bus, GstMessageType(GST_MESSAGE_EOS | GST_MESSAGE_ERROR)))) {
        if (GST_MESSAGE_TYPE(message) == GST_MESSAGE_EOS) {
            gst_message_unref(message);
            gst_object_unref(bus);
            finish(true);
            return;
        }
        GError *error = nullptr;
        gchar *debug = nullptr;
        gst_message_parse_error(message, &error, &debug);
        const QString reason = error ? QString::fromUtf8(error->message) : QString("GStreamer error");
        LOG("Video note pipeline error:" << reason << (debug ? debug : ""));
        if (error) g_error_free(error);
        g_free(debug);
        gst_message_unref(message);
        gst_object_unref(bus);
        finish(false, reason);
        return;
    }
    gst_object_unref(bus);
    if (m_stopping && m_stopTimer.elapsed() > 4000) {
        LOG("Video note: no EOS within 4 s");
        finish(false, "Recording didn't finish in time");
    }
}

void VideoNoteRecorder::finish(bool success, const QString &error)
{
    const bool keep = m_keep && m_stopping;
    const int durationMs = m_durationMs.load();
    teardown();
    if (success && keep && durationMs >= 1000 && QFile(m_path).size() > 0) {
        emit finished(m_path, qMax(1, int((durationMs + 500) / 1000)), SIZE,
                      QFile::exists(m_thumbnailPath) ? m_thumbnailPath : QString());
    } else {
        QFile::remove(m_path);
        QFile::remove(m_thumbnailPath);
        if (success || keep == false) {
            emit cancelled();
        } else {
            emit failed(error);
        }
    }
}

void VideoNoteRecorder::teardown()
{
    m_pollTimer.stop();
    m_acceptFrames.store(false);
    if (m_grabber) {
        m_grabber->setFrameCallback(nullptr);
        m_grabber->stop();
        m_grabber->deleteLater();
        m_grabber = nullptr;
    }
    {
        QMutexLocker lock(&m_encodeMutex);
        if (m_pipeline) {
            gst_element_set_state(m_pipeline, GST_STATE_NULL);
        }
        if (m_videoSrc) {
            gst_object_unref(m_videoSrc);
            m_videoSrc = nullptr;
        }
        if (m_pipeline) {
            gst_object_unref(m_pipeline);
            m_pipeline = nullptr;
        }
        if (m_encoder) {
            m_encoder->Uninitialize();
            WelsDestroySVCEncoder(m_encoder);
            m_encoder = nullptr;
        }
    }
    const bool wasRecording = m_recording;
    m_recording = false;
    m_stopping = false;
    if (wasRecording) {
        emit recordingChanged();
    }
}

} // namespace fernschreiber
