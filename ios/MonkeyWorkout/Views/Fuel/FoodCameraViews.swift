import AVFoundation
import CoreImage
import SwiftUI
import UIKit
import Vision
import WorkoutEngine

// Scan live sees plain food (#1012, design C from `scan-food-live/proposals.png`): one camera reads labels and
// receipts (text), barcodes, and names the food in view with Apple's image classifier, all on the iPhone. Frames are
// dropped as soon as Vision has read them; only a frame the member sends with Ask Monkey leaves the phone.

/// Camera frames → text lines, barcodes and what the classifier sees (whole frame and the main objects).
final class FoodCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// One look at a part of the frame: its box (Vision 0–1, y up; nil = whole frame) and the classifier's guesses.
    struct Region {
        var box: CGRect?
        var guesses: [SeenFood.Guess]
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "monkeyworkout.food-scan", qos: .userInitiated)
    /// On the main thread: a text line read for the first time.
    var onText: ((String) -> Void)?
    /// On the main thread: a barcode (EAN-13, EAN-8, UPC-E).
    var onBarcode: ((String) -> Void)?
    /// On the main thread, about once a second: what the classifier sees.
    var onLook: (([Region]) -> Void)?
    private var lastRead = -10.0
    private var lastLook = -10.0
    private var lines: Set<String> = []
    private var codes: Set<String> = []
    private var snap: ((UIImage?) -> Void)?
    private let ci = CIContext()

    private let textRequest: VNRecognizeTextRequest = {
        let r = VNRecognizeTextRequest()
        r.recognitionLevel = .fast
        r.recognitionLanguages = ["en", "de", "fr", "it"]
        r.usesLanguageCorrection = true
        return r
    }()
    private let barcodeRequest: VNDetectBarcodesRequest = {
        let r = VNDetectBarcodesRequest()
        r.symbologies = [.ean13, .ean8, .upce]
        return r
    }()
    private let objectsRequest = VNGenerateObjectnessBasedSaliencyImageRequest()

    /// Frames are upright (portrait): width ÷ height of what Vision reads.
    static let aspect = 720.0 / 1280

    func start() {
        queue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720
            for i in session.inputs { session.removeInput(i) }
            for o in session.outputs { session.removeOutput(o) }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            if let c = output.connection(with: .video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    /// The next frame as a picture (Ask Monkey), on the main thread.
    func snapshot(_ done: @escaping (UIImage?) -> Void) {
        queue.async { [self] in
            if session.isRunning { snap = done } else { DispatchQueue.main.async { done(nil) } }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        if let done = snap {
            snap = nil
            let image = CIImage(cvPixelBuffer: buffer)
            let picture = ci.createCGImage(image, from: image.extent).map { UIImage(cgImage: $0) }
            DispatchQueue.main.async { done(picture) }
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        if t - lastRead >= 0.5 {
            lastRead = t
            try? handler.perform([barcodeRequest, textRequest])
            let newCodes = (barcodeRequest.results ?? []).compactMap(\.payloadStringValue).filter { codes.insert($0).inserted }
            if lines.count > 400 { lines = [] }
            let newLines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .filter { lines.insert($0).inserted }
            if !newCodes.isEmpty || !newLines.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    newCodes.forEach { self?.onBarcode?($0) }
                    newLines.forEach { self?.onText?($0) }
                }
            }
        }
        if onLook != nil, t - lastLook >= 1 {
            lastLook = t
            let regions = Self.look(handler, objects: objectsRequest)
            DispatchQueue.main.async { [weak self] in self?.onLook?(regions) }
        }
    }

    /// The whole frame, then the two main objects on their own (a croissant on a table is a small part of the frame).
    private static func look(_ handler: VNImageRequestHandler, objects: VNGenerateObjectnessBasedSaliencyImageRequest) -> [Region] {
        let whole = VNClassifyImageRequest()
        try? handler.perform([whole, objects])
        var out = [Region(box: nil, guesses: guesses(whole))]
        let boxes = (objects.results?.first?.salientObjects ?? []).sorted { $0.confidence > $1.confidence }.prefix(2)
        for o in boxes {
            let box = o.boundingBox.insetBy(dx: -0.04, dy: -0.04).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard box.width > 0.08, box.height > 0.08 else { continue }
            let crop = VNClassifyImageRequest()
            crop.regionOfInterest = box
            try? handler.perform([crop])
            out.append(Region(box: o.boundingBox, guesses: guesses(crop)))
        }
        return out
    }

    private static func guesses(_ r: VNClassifyImageRequest) -> [SeenFood.Guess] {
        (r.results ?? []).filter { $0.confidence >= Float(SeenFood.Tracker.fair) }
            .map { SeenFood.Guess($0.identifier, Double($0.confidence)) }
    }
}

/// The lime box and label over the food the classifier sees, placed on the aspect-filled preview.
struct SeenFoodBox: View {
    let box: CGRect
    let title: String

    var body: some View {
        GeometryReader { geo in
            let s = max(geo.size.width / FoodCamera.aspect, geo.size.height)
            let w = FoodCamera.aspect * s
            let x = (geo.size.width - w) / 2 + box.minX * w
            let y = (geo.size.height - s) / 2 + (1 - box.maxY) * s
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.lime, lineWidth: 3)
                    .shadow(color: Theme.lime.opacity(0.6), radius: 8)
                    .frame(width: box.width * w, height: box.height * s)
                    .offset(x: x, y: y)
                Text(title)
                    .font(.caption.weight(.heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(FuelPalette.hot))
                    .offset(x: x - 4, y: max(4, y - 30))
            }
            .animation(.easeOut(duration: 0.25), value: box)
        }
        .allowsHitTesting(false)
    }
}
