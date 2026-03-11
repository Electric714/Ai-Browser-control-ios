import Foundation

protocol BarcodeScannerService {
    func startScanning() async throws -> String
}

struct StubBarcodeScannerService: BarcodeScannerService {
    func startScanning() async throws -> String {
        throw NSError(domain: "WebPuppet", code: -1, userInfo: [NSLocalizedDescriptionKey: "Barcode scanner scaffolded. Implement AVFoundation capture pipeline."])
    }
}
