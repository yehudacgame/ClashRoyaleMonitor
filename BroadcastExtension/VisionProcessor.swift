import Vision
import CoreImage

class VisionProcessor {
    private let textRecognitionRequest: VNRecognizeTextRequest
    private let performanceMonitor = PerformanceMonitor.shared
    
    init() {
        textRecognitionRequest = VNRecognizeTextRequest()
        textRecognitionRequest.recognitionLevel = .accurate
        textRecognitionRequest.usesLanguageCorrection = false
        textRecognitionRequest.minimumTextHeight = 0.005
        textRecognitionRequest.recognitionLanguages = ["en-US"]
        textRecognitionRequest.automaticallyDetectsLanguage = false
        
        // Focus on center-right region where kill notifications appear
        textRecognitionRequest.regionOfInterest = CGRect(x: 0.4, y: 0.3, width: 0.5, height: 0.4)
    }
    
    func processImage(_ ciImage: CIImage, completion: @escaping ([String]) -> Void) {
        guard performanceMonitor.checkMemoryUsage() else {
            print("⚠️ VisionProcessor: Memory limit exceeded, dropping frame")
            performanceMonitor.recordFrameDrop()
            completion([])
            return
        }
        
        print("🔍 VisionProcessor: Starting text recognition on image")
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            autoreleasepool {
                do {
                    try handler.perform([self.textRecognitionRequest])
                    
                    let observations = self.textRecognitionRequest.results ?? []
                    var recognizedStrings: [String] = []
                    
                    print("🔍 VisionProcessor: Found \(observations.count) text observations")
                    
                    for observation in observations {
                        guard observation.confidence > 0.6 else { 
                            print("🔍 Skipping low confidence observation: \(observation.confidence)")
                            continue 
                        }
                        
                        let candidates = observation.topCandidates(1)
                        for candidate in candidates {
                            if candidate.confidence > 0.6 {
                                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !text.isEmpty {
                                    print("🔍 Recognized text: '\(text)' (confidence: \(candidate.confidence))")
                                    recognizedStrings.append(text)
                                }
                            }
                        }
                    }
                    
                    print("🔍 VisionProcessor: Completed. Final text count: \(recognizedStrings.count)")
                    DispatchQueue.main.async {
                        completion(recognizedStrings)
                    }
                    
                } catch {
                    print("❌ VisionProcessor error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion([])
                    }
                }
            }
        }
    }
    
}