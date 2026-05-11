#include "include/flutter_usb_camera_package/flutter_usb_camera_package_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <gst/gst.h>
#include <gst/app/gstappsink.h>

#include <string>
#include <cstring>
#include <vector>
#include <mutex>

// Linux headers for Camera/V4L2
#include <linux/videodev2.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <glob.h>

#define FLUTTER_USB_CAMERA_PACKAGE_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_usb_camera_package_plugin_get_type(), \
                              FlutterUsbCameraPackagePlugin))

// --- GstVideoTexture Object ---
#define GST_TYPE_VIDEO_TEXTURE (gst_video_texture_get_type())
G_DECLARE_FINAL_TYPE(GstVideoTexture, gst_video_texture, GST, VIDEO_TEXTURE, FlPixelBufferTexture)

struct _GstVideoTexture
{
  FlPixelBufferTexture parent_instance;
  uint8_t *buffer;
  uint32_t width;
  uint32_t height;
  GMutex mutex;
  double current_fps;
  size_t last_buffer_size;
  int frame_count;
  gint64 last_time;
};

G_DEFINE_TYPE(GstVideoTexture, gst_video_texture, fl_pixel_buffer_texture_get_type())

static void gst_video_texture_init(GstVideoTexture *self)
{
  self->buffer = nullptr;
  self->width = 0;
  self->height = 0;
  self->current_fps = 0.0;
  self->last_buffer_size = 0;
  self->frame_count = 0;
  g_mutex_init(&self->mutex);
  self->last_time = g_get_monotonic_time();
}

static void gst_video_texture_dispose(GObject *object)
{
  GstVideoTexture *self = GST_VIDEO_TEXTURE(object);
  g_mutex_lock(&self->mutex);
  if (self->buffer)
    g_free(self->buffer);
  g_mutex_unlock(&self->mutex);
  g_mutex_clear(&self->mutex);
  G_OBJECT_CLASS(gst_video_texture_parent_class)->dispose(object);
}

static gboolean gst_video_texture_copy_pixels(FlPixelBufferTexture *texture, const uint8_t **buffer, uint32_t *width, uint32_t *height, GError **error)
{
  GstVideoTexture *self = GST_VIDEO_TEXTURE(texture);
  g_mutex_lock(&self->mutex);
  if (self->width == 0 || self->height == 0 || self->buffer == nullptr)
  {
    static const uint8_t dummy_pixel[4] = {0, 0, 0, 0};
    *buffer = dummy_pixel;
    *width = 1;
    *height = 1;
    g_mutex_unlock(&self->mutex);
    return TRUE;
  }
  *buffer = self->buffer;
  *width = self->width;
  *height = self->height;
  g_mutex_unlock(&self->mutex);
  return TRUE;
}

static void gst_video_texture_class_init(GstVideoTextureClass *klass)
{
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = gst_video_texture_copy_pixels;
  G_OBJECT_CLASS(klass)->dispose = gst_video_texture_dispose;
}

// --- Plugin Implementation ---
struct _FlutterUsbCameraPackagePlugin
{
  GObject parent_instance;
  FlTextureRegistrar *texture_registrar;
  GstVideoTexture *video_texture;
  GstElement *pipeline;
  gboolean is_texture_registered;
};

G_DEFINE_TYPE(FlutterUsbCameraPackagePlugin, flutter_usb_camera_package_plugin, g_object_get_type())

static std::string fourcc_to_string(uint32_t fourcc)
{
  char buf[5];
  memcpy(buf, &fourcc, 4);
  buf[4] = '\0';
  return std::string(buf);
}

static gboolean notify_frame_available_cb(gpointer user_data)
{
  FlutterUsbCameraPackagePlugin *self = FLUTTER_USB_CAMERA_PACKAGE_PLUGIN(user_data);
  if (self->texture_registrar && self->video_texture && self->is_texture_registered)
  {
    fl_texture_registrar_mark_texture_frame_available(self->texture_registrar, FL_TEXTURE(self->video_texture));
  }
  return G_SOURCE_REMOVE;
}

static GstFlowReturn on_new_sample(GstElement *sink, gpointer user_data)
{
  FlutterUsbCameraPackagePlugin *self = FLUTTER_USB_CAMERA_PACKAGE_PLUGIN(user_data);
  GstSample *sample = gst_app_sink_pull_sample(GST_APP_SINK(sink));
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
      g_mutex_lock(&self->video_texture->mutex);
      size_t required_size = width * height * 4;
      if (map.size >= required_size)
      {
        if (self->video_texture->width != (uint32_t)width || self->video_texture->height != (uint32_t)height)
        {
          if (self->video_texture->buffer)
            g_free(self->video_texture->buffer);
          self->video_texture->buffer = (uint8_t *)g_malloc(required_size);
          self->video_texture->width = width;
          self->video_texture->height = height;
        }
        memcpy(self->video_texture->buffer, map.data, required_size);
        self->video_texture->last_buffer_size = required_size;
        self->video_texture->frame_count++;
        gint64 now = g_get_monotonic_time();
        if (now - self->video_texture->last_time >= 1000000)
        {
          self->video_texture->current_fps = (double)self->video_texture->frame_count / ((now - self->video_texture->last_time) / 1000000.0);
          self->video_texture->frame_count = 0;
          self->video_texture->last_time = now;
        }
      }
      g_mutex_unlock(&self->video_texture->mutex);
      gst_buffer_unmap(buffer, &map);
      g_idle_add(notify_frame_available_cb, self);
    }
    gst_sample_unref(sample);
  }
  return GST_FLOW_OK;
}

static void flutter_usb_camera_package_plugin_handle_method_call(FlutterUsbCameraPackagePlugin *self, FlMethodCall *method_call)
{
  const gchar *method = fl_method_call_get_name(method_call);
  FlValue *args = fl_method_call_get_args(method_call);

  if (strcmp(method, "listDevices") == 0)
  {
    glob_t glob_result;
    g_autoptr(FlValue) list = fl_value_new_list();
    if (glob("/dev/video*", 0, NULL, &glob_result) == 0)
    {
      for (size_t i = 0; i < glob_result.gl_pathc; ++i)
      {
        fl_value_append_take(list, fl_value_new_string(glob_result.gl_pathv[i]));
      }
    }
    globfree(&glob_result);
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(list)), nullptr);
  }
  else if (strcmp(method, "getCameraMetadata") == 0)
  {
    const gchar *device_path = fl_value_get_string(fl_value_lookup_string(args, "device"));
    int fd = open(device_path, O_RDWR);
    if (fd < 0)
    {
      fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_error_response_new("IO_ERROR", "Could not open device", nullptr)), nullptr);
      return;
    }
    g_autoptr(FlValue) formats_list = fl_value_new_list();
    v4l2_fmtdesc fmtdesc = {0};
    fmtdesc.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    while (ioctl(fd, VIDIOC_ENUM_FMT, &fmtdesc) == 0)
    {
      g_autoptr(FlValue) format_map = fl_value_new_map();
      fl_value_set_string_take(format_map, "format", fl_value_new_string(fourcc_to_string(fmtdesc.pixelformat).c_str()));
      g_autoptr(FlValue) res_list = fl_value_new_list();
      v4l2_frmsizeenum frmsize = {0};
      frmsize.pixel_format = fmtdesc.pixelformat;
      while (ioctl(fd, VIDIOC_ENUM_FRAMESIZES, &frmsize) == 0)
      {
        if (frmsize.type == V4L2_FRMSIZE_TYPE_DISCRETE)
        {
          g_autoptr(FlValue) res_map = fl_value_new_map();
          fl_value_set_string_take(res_map, "width", fl_value_new_int(frmsize.discrete.width));
          fl_value_set_string_take(res_map, "height", fl_value_new_int(frmsize.discrete.height));
          g_autoptr(FlValue) fps_list = fl_value_new_list();
          v4l2_frmivalenum frmival = {0};
          frmival.pixel_format = fmtdesc.pixelformat;
          frmival.width = frmsize.discrete.width;
          frmival.height = frmsize.discrete.height;
          while (ioctl(fd, VIDIOC_ENUM_FRAMEINTERVALS, &frmival) == 0)
          {
            if (frmival.type == V4L2_FRMIVAL_TYPE_DISCRETE)
              fl_value_append_take(fps_list, fl_value_new_float((double)frmival.discrete.denominator / frmival.discrete.numerator));
            frmival.index++;
          }
          fl_value_set_string_take(res_map, "fps", g_steal_pointer(&fps_list));
          fl_value_append_take(res_list, g_steal_pointer(&res_map));
        }
        frmsize.index++;
      }
      fl_value_set_string_take(format_map, "resolutions", g_steal_pointer(&res_list));
      fl_value_append_take(formats_list, g_steal_pointer(&format_map));
      fmtdesc.index++;
    }
    close(fd);
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(formats_list)), nullptr);
  }
  else if (strcmp(method, "startStream") == 0)
  {
    if (self->pipeline)
    {
      gst_element_set_state(self->pipeline, GST_STATE_NULL);
      gst_object_unref(self->pipeline);
    }
    const gchar *dev = fl_value_get_string(fl_value_lookup_string(args, "device"));
    const gchar *fmt = fl_value_get_string(fl_value_lookup_string(args, "format"));
    int w = fl_value_get_int(fl_value_lookup_string(args, "width"));
    int h = fl_value_get_int(fl_value_lookup_string(args, "height"));
    int fps = (int)fl_value_get_float(fl_value_lookup_string(args, "fps"));

    std::string caps = (std::string(fmt) == "MJPG")
                           ? "image/jpeg,width=" + std::to_string(w) + ",height=" + std::to_string(h) + ",framerate=" + std::to_string(fps) + "/1"
                           : "video/x-raw,width=" + std::to_string(w) + ",height=" + std::to_string(h) + ",framerate=" + std::to_string(fps) + "/1";

    std::string pipe_str = "v4l2src device=" + std::string(dev) + " ! " + caps + " ! " +
                           (std::string(fmt) == "MJPG" ? "jpegdec ! " : "") + "videoconvert ! video/x-raw,format=RGBA ! appsink name=mysink emit-signals=true max-buffers=1 drop=true";

    self->pipeline = gst_parse_launch(pipe_str.c_str(), nullptr);
    GstElement *sink = gst_bin_get_by_name(GST_BIN(self->pipeline), "mysink");
    g_signal_connect(sink, "new-sample", G_CALLBACK(on_new_sample), self);
    gst_object_unref(sink);

    if (!self->is_texture_registered)
    {
      fl_texture_registrar_register_texture(self->texture_registrar, FL_TEXTURE(self->video_texture));
      self->is_texture_registered = TRUE;
    }
    gst_element_set_state(self->pipeline, GST_STATE_PLAYING);
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_int((int64_t)self->video_texture))), nullptr);
  }
  else if (strcmp(method, "getPerformanceMetrics") == 0)
  {
    g_autoptr(FlValue) metrics = fl_value_new_map();
    fl_value_set_string_take(metrics, "fps", fl_value_new_float(self->video_texture->current_fps));
    fl_value_set_string_take(metrics, "width", fl_value_new_int(self->video_texture->width));
    fl_value_set_string_take(metrics, "height", fl_value_new_int(self->video_texture->height));
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(metrics)), nullptr);
  }
  else
  {
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()), nullptr);
  }
}

static void flutter_usb_camera_package_plugin_dispose(GObject *object)
{
  FlutterUsbCameraPackagePlugin *self = FLUTTER_USB_CAMERA_PACKAGE_PLUGIN(object);
  if (self->pipeline)
  {
    gst_element_set_state(self->pipeline, GST_STATE_NULL);
    gst_object_unref(self->pipeline);
  }
  if (self->video_texture)
    g_object_unref(self->video_texture);
  G_OBJECT_CLASS(flutter_usb_camera_package_plugin_parent_class)->dispose(object);
}

static void flutter_usb_camera_package_plugin_class_init(FlutterUsbCameraPackagePluginClass *klass)
{
  G_OBJECT_CLASS(klass)->dispose = flutter_usb_camera_package_plugin_dispose;
}

static void flutter_usb_camera_package_plugin_init(FlutterUsbCameraPackagePlugin *self)
{
  self->pipeline = nullptr;
  self->is_texture_registered = FALSE;
}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call, gpointer user_data)
{
  FlutterUsbCameraPackagePlugin *self = FLUTTER_USB_CAMERA_PACKAGE_PLUGIN(user_data);
  flutter_usb_camera_package_plugin_handle_method_call(self, method_call);
}

void flutter_usb_camera_package_plugin_register_with_registrar(FlPluginRegistrar *registrar)
{
  gst_init(NULL, NULL);
  FlutterUsbCameraPackagePlugin *self = FLUTTER_USB_CAMERA_PACKAGE_PLUGIN(g_object_new(flutter_usb_camera_package_plugin_get_type(), nullptr));
  self->texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);
  self->video_texture = (GstVideoTexture *)g_object_new(gst_video_texture_get_type(), nullptr);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar), "flutter_usb_camera_package", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, self, g_object_unref);
}