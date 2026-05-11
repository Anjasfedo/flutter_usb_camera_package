#include <gst/gst.h>
#include <gst/video/videooverlay.h>
#include <android/native_window_jni.h>
#include <android/log.h>
#include <jni.h>

#define TAG "USB_ENGINE"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

GstElement *pipeline = NULL;

// 1. Initialize Pipeline
JNIEXPORT void JNICALL
Java_com_example_flutter_1usb_1camera_1package_FlutterUsbCameraPackagePlugin_nativeStart(
    JNIEnv *env, jobject thiz, jstring device_path, jstring format, jint width, jint height, jint fps, jobject surface)
{
    // Stop existing if running
    if (pipeline)
    {
        gst_element_set_state(pipeline, GST_STATE_NULL);
        gst_object_unref(pipeline);
    }

    const char *path = (*env)->GetStringUTFChars(env, device_path, 0);
    const char *fmt = (*env)->GetStringUTFChars(env, format, 0);
    ANativeWindow *native_window = ANativeWindow_fromSurface(env, surface);

    // Build the 4K optimized pipeline
    // We use glimagesink for zero-copy rendering to the Flutter Surface
    gchar *desc = g_strdup_printf(
        "v4l2src device=%s io-mode=4 ! "
        "video/x-raw,width=%d,height=%d,framerate=%d/1 ! "
        "videoconvert ! video/x-raw,format=RGBA ! glimagesink name=sink",
        path, width, height, fps);

    LOGI("Launching pipeline: %s", desc);
    pipeline = gst_parse_launch(desc, NULL);
    g_free(desc);

    // Attach the Flutter Surface to the GStreamer Sink
    GstElement *sink = gst_bin_get_by_name(GST_BIN(pipeline), "sink");
    gst_video_overlay_set_window_handle(GST_VIDEO_OVERLAY(sink), (guintptr)native_window);
    gst_object_unref(sink);

    gst_element_set_state(pipeline, GST_STATE_PLAYING);

    (*env)->ReleaseStringUTFChars(env, device_path, path);
    (*env)->ReleaseStringUTFChars(env, format, fmt);
}

// 2. Stop Pipeline
JNIEXPORT void JNICALL
Java_com_example_flutter_1usb_1camera_1package_FlutterUsbCameraPackagePlugin_nativeStop(JNIEnv *env, jobject thiz)
{
    if (pipeline)
    {
        LOGI("Stopping pipeline...");
        gst_element_set_state(pipeline, GST_STATE_NULL);
        gst_object_unref(pipeline);
        pipeline = NULL;
    }
}

// 3. Get Metadata (Simplified for now to prevent crashes)
JNIEXPORT jobject JNICALL
Java_com_example_flutter_1usb_1camera_1package_FlutterUsbCameraPackagePlugin_nativeGetMetadata(JNIEnv *env, jobject thiz, jstring path)
{
    // For now, return an empty list to keep the UI running.
    // Probing caps on Android requires the pipeline to be in READY state.
    jclass array_list_class = (*env)->FindClass(env, "java/util/ArrayList");
    jmethodID constructor = (*env)->GetMethodID(env, array_list_class, "<init>", "()V");
    return (*env)->NewObject(env, array_list_class, constructor);
}