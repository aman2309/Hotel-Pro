import Cocoa
import FlutterMacOS
import Vision

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let ocrChannel = FlutterMethodChannel(
      name: "hotel_pro/ocr",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    ocrChannel.setMethodCallHandler { call, result in
      guard call.method == "recognizeText",
            let path = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      IdCardOcr.recognize(path: path, result: result)
    }

    super.awakeFromNib()
  }
}

private enum IdCardOcr {
  static func recognize(path: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      let url = URL(fileURLWithPath: path)
      guard FileManager.default.fileExists(atPath: path),
            let nsImage = NSImage(contentsOf: url),
            let tiff = nsImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let cgImage = bitmap.cgImage else {
        DispatchQueue.main.async { result("") }
        return
      }

      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["en-US"]

      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      do {
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap {
          $0.topCandidates(1).first?.string
        }
        DispatchQueue.main.async { result(lines.joined(separator: "\n")) }
      } catch {
        DispatchQueue.main.async { result("") }
      }
    }
  }
}
