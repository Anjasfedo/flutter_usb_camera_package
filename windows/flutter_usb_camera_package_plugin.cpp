#include "flutter_usb_camera_package_plugin.h"

// Flutter headers for the Method Channel and Data Types
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <windows.h>
#include <gst/gst.h>
#include <gst/video/video.h>
#include <gst/app/gstappsink.h>

#include <memory>
#include <sstream>
#include <mutex>
#include <map>
#include <vector>
#include <string>

namespace flutter_usb_camera_package
{

  // Callback for GStreamer frames
  static GstFlowReturn on_new_sample(GstElement *sink, gpointer user_data)
  {
    auto *plugin = static_cast<FlutterUsbCameraPackagePlugin *>(user_data);
    GstSample *sample = nullptr;
    g_signal_emit_by_name(sink, "pull-sample", &sample);

    if (sample)
    {
      GstBuffer *buffer = gst_sample_get_buffer(sample);
      GstCaps *caps = gst_sample_get_caps(sample);
      GstStructure *s = gst_caps_get_structure(caps, 0);

      int width, height;
      gst_structure_get_int(s, "width", &width);
      gst_structure_get_int(s, "height", &height);

      GstMapInfo map;
      if (gst_buffer_map(buffer, &map, GST_MAP_READ))
      {
        plugin->UpdateFrame(map.data, map.size, width, height);
        gst_buffer_unmap(buffer, &map);
      }
      gst_sample_unref(sample);
    }
    return GST_FLOW_OK;
  }

  void FlutterUsbCameraPackagePlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar)
  {
    auto plugin = std::make_unique<FlutterUsbCameraPackagePlugin>(registrar->texture_registrar());

    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), "flutter_usb_camera_package",
        &flutter::StandardMethodCodec::GetInstance());

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  FlutterUsbCameraPackagePlugin::FlutterUsbCameraPackagePlugin(flutter::TextureRegistrar *textures)
      : texture_registrar_(textures), last_time_(std::chrono::steady_clock::now())
  {
    gst_init(NULL, NULL);
  }

  FlutterUsbCameraPackagePlugin::~FlutterUsbCameraPackagePlugin()
  {
    if (pipeline_)
    {
      gst_element_set_state(pipeline_, GST_STATE_NULL);
      gst_object_unref(pipeline_);
    }
  }

  void FlutterUsbCameraPackagePlugin::UpdateFrame(const uint8_t *data, size_t size, int width, int height)
  {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    if (frame_buffer_.size() != size)
      frame_buffer_.resize(size);
    std::memcpy(frame_buffer_.data(), data, size);

    video_width_ = width;
    video_height_ = height;
    last_buffer_size_ = size;
    frame_count_++;

    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - last_time_).count();
    if (elapsed >= 1000)
    {
      current_fps_ = static_cast<double>(frame_count_) / (elapsed / 1000.0);
      frame_count_ = 0;
      last_time_ = now;
    }

    if (texture_id_ != -1)
      texture_registrar_->MarkTextureFrameAvailable(texture_id_);
  }

  void FlutterUsbCameraPackagePlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {

    if (method_call.method_name().compare("listDevices") == 0)
    {
      flutter::EncodableList devices;
      GstDeviceMonitor *monitor = gst_device_monitor_new();
      gst_device_monitor_add_filter(monitor, "Video/Source", NULL);
      GList *gst_devices = gst_device_monitor_get_devices(monitor);

      for (GList *l = gst_devices; l != NULL; l = l->next)
      {
        GstDevice *device = (GstDevice *)l->data;
        gchar *name = gst_device_get_display_name(device);
        devices.push_back(flutter::EncodableValue(std::string(name)));
        g_free(name);
      }
      g_list_free_full(gst_devices, gst_object_unref);
      gst_object_unref(monitor);
      result->Success(flutter::EncodableValue(devices));
    }
    else if (method_call.method_name().compare("startStream") == 0)
    {
      const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (!args)
      {
        result->Error("INVALID_ARGS", "Arguments are not a map");
        return;
      }

      // Safely extract parameters
      std::string device_name = std::get<std::string>(args->at(flutter::EncodableValue("device")));
      std::string format = std::get<std::string>(args->at(flutter::EncodableValue("format")));
      int width = std::get<int>(args->at(flutter::EncodableValue("width")));
      int height = std::get<int>(args->at(flutter::EncodableValue("height")));
      double fps_raw = std::get<double>(args->at(flutter::EncodableValue("fps")));
      int fps = static_cast<int>(fps_raw);

      if (texture_id_ == -1)
      {
        texture_ = std::make_unique<flutter::TextureVariant>(
            flutter::PixelBufferTexture([this](size_t w, size_t h) -> const FlutterDesktopPixelBuffer *
                                        {
            std::lock_guard<std::mutex> lock(this->frame_mutex_);
            if (this->frame_buffer_.empty()) return nullptr;
            this->flutter_pixel_buffer_.buffer = this->frame_buffer_.data();
            this->flutter_pixel_buffer_.width = this->video_width_;
            this->flutter_pixel_buffer_.height = this->video_height_;
            return &this->flutter_pixel_buffer_; }));
        texture_id_ = texture_registrar_->RegisterTexture(texture_.get());
      }

      // Windows Pipeline using mfvideosrc (Media Foundation)
      std::string pipe_str = "mfvideosrc ! video/x-raw,width=" + std::to_string(width) +
                             ",height=" + std::to_string(height) + ",framerate=" + std::to_string(fps) + "/1 ! " +
                             "videoconvert ! video/x-raw,format=RGBA ! appsink name=mysink emit-signals=true";

      if (pipeline_)
      {
        gst_element_set_state(pipeline_, GST_STATE_NULL);
        gst_object_unref(pipeline_);
      }

      GError *error = NULL;
      pipeline_ = gst_parse_launch(pipe_str.c_str(), &error);

      if (error)
      {
        result->Error("GSTREAMER_ERROR", error->message);
        g_error_free(error);
        return;
      }

      GstElement *sink = gst_bin_get_by_name(GST_BIN(pipeline_), "mysink");
      g_signal_connect(sink, "new-sample", G_CALLBACK(on_new_sample), this);
      gst_object_unref(sink);

      gst_element_set_state(pipeline_, GST_STATE_PLAYING);
      result->Success(flutter::EncodableValue(texture_id_));
    }
    else if (method_call.method_name().compare("getPerformanceMetrics") == 0)
    {
      flutter::EncodableMap metrics;
      metrics[flutter::EncodableValue("fps")] = flutter::EncodableValue(current_fps_);
      metrics[flutter::EncodableValue("width")] = flutter::EncodableValue(video_width_);
      metrics[flutter::EncodableValue("height")] = flutter::EncodableValue(video_height_);
      result->Success(flutter::EncodableValue(metrics));
    }
    else
    {
      result->NotImplemented();
    }
  }

} // namespace flutter_usb_camera_package