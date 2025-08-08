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
        
        // Remove regionOfInterest - we're already cropping the image in SampleHandler
        // Let Vision process the entire cropped image for better results
        // textRecognitionRequest.regionOfInterest = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
    }
    
    func processImage(_ ciImage: CIImage, completion: @escaping ([String]) -> Void) {
        // Remove performance monitor check - it's blocking OCR processing
        // Extension already handles memory management through frame cropping
        
        NSLog("🔍 VisionProcessor: Starting text recognition on cropped image")
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            autoreleasepool {
                do {
                    try handler.perform([self.textRecognitionRequest])
                    
                    let observations = self.textRecognitionRequest.results ?? []
                    var recognizedStrings: [String] = []
                    
                    NSLog("🔍 VisionProcessor: Found \(observations.count) text observations")
                    
                    for observation in observations {
                        guard observation.confidence > 0.5 else { 
                            NSLog("🔍 Skipping low confidence observation: \(observation.confidence)")
                            continue 
                        }
                        
                        let candidates = observation.topCandidates(1)
                        for candidate in candidates {
                            if candidate.confidence > 0.5 {
                                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !text.isEmpty {
                                    NSLog("🔍 Recognized text: '\(text)' (confidence: \(candidate.confidence))")
                                    recognizedStrings.append(text)
                                }
                            }
                        }
                    }
                    
                    NSLog("🔍 VisionProcessor: Completed. Final text count: \(recognizedStrings.count)")
                    DispatchQueue.main.async {
                        completion(recognizedStrings)
                    }
                    
                } catch {
                    NSLog("❌ VisionProcessor error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion([])
                    }
                }
            }
        }
    }
    
}