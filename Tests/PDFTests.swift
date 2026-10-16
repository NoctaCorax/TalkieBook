import Foundation
import PDFKit
import CoreText
import Vision

struct EngineError:LocalizedError {let message:String;var errorDescription:String?{message}}

@main struct PDFTests {
    static func main() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("talkiebook-tests-"+UUID().uuidString)
        setenv("TALKIEBOOK_DATA_DIR",directory.path,1)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        // An isolated synthetic fixture; tests never search a user's personal folders.
        let source=directory.appendingPathComponent("Sample.pdf")
        var media=CGRect(x:0,y:0,width:595,height:842)
        guard let context=CGContext(source as CFURL,mediaBox:&media,nil) else{fatalError("Cannot create test PDF")}
        for page in 1...8 {
            context.beginPDFPage(nil)
            func draw(_ value:String,_ y:Double){
                let line=CTLineCreateWithAttributedString(NSAttributedString(string:value,attributes:[.font:NSFont.systemFont(ofSize:16)]) as CFAttributedString)
                context.textPosition=CGPoint(x:50,y:y);CTLineDraw(line,context)
            }
            draw(page%2==0 ? "Even running header":"Odd running header",800);draw("Page \(page). A sentence split across",720);draw("two lines. Polish: Zażółć gęślą jaźń.",695);draw(page<=4 ? "Chapter One footer \(page)":"Chapter Two footer \(page)",30)
            context.endPDFPage()
        }
        context.closePDF()
        let id=UUID().uuidString
        try FileManager.default.createDirectory(at:AppPaths.book(id),withIntermediateDirectories:true)
        let result=try PDFService.importDocument(at:source,id:id){_,_ in}
        let index=try JSONDecoder().decode(PDFBookIndex.self,from:Data(contentsOf:PDFService.indexURL(id)))
        precondition(result.isPDF && index.pages.count==8 && index.version==PDFBookIndex.currentVersion)
        let sentences=index.pages.flatMap{$0.sentences}
        precondition(sentences.contains{$0.text.contains("split across two lines.")})
        precondition(sentences.contains{$0.text.contains("Page 1.")})
        precondition(!sentences.contains{$0.text.contains("running header") || $0.text.contains("footer")})
        precondition(sentences.allSatisfy{!$0.boxes.isEmpty && $0.text.count<=1000})
        precondition(PDFService.clean("Sło-\nwo  i tekst") == "Słowo i tekst")
        let raw="Zażółć\n  gęślą 😀 jaźń. Kolejne zdanie."
        let (normalized,offsets)=PDFService.normalizedText(raw)
        let match=(normalized as NSString).range(of:"jaźń")
        precondition((raw as NSString).substring(with:NSRange(location:offsets[match.location],length:match.length)) == "jaźń")
        let hitBoxes=[[CGRect(x:10,y:20,width:100,height:14),CGRect(x:10,y:40,width:65,height:14)],[CGRect(x:80,y:40,width:80,height:14)]]
        precondition(PDFSentenceHitTesting.sentence(at:CGPoint(x:35,y:45),boxes:hitBoxes)==0)
        precondition(PDFSentenceHitTesting.sentence(at:CGPoint(x:110,y:45),boxes:hitBoxes)==1)
        precondition(PDFSentenceHitTesting.sentence(at:CGPoint(x:500,y:500),boxes:hitBoxes)==nil)
        let first=PDFSentenceData(text:"Running header",start:0,length:15,boxes:[])
        let body=PDFSentenceData(text:"Body sentence.",start:16,length:14,boxes:[])
        let oldIndex=PDFBookIndex(version:1,pages:[PDFPageData(label:"1",sentences:[first,body],ocr:false)])
        let newIndex=PDFBookIndex(pages:[PDFPageData(label:"1",sentences:[body],ocr:false)])
        precondition(PDFService.remapLocator("pdf:0:1",from:oldIndex,to:newIndex)=="pdf:0:0")
        let legacy=#"{"id":"old","title":"Test","author":"","cover":"","fingerprint":"","added":0,"location":"","speechLocation":"","progress":0,"status":"W trakcie","collection":""}"#
        let oldBook=try JSONDecoder().decode(Book.self,from:Data(legacy.utf8))
        precondition(!oldBook.isPDF)
        // OCR is tested explicitly because Vision needs access to graphics services.
        if CommandLine.arguments.contains("--ocr") {
            let ocrDocument=PDFDocument(url:source)
            guard let page=ocrDocument?.page(at:0) else{fatalError("Missing fixture page")}
            let recognized=try PDFService.recognize(page)
            precondition(recognized.contains{$0.text.localizedCaseInsensitiveContains("sentence")})
            precondition(recognized.allSatisfy{!$0.boxes.isEmpty})
            print("Local OCR: passed")
        }
        print("PDF import, sentence mapping, repeated headers, Unicode offsets and legacy library: passed")
    }
}
