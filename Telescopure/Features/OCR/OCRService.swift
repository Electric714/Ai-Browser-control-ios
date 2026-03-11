import Foundation

protocol OCRService {
    func recognizeText(from imageData: Data) async throws -> [String]
}

struct StubOCRService: OCRService {
    func recognizeText(from imageData: Data) async throws -> [String] {
        []
    }
}
