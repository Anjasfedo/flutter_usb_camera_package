package com.example.flutter_usb_camera_package

import android.content.Context
import android.hardware.usb.UsbManager
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import org.freedesktop.gstreamer.GStreamer
import java.io.File

class FlutterUsbCameraPackagePlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context
    private var textureRegistry: TextureRegistry? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null

    companion object {
        init {
            System.loadLibrary("usb_camera_engine")
        }
    }

    private external fun nativeGetMetadata(path: String): List<Map<String, Any>>
    private external fun nativeStart(path: String, format: String, width: Int, height: Int, fps: Int, surface: Surface): Long
    private external fun nativeStop()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_usb_camera_package")
        channel.setMethodCallHandler(this)
        textureRegistry = flutterPluginBinding.textureRegistry
        applicationContext = flutterPluginBinding.applicationContext
        
        try {
            GStreamer.init(applicationContext)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "listDevices" -> {
                val usbManager = applicationContext.getSystemService(Context.USB_SERVICE) as UsbManager
                val deviceList = usbManager.deviceList
                val devices = mutableListOf<String>()

                for ((deviceName, device) in deviceList) {
                    val deviceInfo = "Device: $deviceName | Vendor: ${device.vendorId} | Product: ${device.productId}"
                    devices.add(deviceInfo)
                    println("USB DETECTED: $deviceInfo")
                }

                if (devices.isEmpty()) {
                    devices.add("No USB devices detected by UsbManager.")
                }

                result.success(devices)
            }

            "getCameraMetadata" -> {
                val path = call.argument<String>("device") ?: ""
                result.success(nativeGetMetadata(path))
            }

            "startStream" -> {
                val path = call.argument<String>("device") ?: ""
                val format = call.argument<String>("format") ?: "YUY2"
                val width = call.argument<Int>("width") ?: 1920
                val height = call.argument<Int>("height") ?: 1080
                val fps = (call.argument<Double>("fps") ?: 30.0).toInt()

                textureEntry = textureRegistry?.createSurfaceTexture()
                val surfaceTexture = textureEntry?.surfaceTexture()
                
                surfaceTexture?.setDefaultBufferSize(width, height)
                surface = Surface(surfaceTexture)

                nativeStart(path, format, width, height, fps, surface!!)
                
                result.success(textureEntry?.id())
            }

            "stopStream" -> {
                nativeStop()
                surface?.release()
                textureEntry?.release()
                surface = null
                textureEntry = null
                result.success(null)
            }

            "getPerformanceMetrics" -> {
                val metrics = mapOf("fps" to 0.0, "width" to 0, "height" to 0)
                result.success(metrics)
            }

            else -> result.notImplemented()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {}
    override fun onDetachedFromActivityForConfigChanges() {}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}
    override fun onDetachedFromActivity() {}

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        nativeStop()
    }
}