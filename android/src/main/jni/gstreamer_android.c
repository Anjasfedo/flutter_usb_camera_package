#include <jni.h>
#include <gst/gst.h>

void gst_android_init(JNIEnv *env, jobject context);

JNIEXPORT void JNICALL
Java_com_example_flutter_1usb_1camera_1package_FlutterUsbCameraPackagePlugin_nativeInit(JNIEnv *env, jobject thiz)
{
    gst_android_init(env, thiz);
}