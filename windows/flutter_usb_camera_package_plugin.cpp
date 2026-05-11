#include "flutter_usb_camera_package_plugin.h"

// Flutter headers
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

// Windows and GStreamer headers
#include <windows.h>
#include <gst/gst.h>
#include <gst/video/video.h>
#include <gst/app/gstappsink.h>

// Standard C++ headers
#include <memory>
#include <sstream>
#include <mutex>
#include <map>
#include <vector>
#include <string>
#include <set>
#include <algorithm>

namespace flutter_usb_camera_package
{
  // --- GStreamer Frame Callback ---
  static GstFlowReturn on_new_sample(GstElement *sink, gpointer user_data)
  {
    auto *plugin = static_cast<FlutterUsbCameraPackagePlugin *>(user_data);
    GstSample *sample = nullptr;

    // Pull the sample from the appsink
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

  // --- Plugin Registration ---
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
      pipeline_ = nullptr;
    }
  }

  // --- Pixel Pushing Logic ---
  void FlutterUsbCameraPackagePlugin::UpdateFrame(const uint8_t *data, size_t size, int width, int height)
  {
    std::lock_guard<std::mutex> lock(frame_mutex_);

    // Resize buffer only when resolution changes
    if (frame_buffer_.size() != size)
    {
      frame_buffer_.resize(size);
    }
    std::memcpy(frame_buffer_.data(), data, size);

    video_width_ = width;
    video_height_ = height;
    last_buffer_size_ = size;
    frame_count_++;

    // Calculate internal performance metrics
    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - last_time_).count();
    if (elapsed >= 1000)
    {
      current_fps_ = static_cast<double>(frame_count_) / (elapsed / 1000.0);
      frame_count_ = 0;
      last_time_ = now;
    }

    // Trigger Flutter UI Redraw
    if (texture_id_ != -1)
    {
      texture_registrar_->MarkTextureFrameAvailable(texture_id_);
    }
  }

  // --- Method Channel Handling ---
  void FlutterUsbCameraPackagePlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    // 1. LIST DEVICES (Filtered for Uniqueness)
    if (method_call.method_name().compare("listDevices") == 0)
    {
      flutter::EncodableList devices;
      std::set<std::string> seen_names;

      GstDeviceMonitor *monitor = gst_device_monitor_new();
      gst_device_monitor_add_filter(monitor, "Video/Source", NULL);
      GList *gst_devices = gst_device_monitor_get_devices(monitor);

      for (GList *l = gst_devices; l != NULL; l = l->next)
      {
        GstDevice *device = (GstDevice *)l->data;
        gchar *name_raw = gst_device_get_display_name(device);
        std::string name(name_raw);

        if (seen_names.find(name) == seen_names.end())
        {
          devices.push_back(flutter::EncodableValue(name));
          seen_names.insert(name);
        }
        g_free(name_raw);
      }

      g_list_free_full(gst_devices, gst_object_unref);
      gst_object_unref(monitor);
      result->Success(flutter::EncodableValue(devices));
    }

    // 2. GET METADATA (Filtered and Normalized)
    else if (method_call.method_name().compare("getCameraMetadata") == 0)
    {
      const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
      std::string target_name = std::get<std::string>(args->at(flutter::EncodableValue("device")));

      flutter::EncodableList formats_list;
      std::set<std::string> seen_formats;
      GstDeviceMonitor *monitor = gst_device_monitor_new();
      gst_device_monitor_add_filter(monitor, "Video/Source", NULL);
      GList *gst_devices = gst_device_monitor_get_devices(monitor);

      for (GList *l = gst_devices; l != NULL; l = l->next)
      {
        GstDevice *device = (GstDevice *)l->data;
        gchar *name = gst_device_get_display_name(device);

        if (target_name == std::string(name))
        {
          GstCaps *caps = gst_device_get_caps(device);
          if (caps)
          {
            std::map<std::string, std::map<std::string, std::vector<double>>> structure_map;

            for (guint i = 0; i < gst_caps_get_size(caps); i++)
            {
              GstStructure *s = gst_caps_get_structure(caps, i);
              const gchar *raw_fmt = gst_structure_get_string(s, "format");
              if (!raw_fmt)
                raw_fmt = gst_structure_get_name(s);

              // Normalize: remove (memory:...) suffixes
              std::string fmt(raw_fmt);
              size_t bracket = fmt.find('(');
              if (bracket != std::string::npos)
                fmt = fmt.substr(0, bracket);

              int width, height;
              if (gst_structure_get_int(s, "width", &width) && gst_structure_get_int(s, "height", &height))
              {
                std::string res_key = std::to_string(width) + "x" + std::to_string(height);
                const GValue *fr = gst_structure_get_value(s, "framerate");
                if (GST_VALUE_HOLDS_FRACTION(fr))
                {
                  double fps = (double)gst_value_get_fraction_numerator(fr) / gst_value_get_fraction_denominator(fr);
                  structure_map[fmt][res_key].push_back(fps);
                }
              }
            }

            for (auto const &[fmt, res_map] : structure_map)
            {
              if (seen_formats.find(fmt) != seen_formats.end())
                continue;
              seen_formats.insert(fmt);

              flutter::EncodableMap format_entry;
              format_entry[flutter::EncodableValue("format")] = flutter::EncodableValue(fmt);
              flutter::EncodableList resolutions_list;

              for (auto const &[res, fps_vec] : res_map)
              {
                flutter::EncodableMap res_entry;
                size_t x_pos = res.find('x');
                res_entry[flutter::EncodableValue("width")] = flutter::EncodableValue(std::stoi(res.substr(0, x_pos)));
                res_entry[flutter::EncodableValue("height")] = flutter::EncodableValue(std::stoi(res.substr(x_pos + 1)));

                flutter::EncodableList fps_list;
                for (double f : fps_vec)
                  fps_list.push_back(flutter::EncodableValue(f));
                res_entry[flutter::EncodableValue("fps")] = flutter::EncodableValue(fps_list);
                resolutions_list.push_back(flutter::EncodableValue(res_entry));
              }
              format_entry[flutter::EncodableValue("resolutions")] = flutter::EncodableValue(resolutions_list);
              formats_list.push_back(flutter::EncodableValue(format_entry));
            }
            gst_caps_unref(caps);
          }
        }
        g_free(name);
      }
      g_list_free_full(gst_devices, gst_object_unref);
      gst_object_unref(monitor);
      result->Success(flutter::EncodableValue(formats_list));
    }

    // 3. START STREAM (Optimized for 4K)
    else if (method_call.method_name().compare("startStream") == 0)
    {
      const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (!args)
      {
        result->Error("INVALID_ARGS", "Arguments are not a map");
        return;
      }

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

      if (pipeline_)
      {
        gst_element_set_state(pipeline_, GST_STATE_NULL);
        gst_object_unref(pipeline_);
        pipeline_ = nullptr;
      }

      std::string caps_type = (format == "MJPG" || format == "image/jpeg") ? "image/jpeg" : "video/x-raw";

      std::stringstream ss;
      ss << "mfvideosrc device-name=\"" << device_name << "\" ! "
         << caps_type << ",width=" << width << ",height=" << height << ",framerate=" << fps << "/1 ! "
         << (caps_type == "image/jpeg" ? "jpegdec ! " : "")
         << "videoconvert ! video/x-raw,format=RGBA ! "
         << "appsink name=mysink emit-signals=true max-buffers=1 drop=true";

      GError *error = NULL;
      pipeline_ = gst_parse_launch(ss.str().c_str(), &error);

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

    // 4. PERFORMANCE METRICS
    else if (method_call.method_name().compare("getPerformanceMetrics") == 0)
    {
      flutter::EncodableMap metrics;
      metrics[flutter::EncodableValue("fps")] = flutter::EncodableValue(current_fps_);
      metrics[flutter::EncodableValue("width")] = flutter::EncodableValue(video_width_);
      metrics[flutter::EncodableValue("height")] = flutter::EncodableValue(video_height_);
      result->Success(flutter::EncodableValue(metrics));
    }
    else if (method_call.method_name().compare("stopStream") == 0)
    {
      if (pipeline_)
      {
        gst_element_set_state(pipeline_, GST_STATE_NULL); // CRITICAL: Releases hardware lock
        gst_object_unref(pipeline_);
        pipeline_ = nullptr;
      }
      result->Success();
    }
    else
    {
      result->NotImplemented();
    }
  }

} // namespace flutter_usb_camera_package