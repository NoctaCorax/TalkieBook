import Foundation
import SwiftUI

final class RecordingReader:ReaderControlling {
    var calls:[(String,[Any])]=[]
    func call(_ name:String,_ args:[Any]){calls.append((name,args))}
    func dispose(){}
}
@main struct PlaybackTests {
    static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("talkiebook-playback-"+UUID().uuidString)
        setenv("TALKIEBOOK_DATA_DIR",root.path,1)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        let id=UUID().uuidString
        var data=LibraryData();data.books=[Book(id:id,title:"Test",author:"",format:"pdf")]
        data.books[0].location="pdf:0:1";data.books[0].speechLocation="pdf:0:1"
        data.marks=[Mark(bookID:id,cfi:"pdf:0:1",text:"Body sentence.",note:"Preserved note",kind:"note")]
        try JSONEncoder().encode(data).write(to:root.appendingPathComponent("library.json"))
        let model=AppModel();model.open(model.data.books[0]);model.ready=true
        let reader=RecordingReader();model.reader=reader
        model.receive("sentences",["chapter":0,"items":[["id":0,"text":"First.","cfi":"pdf:0:0"],["id":1,"text":"Second.","cfi":"pdf:0:1"]]])
        model.receive("focus",["index":1])
        precondition(!model.isPlaying && model.currentText=="Second." && model.sentenceIndex==1 && model.sentenceCount==2)
        precondition(model.data.books[0].speechLocation=="pdf:0:1")
        model.seekToSentence(-1);precondition(model.currentText=="Second.")
        model.stop();model.open(model.data.books[0]);model.reader=reader
        let first=PDFSentenceData(text:"Header",start:0,length:6,boxes:[]),body=PDFSentenceData(text:"Body sentence.",start:7,length:14,boxes:[])
        let old=PDFBookIndex(version:1,pages:[PDFPageData(label:"1",sentences:[first,body],ocr:false)])
        let new=PDFBookIndex(pages:[PDFPageData(label:"1",sentences:[body],ocr:false)])
        model.migratePDFLocations(id,from:old,to:new)
        precondition(model.data.marks[0].cfi=="pdf:0:0" && model.data.marks[0].note=="Preserved note")
        precondition(model.data.books[0].speechLocation=="pdf:0:0" && model.data.books[0].pdfIndexVersion==PDFBookIndex.currentVersion)
        model.ready=true;model.togglePlayback()
        precondition(reader.calls.last?.0=="resume" && reader.calls.last?.1.first as? String=="pdf:0:0")
        model.shutdown()
        print("Paused sentence focus and bookmark/note/resume migration: passed")
    }
}
