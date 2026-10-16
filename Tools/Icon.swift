import AppKit
let root=CommandLine.arguments[1]
let folder=URL(fileURLWithPath:root).appendingPathComponent("TalkieBook.iconset")
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    let s=CGFloat(size), scale=s/1024
    let transform=NSAffineTransform();transform.scale(by:scale);transform.concat()
    NSColor(calibratedRed:0.30,green:0.37,blue:0.28,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:30,y:30,width:964,height:964),xRadius:215,yRadius:215).fill()
    NSColor(calibratedRed:0.94,green:0.90,blue:0.80,alpha:1).setFill()
    let left=NSBezierPath();left.move(to:NSPoint(x:210,y:300));left.line(to:NSPoint(x:210,y:720));left.curve(to:NSPoint(x:495,y:665),controlPoint1:NSPoint(x:325,y:760),controlPoint2:NSPoint(x:405,y:735));left.line(to:NSPoint(x:495,y:245));left.curve(to:NSPoint(x:210,y:300),controlPoint1:NSPoint(x:400,y:315),controlPoint2:NSPoint(x:320,y:340));left.close();left.fill()
    let right=NSBezierPath();right.move(to:NSPoint(x:814,y:300));right.line(to:NSPoint(x:814,y:720));right.curve(to:NSPoint(x:529,y:665),controlPoint1:NSPoint(x:699,y:760),controlPoint2:NSPoint(x:619,y:735));right.line(to:NSPoint(x:529,y:245));right.curve(to:NSPoint(x:814,y:300),controlPoint1:NSPoint(x:624,y:315),controlPoint2:NSPoint(x:704,y:340));right.close();right.fill()
    NSColor(calibratedRed:0.30,green:0.37,blue:0.28,alpha:0.45).setStroke()
    for y in [440,505,570] {let path=NSBezierPath();path.lineWidth=12;path.lineCapStyle = .round;path.move(to:NSPoint(x:265,y:y));path.curve(to:NSPoint(x:437,y:y-28),controlPoint1:NSPoint(x:326,y:y+7),controlPoint2:NSPoint(x:378,y:y-8));path.stroke()}
    NSGraphicsContext.restoreGraphicsState()
    let png=bitmap.representation(using:.png,properties:[:])!
    let names:[String]
    switch size {case 16:names=["icon_16x16.png"];case 32:names=["icon_16x16@2x.png","icon_32x32.png"];case 64:names=["icon_32x32@2x.png"];case 128:names=["icon_128x128.png"];case 256:names=["icon_128x128@2x.png","icon_256x256.png"];case 512:names=["icon_256x256@2x.png","icon_512x512.png"];default:names=["icon_512x512@2x.png"]}
    for name in names {try png.write(to:folder.appendingPathComponent(name))}
}
