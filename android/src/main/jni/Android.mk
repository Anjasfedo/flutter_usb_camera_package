LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE    := usb_camera_engine
LOCAL_SRC_FILES := usb_camera_engine.c 
LOCAL_SHARED_LIBRARIES := gstreamer_android
LOCAL_LDLIBS := -landroid -lGLESv2 -llog

include $(BUILD_SHARED_LIBRARY)

# 1. Map Android ABIs to GStreamer folder names
ifeq ($(TARGET_ARCH_ABI),armeabi-v7a)
    GST_ARCH := armv7
else ifeq ($(TARGET_ARCH_ABI),arm64-v8a)
    GST_ARCH := arm64
else ifeq ($(TARGET_ARCH_ABI),x86)
    GST_ARCH := x86
else ifeq ($(TARGET_ARCH_ABI),x86_64)
    GST_ARCH := x86_64
endif

GSTREAMER_ROOT := $(GSTREAMER_ROOT_ANDROID)/$(GST_ARCH)
GSTREAMER_NDK_BUILD_PATH := $(GSTREAMER_ROOT)/share/gst-android/ndk-build

# 2. THE PATH GUARANTEER (Updated filename)
ifeq ($(wildcard $(GSTREAMER_NDK_BUILD_PATH)/gstreamer-1.0.mk),)
$(error GSTREAMER PATH ERROR: Could not find $(GSTREAMER_NDK_BUILD_PATH)/gstreamer-1.0.mk)
endif

# 3. PLUGINS
GSTREAMER_PLUGINS         := coreelements videoconvertscale autodetect androidmedia opengl app
GSTREAMER_EXTRA_DEPS      := gstreamer-video-1.0 gstreamer-gl-1.0

# 4. Include the GStreamer build system (Updated filename)
include $(GSTREAMER_NDK_BUILD_PATH)/gstreamer-1.0.mk