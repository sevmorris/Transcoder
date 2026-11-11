#!/usr/bin/env swift
// Draws Transcoder's app icon and writes every size the appiconset names.
//
// This script is the icon's source: there is no design-tool document behind
// it. It draws in Core Graphics on a 1024-point canvas and renders each size
// straight from the vectors, so nothing is downscaled from a bitmap.
//
//   swift tools/icon/make-icon.swift                 # writes the appiconset
//   swift tools/icon/make-icon.swift --out DIR       # writes somewhere else
//
// The look follows the sibling apps (WaxOnWaxOff, FilmStrip, ClipHack): a navy
// macOS rounded square, one orange glyph folded down the middle (lighter left
// half, darker right half) and a soft shadow under it. Transcoder's glyph is a
// pair of arrows chasing each other round a waveform: audio going from one
// format to another.
//
// Geometry follows Apple's macOS icon grid: on the 1024 canvas the body is
// 824 x 824 at (100, 100), with continuous corners (a superellipse, n = 5,
// which meets the siblings' outline to within a pixel), and a shadow that
// falls about 12 points below it.
//
// Small sizes get their own drawing rather than a shrunken one. At 32 px and
// below the ring is thicker and the waveform drops to fewer, wider bars, laid
// on the pixel grid so they stay separate strokes instead of an orange smear.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette (sampled from FilmStrip's and WaxOnWaxOff's icons)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r / 255, g / 255, b / 255, a])!
}

let navyTop = rgb(38, 104, 148)     // body gradient, top edge
let navyMid = rgb(0, 77, 128)       // reached half-way down
let navyBottom = rgb(0, 65, 108)    // bottom edge
let orangeLight = rgb(251, 151, 68) // left of the fold
let orangeDark = rgb(196, 92, 14)   // right of the fold

/// The body's vertical gradient at `t` (0 top, 1 bottom).
func navy(at t: CGFloat) -> CGColor {
    let t = min(max(t, 0), 1)
    let (a, b, u) = t < 0.5 ? (navyTop, navyMid, t / 0.5) : (navyMid, navyBottom, (t - 0.5) / 0.5)
    let ca = a.components!, cb = b.components!
    return CGColor(colorSpace: sRGB, components: (0..<4).map { ca[$0] + (cb[$0] - ca[$0]) * u })!
}

// MARK: - Geometry (points on the 1024 canvas, y down)

let canvas: CGFloat = 1024
let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let center = CGPoint(x: 512, y: 512)

/// One drawing of the glyph. `full` is for 64 px and up; `small` for 16 and 32.
struct Glyph {
    var ringRadius: CGFloat       // centre line of the ring
    var ringWidth: CGFloat
    var headWidth: CGFloat        // arrowhead, measured across the ring
    var headSweep: CGFloat        // arrowhead length, degrees of arc
    var gap: CGFloat              // degrees between one head's tip and the next tail
    var bars: [(x: CGFloat, width: CGFloat, height: CGFloat)]
    var shadowBlur: CGFloat       // drop shadow under the glyph
    var shadowOffset: CGFloat
    var shadowAlpha: CGFloat
}

let full = Glyph(
    ringRadius: 262, ringWidth: 76, headWidth: 176, headSweep: 27, gap: 22,
    // An asymmetric burst so it reads as sound rather than a bar chart.
    bars: [(-132, 40, 116), (-66, 40, 226), (0, 40, 300), (66, 40, 192), (132, 40, 104)],
    shadowBlur: 46, shadowOffset: 18, shadowAlpha: 0.42)

/// 32 px (and 16 px @2x).
let small = Glyph(
    ringRadius: 268, ringWidth: 128, headWidth: 250, headSweep: 32, gap: 18,
    // Three bars, each 1/16 of the canvas wide with a 1/16 gap, which is
    // exactly two pixels each at 32 px, so they land on the pixel grid.
    bars: [(-128, 64, 128), (0, 64, 256), (128, 64, 128)],
    shadowBlur: 0, shadowOffset: 0, shadowAlpha: 0)

/// 16 px: the arrows alone, heavier. Any bar here falls across the fold and
/// the pixel boundary at the centre and reads as a grey smudge, while the
/// ring on its own still says "convert".
let tiny = Glyph(
    ringRadius: 270, ringWidth: 150, headWidth: 300, headSweep: 40, gap: 22,
    bars: [], shadowBlur: 0, shadowOffset: 0, shadowAlpha: 0)

// MARK: - Paths

/// Apple's continuous-corner square, as a superellipse |x|^n + |y|^n = 1.
func bodyPath(_ r: CGRect, n: CGFloat = 5, steps: Int = 720) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + a * copysign(pow(abs(c), 2 / n), c)
        let y = r.midY + b * copysign(pow(abs(s), 2 / n), s)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func polar(_ radius: CGFloat, _ degrees: CGFloat) -> CGPoint {
    let t = degrees * .pi / 180
    return CGPoint(x: center.x + radius * cos(t), y: center.y + radius * sin(t))
}

/// The filled shapes that make up the glyph. Each is filled on its own, so
/// overlaps never cancel under the winding rule.
func glyphShapes(_ g: Glyph) -> [CGPath] {
    var shapes: [CGPath] = []
    // Two arrows, each a half turn less the gap, the second the first rotated
    // 180°. Angles grow clockwise on screen because y points down. The first
    // starts on the left just above centre and runs over the top.
    let span = 180 - g.gap
    for start in [190.0 as CGFloat, 10] {
        let headBase = start + span - g.headSweep
        let tip = start + span
        // Shaft: an annular sector, so its tail is cut square to the ring.
        let inner = g.ringRadius - g.ringWidth / 2, outer = g.ringRadius + g.ringWidth / 2
        let shaft = CGMutablePath()
        let rad = { (d: CGFloat) in d * .pi / 180 }
        shaft.addArc(center: center, radius: outer, startAngle: rad(start),
                     endAngle: rad(headBase + 0.5), clockwise: false)
        shaft.addArc(center: center, radius: inner, startAngle: rad(headBase + 0.5),
                     endAngle: rad(start), clockwise: true)
        shaft.closeSubpath()
        shapes.append(shaft)
        // Head: base square across the ring, tip on the ring's centre line,
        // so it follows the curve instead of flying off along the tangent.
        let head = CGMutablePath()
        head.move(to: polar(g.ringRadius - g.headWidth / 2, headBase))
        head.addLine(to: polar(g.ringRadius + g.headWidth / 2, headBase))
        head.addLine(to: polar(g.ringRadius, tip))
        head.closeSubpath()
        shapes.append(head)
    }
    for bar in g.bars {
        let r = CGRect(x: center.x + bar.x - bar.width / 2, y: center.y - bar.height / 2,
                       width: bar.width, height: bar.height)
        shapes.append(CGPath(roundedRect: r, cornerWidth: bar.width / 2,
                             cornerHeight: bar.width / 2, transform: nil))
    }
    return shapes
}

// MARK: - Rendering

func render(pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                        bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(pixels) / canvas
    // Work on the 1024 canvas with y down. Shadow offsets and blurs are not
    // touched by the CTM, so they are scaled by `s` by hand, and a shadow
    // that falls down the screen has a negative y offset.
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: s, y: -s)
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)

    let g = pixels <= 16 ? tiny : pixels <= 32 ? small : full
    let body = bodyPath(bodyRect)

    // Body with the grid's drop shadow; skipped where it would be a smudge.
    ctx.saveGState()
    if pixels > 32 {
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s,
                      color: rgb(0, 0, 0, 0.32))
    }
    ctx.addPath(body)
    ctx.setFillColor(navyMid)
    ctx.fillPath()
    ctx.restoreGState()

    // Gradient: the siblings fall from a lighter navy to their mid tone over
    // the top half, then only slightly darker to the bottom.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    // One flat band per pixel row rather than CGGradient, which dithers: the
    // noise is invisible but quadruples the PNG.
    ctx.setShouldAntialias(false)
    for row in 0..<pixels {
        let y = (CGFloat(row) + 0.5) / s
        ctx.setFillColor(navy(at: (y - bodyRect.minY) / bodyRect.height))
        ctx.fill(CGRect(x: 0, y: CGFloat(row) / s, width: canvas, height: 1 / s))
    }
    ctx.setShouldAntialias(true)

    // Glyph: drawn in a transparency layer so the shadow belongs to the whole
    // shape, not to each piece, and stays clipped to the body.
    let shapes = glyphShapes(g)
    ctx.saveGState()
    if g.shadowAlpha > 0 {
        ctx.setShadow(offset: CGSize(width: 0, height: -g.shadowOffset * s),
                      blur: g.shadowBlur * s, color: rgb(0, 20, 40, g.shadowAlpha))
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    func fillAll(_ color: CGColor) {
        ctx.setFillColor(color)
        for p in shapes { ctx.addPath(p); ctx.fillPath() }
    }
    fillAll(orangeLight)
    ctx.saveGState()
    ctx.clip(to: CGRect(x: center.x, y: 0, width: canvas, height: canvas))
    fillAll(orangeDark)
    ctx.restoreGState()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                               1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
}

// MARK: - Main

// Default: the app's appiconset, found from this file, so the script runs
// from any directory.
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
var outDir = repoRoot.appendingPathComponent("Transcoder/Assets.xcassets/AppIcon.appiconset").path
var args = CommandLine.arguments.dropFirst()
while let a = args.popFirst() {
    switch a {
    case "--out": outDir = args.popFirst() ?? outDir
    default:
        FileHandle.standardError.write("usage: make-icon.swift [--out DIR]\n".data(using: .utf8)!)
        exit(2)
    }
}
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("icon_\(px)x\(px).png")
    writePNG(render(pixels: px), to: url)
    let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("\(url.path)  \(px)x\(px)  \(bytes / 1024) KB")
}
