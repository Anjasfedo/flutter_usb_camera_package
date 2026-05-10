#ifndef FLUTTER_PLUGIN_FLUTTER_USB_CAMERA_PACKAGE_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_USB_CAMERA_PACKAGE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/texture_registrar.h>
#include <gst/gst.h>

#include <memory>
#include <mutex>
#include <vector>
#include <chrono>

namespace flutter_usb_camera_package
{

    class FlutterUsbCameraPackagePlugin : public flutter::Plugin
    {
    public:
        static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

        FlutterUsbCameraPackagePlugin(flutter::TextureRegistrar *textures);
        virtual ~FlutterUsbCameraPackagePlugin();

        void HandleMethodCall(
            const flutter::MethodCall<flutter::EncodableValue> &method_call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

        void UpdateFrame(const uint8_t *data, size_t size, int width, int height);

    private:
        flutter::TextureRegistrar *texture_registrar_;
        int64_t texture_id_ = -1;
        std::unique_ptr<flutter::TextureVariant> texture_;

        // GStreamer state
        GstElement *pipeline_ = nullptr;

        // Frame Data
        std::mutex frame_mutex_;
        std::vector<uint8_t> frame_buffer_;
        int video_width_ = 0;
        int video_height_ = 0;
        FlutterDesktopPixelBuffer flutter_pixel_buffer_{};

        // Metrics
        double current_fps_ = 0.0;
        size_t last_buffer_size_ = 0;
        int frame_count_ = 0;
        std::chrono::steady_clock::time_point last_time_;
    };

} // namespace flutter_usb_camera_package

#endif // FLUTTER_PLUGIN_FLUTTER_USB_CAMERA_PACKAGE_PLUGIN_H_