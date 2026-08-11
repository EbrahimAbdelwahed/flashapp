// Reads the clock out of a clip's first frame.
//
// Spec §1.12 requires every clip to open on the keynote status bar, and §3.6 requires
// `make verify` to enforce it. Asserting that the override was applied is not the same
// thing: the simulator drops it on some state transitions, and the failure is invisible
// until the footage is on the timeline. So the frame is actually read.
//
// Usage: StatusBarCheck <frame.png> [expected time]
// Exit 0 when the expected time is on screen, 1 when it is not, 2 on a usage error.

import CoreGraphics
import Foundation
import ImageIO
import Vision

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: StatusBarCheck <frame.png> [expected time]\n".utf8))
    exit(2)
}

let frameURL = URL(fileURLWithPath: arguments[1])
let expected = arguments.count >= 3 ? arguments[2] : "9:41"

guard
    let source = CGImageSourceCreateWithURL(frameURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    FileHandle.standardError.write(Data("cannot read image at \(frameURL.path)\n".utf8))
    exit(2)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
// The clock lives in the top-left corner. Vision's origin is bottom-left, so the top 8%
// of the frame is y >= 0.92. Restricting the region keeps a "9:41" elsewhere in the app
// from passing a clip whose status bar is wrong.
request.regionOfInterest = CGRect(x: 0, y: 0.92, width: 0.45, height: 0.08)

do {
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
} catch {
    FileHandle.standardError.write(Data("vision failed: \(error)\n".utf8))
    exit(2)
}

let observations = request.results ?? []
let readings = observations.compactMap { $0.topCandidates(1).first?.string }
let normalised = readings.map { $0.replacingOccurrences(of: " ", with: "") }

if normalised.contains(where: { $0.contains(expected) }) {
    print("ok \(expected)")
    exit(0)
}

let seen = readings.isEmpty ? "(nothing legible)" : readings.joined(separator: " | ")
print("expected \(expected), read: \(seen)")
exit(1)
