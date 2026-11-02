import Foundation
import UIKit
import Vision

/// Finds the densest block of text in a photo (paper, screen, whiteboard, anything) and
/// returns a full-resolution crop of it. The glasses see the whole room; the model only
/// needs the problem, and small print survives much better when it is not downscaled
/// together with the rest of the frame.
enum TextRegion {
    struct Match {
        let crop: UIImage
        let rect: CGRect      // pixel rect inside the upright source image
        let lines: Int        // text lines that formed the block
    }

    /// `image` must be upright (orientation .up, scale 1); see `Tutor.upright`.
    static func find(in image: UIImage) -> Match? {
        guard let cg = image.cgImage else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let observations = request.results, !observations.isEmpty else { return nil }

        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        struct Line { let rect: CGRect; let chars: Int }
        var lines: [Line] = []
        for o in observations {
            let text = o.topCandidates(1).first?.string ?? ""
            // Single glyphs are keyboard keys, icons and noise; real lines have several characters.
            guard text.count >= 2 else { continue }
            let b = o.boundingBox   // normalized, origin bottom-left
            let rect = CGRect(x: b.minX * w, y: (1 - b.maxY) * h, width: b.width * w, height: b.height * h)
            guard rect.height >= h * 0.004 else { continue }
            lines.append(Line(rect: rect, chars: text.count))
        }
        guard !lines.isEmpty else { return nil }

        // Cluster lines that sit close to each other (gap under two line heights), then keep
        // the cluster with the most characters: that is the problem, not the browser tabs or
        // the key caps.
        var cluster = Array(0..<lines.count)   // union-find parent
        func root(_ i: Int) -> Int { var i = i; while cluster[i] != i { cluster[i] = cluster[cluster[i]]; i = cluster[i] }; return i }
        for i in 0..<lines.count {
            for j in (i + 1)..<lines.count {
                let a = lines[i].rect, b = lines[j].rect
                let pad = max(a.height, b.height) * 2
                if a.insetBy(dx: -pad, dy: -pad).intersects(b) {
                    let ra = root(i), rb = root(j)
                    if ra != rb { cluster[ra] = rb }
                }
            }
        }
        var totals: [Int: (chars: Int, count: Int, rect: CGRect)] = [:]
        for (i, line) in lines.enumerated() {
            let r = root(i)
            if let t = totals[r] {
                totals[r] = (t.chars + line.chars, t.count + 1, t.rect.union(line.rect))
            } else {
                totals[r] = (line.chars, 1, line.rect)
            }
        }
        guard let best = totals.values.max(by: { $0.chars < $1.chars }) else { return nil }

        // Breathe a little around the block so matrix brackets and margins are not clipped.
        let margin = max(24, min(best.rect.width, best.rect.height) * 0.08)
        let padded = best.rect.insetBy(dx: -margin, dy: -margin)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
            .integral
        guard padded.width > 40, padded.height > 20, let cropped = cg.cropping(to: padded) else { return nil }
        return Match(crop: UIImage(cgImage: cropped), rect: padded, lines: best.count)
    }
}
