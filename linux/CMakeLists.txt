cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "flutter_usb_camera_package")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "flutter_usb_camera_package_plugin")

list(APPEND PLUGIN_SOURCES
  "flutter_usb_camera_package_plugin.cc"
)

add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# --- Modern GStreamer Linking ---
find_package(PkgConfig REQUIRED)
# We include gobject and glib explicitly as they are required for the GType system
pkg_check_modules(GSTREAMER REQUIRED IMPORTED_TARGET 
  gstreamer-1.0 
  gstreamer-video-1.0 
  gstreamer-app-1.0
  gobject-2.0
  glib-2.0
)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GSTREAMER)

set(flutter_usb_camera_package_bundled_libraries
  ""
  PARENT_SCOPE
)