import Foundation

class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private var frameDropCount = 0
    private var lastMemoryCheck = Date()
    
    private let memoryCriticalThreshold: UInt64 = 49 * 1024 * 1024 // 49MB
    
    private init() {}
    
    func checkMemoryUsage() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastMemoryCheck) > 5.0 else { return true }
        lastMemoryCheck = now
        
        let memoryUsage = getCurrentMemoryUsage()
        
        if memoryUsage > memoryCriticalThreshold {
            return false
        }
        
        return true
    }
    
    private func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        } else {
            return 0
        }
    }
    
    
    func recordFrameDrop() {
        frameDropCount += 1
    }
}