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

        registrar.addMethodCallDelegate(
            instance,
            channel: channel
        )
    }

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {

        switch call.method {

        case "getMemoryInfo":
            result(Self.getMemoryInfo())

        case "getBatteryLevel":
            result(Self.getBatteryLevel())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Memory

    private static func getMemoryInfo() -> [String: Any] {

        // Total RAM
        let totalRamBytes =
            ProcessInfo.processInfo.physicalMemory

        let totalRamMb = Int(
            totalRamBytes / 1024 / 1024
        )

        // Free RAM
        let freeRamBytes = getFreeMemory()

        let freeRamMb = Int(
            freeRamBytes / 1024 / 1024
        )

        // Low Memory
        let isLowMemory = freeRamMb < 200

        return [
            "totalRamMb": totalRamMb,
            "freeRamMb": freeRamMb,
            "isLowMemory": isLowMemory
        ]
    }

    // MARK: - Free Memory

    private static func getFreeMemory() -> UInt64 {

        var stats = vm_statistics64()

        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size
            / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stats) {

            $0.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) {

                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    $0,
                    &count
                )
            }
        }

        if result != KERN_SUCCESS {
            return 0
        }

        let pageSize = UInt64(vm_kernel_page_size)

        let freePages = UInt64(stats.free_count)

        let inactivePages =
            UInt64(stats.inactive_count)

        let freeMemory =
            (freePages + inactivePages) * pageSize

        return freeMemory
    }

    // MARK: - Battery

    private static func getBatteryLevel() -> Int {

        UIDevice.current.isBatteryMonitoringEnabled = true

        let batteryLevel =
            UIDevice.current.batteryLevel

        // Simulator / unavailable
        if batteryLevel < 0 {
            return -1
        }

        return Int(batteryLevel * 100)
    }
}