cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "flutter_usb_camera_package")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "flutter_usb_camera_package_plugin")

# --- GStreamer Configuration (Based on your reference) ---
set(GSTREAMER_ROOT "$ENV{GSTREAMER_1_0_ROOT_MSVC_X86_64}")
if(NOT GSTREAMER_ROOT)
    message(FATAL_ERROR "GStreamer MSVC SDK not found. Please set GSTREAMER_1_0_ROOT_MSVC_X86_64")
endif()

file(TO_CMAKE_PATH "${GSTREAMER_ROOT}" GST_ROOT)

list(APPEND PLUGIN_SOURCES
  "flutter_usb_camera_package_plugin.cpp"
  "flutter_usb_camera_package_plugin.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/flutter_usb_camera_package/flutter_usb_camera_package_plugin_c_api.h"
  "flutter_usb_camera_package_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Include directories from your reference
target_include_directories(${PLUGIN_NAME} PRIVATE
    "${GST_ROOT}/include/gstreamer-1.0"
    "${GST_ROOT}/include/glib-2.0"
    "${GST_ROOT}/lib/glib-2.0/include"
    "${CMAKE_CURRENT_SOURCE_DIR}"
)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# Link libraries from your reference + video/app libs
target_link_libraries(${PLUGIN_NAME} PRIVATE 
    "${GST_ROOT}/lib/gstreamer-1.0.lib"
    "${GST_ROOT}/lib/gobject-2.0.lib"
    "${GST_ROOT}/lib/glib-2.0.lib"
    "${GST_ROOT}/lib/gstvideo-1.0.lib"
    "${GST_ROOT}/lib/gstapp-1.0.lib"
)