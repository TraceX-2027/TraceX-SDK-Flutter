import Flutter
import UIKit
import Mach

public class TracexPlugin: NSObject, FlutterPlugin {

    private var channel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "tracex/environment",
            binaryMessenger: registrar.messenger()
        )
        let instance = TracexPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getEnvironmentInfo":
            result(Self.getEnvironmentInfo())
        case "getMemoryInfo":
            result(Self.getMemoryInfo())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Full Environment Info

    private static func getEnvironmentInfo() -> [String: Any] {
        let mem = getMemoryInfo()

        // Battery
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawBat = UIDevice.current.batteryLevel
        let batteryLevel = rawBat >= 0 ? Int(rawBat * 100) : -1

        // App Version
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let appVersion = "\(shortVersion)+\(buildNumber)"

        // Device Model via utsname
        var systemInfo = utsname()
        uname(&systemInfo)
       let deviceModel = withUnsafeBytes(of: &systemInfo.machine) { raw in
       guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else {
       return "Unknown"
       }
    return String(cString: base)
}
        let osVersion = UIDevice.current.systemVersion

        #if targetEnvironment(simulator)
        let isPhysicalDevice = false
        #else
        let isPhysicalDevice = true
        #endif

        return [
            "totalRamMb": mem["totalRamMb"] as? Int ?? 0,
            "freeRamMb": mem["freeRamMb"] as? Int ?? 0,
            "isLowMemory": mem["isLowMemory"] as? Bool ?? false,
            "batteryLevel": batteryLevel,
            "appVersion": appVersion,
            "deviceModel": deviceModel,
            "osVersion": osVersion,
            "isPhysicalDevice": isPhysicalDevice
        ]
    }

    // MARK: - Memory

    private static func getMemoryInfo() -> [String: Any] {
        let totalRamBytes = ProcessInfo.processInfo.physicalMemory
        let totalRamMb = Int(totalRamBytes / 1024 / 1024)

        let freeRamBytes = getFreeMemory()
        let freeRamMb = Int(freeRamBytes / 1024 / 1024)
        let isLowMemory = freeRamMb < 200

        return [
            "totalRamMb": totalRamMb,
            "freeRamMb": freeRamMb,
            "isLowMemory": isLowMemory
        ]
    }

    private static func getFreeMemory() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        if result != KERN_SUCCESS {
            return 0
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let freePages = UInt64(stats.free_count)
        let inactivePages = UInt64(stats.inactive_count)
        return (freePages + inactivePages) * pageSize
    }
}