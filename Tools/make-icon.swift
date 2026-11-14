// 生成 macOS 应用图标。
//
// 用法（在仓库根目录执行）：
//     swift Tools/make-icon.swift
//
// 规则遵循 Apple 的 macOS 图标网格：1024 画布、824×824 主体、185.4 圆角。
// 每个尺寸都按自身分辨率原生渲染，不从大图缩放，避免小尺寸发虚；
// 16–40px 改用六边形剪影，否则细线条会糊成一团。

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourcePath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : root.appendingPathComponent("Resources/icon-source.png").path
let iconsetDir = root.appendingPathComponent("Resources/AppIcon.iconset")
let masterPath = root.appendingPathComponent("Resources/icon_1024.png").path
let icnsPath = root.appendingPathComponent("Resources/AppIcon.icns").path

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
      let mark = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("找不到图标源文件：\(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func hexagonPath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let radius = rect.height / 2
    for i in 0..<6 {
        let angle = CGFloat.pi / 2 + CGFloat(i) * .pi / 3
        let point = CGPoint(x: rect.midX + cos(angle) * radius, y: rect.midY + sin(angle) * radius)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

func render(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let inset = s * (100.0 / 1024.0)
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * (185.4 / 824.0)
    let outline = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))
    ctx.interpolationQuality = .high

    ctx.saveGState()
    ctx.addPath(outline)
    ctx.clip()

    // 顶白到底部淡蓝灰的三段渐变，避免大面积纯白显得扁平
    let stops = [
        CGColor(colorSpace: space, components: [1.00, 1.00, 1.00, 1.0])!,
        CGColor(colorSpace: space, components: [0.972, 0.978, 0.992, 1.0])!,
        CGColor(colorSpace: space, components: [0.902, 0.918, 0.953, 1.0])!,
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: space, colors: stops, locations: [0, 0.55, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: body.maxY),
            end: CGPoint(x: 0, y: body.minY),
            options: []
        )
    }

    if s <= 40 {
        var hex = body.insetBy(dx: body.width * 0.175, dy: body.height * 0.165)
        hex.size.width = hex.height * 0.866
        hex.origin.x = body.midX - hex.width / 2
        ctx.addPath(hexagonPath(in: hex))
        ctx.setFillColor(CGColor(colorSpace: space, components: [0.145, 0.149, 0.161, 1.0])!)
        ctx.fillPath()
    } else {
        let scale: CGFloat = s <= 64 ? 0.70 : 0.68
        let height = body.height * scale
        let width = height * CGFloat(mark.width) / CGFloat(mark.height)
        ctx.draw(mark, in: CGRect(
            x: body.midX - width / 2, y: body.midY - height / 2,
            width: width, height: height
        ))
    }
    ctx.restoreGState()

    // 受光边
    ctx.saveGState()
    ctx.addPath(outline)
    ctx.clip()
    ctx.addPath(outline)
    ctx.setStrokeColor(CGColor(colorSpace: space, components: [1, 1, 1, 0.65])!)
    ctx.setLineWidth(max(1, s * 0.004))
    ctx.strokePath()
    ctx.restoreGState()

    // 外侧细描边，深色背景上不飘
    ctx.addPath(outline)
    ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.35, 0.40, 0.50, 0.16])!)
    ctx.setLineWidth(max(1, s * 0.0025))
    ctx.strokePath()

    return ctx.makeImage()
}

try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let jobs: [(size: Int, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for job in jobs {
    guard let image = render(size: job.size) else { continue }
    let url = iconsetDir.appendingPathComponent(job.name)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { continue }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)

    if job.name == "icon_512x512@2x.png",
       let master = CGImageDestinationCreateWithURL(
           URL(fileURLWithPath: masterPath) as CFURL,
           UTType.png.identifier as CFString, 1, nil
       ) {
        CGImageDestinationAddImage(master, image, nil)
        CGImageDestinationFinalize(master)
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsPath]
try iconutil.run()
iconutil.waitUntilExit()
print("图标已生成：\(icnsPath)")
