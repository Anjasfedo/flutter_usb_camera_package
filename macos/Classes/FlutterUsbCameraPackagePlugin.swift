import Cocoa
import FlutterMacOS
import AVFoundation
import CoreVideo

public class FlutterUsbCameraPackagePlugin: NSObject, FlutterPlugin {
    private var registrar: FlutterPluginRegistrar
    private var textureRegistry: FlutterTextureRegistry
    private var activeCamera: UsbCameraEngine?
    
    public init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        self.textureRegistry = registrar.textures
        super.init()
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_usb_camera_package", binaryMessenger: registrar.messenger)
        let instance = FlutterUsbCameraPackagePlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "listDevices":
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
                mediaType: .video,
                position: .unspecified
            )
            let devices = discoverySession.devices.map { $0.uniqueID }
            result(devices)
            
        case "getCameraMetadata":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["device"] as? String,
                  let device = AVCaptureDevice(uniqueID: deviceId) else {
                result([])
                return
            }
            
            var resolutions: [[String: Any]] = []
            for format in device.formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                var fpsList: [Double] = []
                for range in format.videoSupportedFrameRateRanges {
                    fpsList.append(range.maxFrameRate)
                }
                
                resolutions.append([
                    "width": Int(dimensions.width),
                    "height": Int(dimensions.height),
                    "fps": fpsList
                ])
            }
            
            let metadata = [
                [
                    "format": "AVFoundation_Native",
                    "resolutions": resolutions
                ]
            ]
            result(metadata)
            
        case "startStream":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["device"] as? String,
                  let widthNum = args["width"] as? NSNumber,
                  let heightNum = args["height"] as? NSNumber,
                  let fpsNum = args["fps"] as? NSNumber else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
                return
            }
            
            let width = widthNum.intValue
            let height = heightNum.intValue
            let fps = fpsNum.doubleValue
            
            stopActiveStream()
            
            // FIX 1: Push ALL heavy hardware initialization to a background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                do {
                    let camera = try UsbCameraEngine(
                        deviceId: deviceId,
                        targetWidth: width,
                        targetHeight: height,
                        targetFps: fps
                    )
                    
                    // Flutter Textures MUST be registered on the Main Thread
                    DispatchQueue.main.sync {
                        camera.register(with: self.textureRegistry)
                    }
                    
                    // Start the physical hardware (This takes 1-2 seconds, keep it in background!)
                    camera.start()
                    
                    // Return the successful texture ID to Dart on the Main Thread
                    DispatchQueue.main.async {
                        self.activeCamera = camera
                        result(camera.textureId)
                    }
                    
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "CAMERA_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }
            
        case "stopStream":
            stopActiveStream()
            result(nil)
            
        case "getPerformanceMetrics":
            if let camera = activeCamera {
                result([
                    "fps": camera.currentFps,
                    "width": camera.currentWidth,
                    "height": camera.currentHeight
                ])
            } else {
                result(["fps": 0.0, "width": 0, "height": 0])
            }
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func stopActiveStream() {
        activeCamera?.stop()
        activeCamera = nil
    }
}

// MARK: - Core Camera Engine & Texture Bridge

class UsbCameraEngine: NSObject, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "usb_camera_capture_queue")
    
    private var registry: FlutterTextureRegistry?
    public var textureId: Int64 = -1
    
    private var latestPixelBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()
    
    public var currentWidth: Int = 0
    public var currentHeight: Int = 0
    public var currentFps: Double = 0.0
    private var frameCount: Int = 0
    private var lastFpsTime = Date()
    
    init(deviceId: String, targetWidth: Int, targetHeight: Int, targetFps: Double) throws {
        super.init()
        
        guard let device = AVCaptureDevice(uniqueID: deviceId) else {
            throw NSError(domain: "UsbCamera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Device not found"])
        }
        
        let input = try AVCaptureDeviceInput(device: device)
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        try device.lockForConfiguration()
        var bestFormat: AVCaptureDevice.Format?
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            if dimensions.width == Int32(targetWidth) && dimensions.height == Int32(targetHeight) {
                bestFormat = format
                break
            }
        }
        
        if let format = bestFormat {
            device.activeFormat = format
            
            // FIX 2: Find the exact hardware-supported framerate duration to avoid silent crashes
            for range in format.videoSupportedFrameRateRanges {
                if abs(range.maxFrameRate - targetFps) < 1.0 { // Safe matching margin
                    device.activeVideoMinFrameDuration = range.minFrameDuration
                    device.activeVideoMaxFrameDuration = range.minFrameDuration
                    break
                }
            }
            
            currentWidth = targetWidth
            currentHeight = targetHeight
        }
        device.unlockForConfiguration()
    }
    
    func register(with registry: FlutterTextureRegistry) {
        self.registry = registry
        self.textureId = registry.register(self)
    }
    
    func start() {
        captureSession.startRunning()
    }
    
    func stop() {
        captureSession.stopRunning()
        if let reg = registry, textureId != -1 {
            reg.unregisterTexture(textureId)
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        bufferLock.lock()
        latestPixelBuffer = pixelBuffer
        bufferLock.unlock()
        
        // Notify Flutter on the Main Thread that a frame is ready
        if textureId != -1 {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.registry?.textureFrameAvailable(self.textureId)
            }
        }
        
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFpsTime)
        if elapsed >= 1.0 {
            currentFps = Double(frameCount) / elapsed
            frameCount = 0
            lastFpsTime = now
        }
    }
    
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        
        guard let pixelBuffer = latestPixelBuffer else { return nil }
        return Unmanaged.passRetained(pixelBuffer)
    }
}