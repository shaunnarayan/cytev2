//
//  Analysis.swift
//  Cyte
//
//  Created by Shaun Narayan on 3/03/23.
//

import Foundation
import Vision
import NaturalLanguage

class Analysis {
    static let shared = Analysis()
    private var pendingRequest: Bool = false
    private var dropouts: Int64 = 0
    private var observedTime: Date = Date()
    
    //
    // Runs a chain of vision analysis (OCR then NLP) on the provided frame
    //
    func runOnFrame(frame: CapturedFrame) {
        if pendingRequest {
            dropouts += 1
            log.warning("Drop frame due to overrun in process: \(dropouts)")
            return
        }
        pendingRequest = true
        observedTime = Date()
        // do analysis
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: frame.data!, orientation: .up)
        let request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
        if !utsname.isAppleSilicon {
            // fallback for intel
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
        }
        do {
            // Perform the text-recognition request.
            try requestHandler.perform([request])
        } catch {
            log.warning("Unable to perform the requests: \(error).")
        }
    }
    
    //
    // Callback from vision OCR. Next run NLP and index keywords (nouns)
    //
    func recognizeTextHandler(request: VNRequest, error: Error?) {
        let recognizedStringsAndRects = procVisionResult(request: request, error: error)
        let text = recognizedStringsAndRects.reduce("") { (result, adding) in
            return "\(result) \(adding.0)"
        }
        Task {
            await Memory.shared.observe(what: text, at: observedTime)
            pendingRequest = false
        }
    }
}
