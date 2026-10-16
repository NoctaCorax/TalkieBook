import Foundation

/// A small tolerance makes pointing comfortable without sending blank-area clicks to sentence zero.
enum PDFSentenceHitTesting {
    static func sentence(at point:CGPoint,boxes:[[CGRect]])->Int? {
        var best:Int?,distance=CGFloat.greatestFiniteMagnitude
        for (index,rects) in boxes.enumerated(){for rect in rects where !rect.isEmpty {
            let dx=max(rect.minX-point.x,0,point.x-rect.maxX),dy=max(rect.minY-point.y,0,point.y-rect.maxY)
            guard dx<=10,dy<=min(7,max(3,rect.height*0.4)) else{continue}
            let score=dx*dx+dy*dy
            if score<distance{distance=score;best=index}
        }}
        return best
    }
}
