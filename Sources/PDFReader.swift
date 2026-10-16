import SwiftUI
import AppKit
import PDFKit

protocol ReaderControlling: AnyObject {
    func call(_ name:String,_ args:[Any])
    func dispose()
}
extension ReaderControlling {func call(_ name:String){call(name,[])}}

final class SpeechPDFView: PDFView {
    var context: ((NSPoint)->Void)?
    var keyAction: ((String)->Void)?
    override func rightMouseDown(with event:NSEvent){context?(convert(event.locationInWindow,from:nil))}
    override func keyDown(with event:NSEvent){if !event.modifierFlags.intersection([.command,.control,.option]).isEmpty {super.keyDown(with:event);return};if let key=event.charactersIgnoringModifiers,[" ","\u{f702}","\u{f703}"].contains(key){keyAction?(key)}else{super.keyDown(with:event)}}
}
final class SpeechTextView: NSTextView {
    var context:((Int,NSEvent)->Void)?
    var focusSentence:((Int)->Void)?
    var hoverSentence:((Int?)->Void)?
    var keyAction:((String)->Void)?
    private var tracking:NSTrackingArea?
    private func position(_ event:NSEvent)->Int{characterIndexForInsertion(at:convert(event.locationInWindow,from:nil))}
    override func mouseDown(with event:NSEvent){
        if event.clickCount==1,event.modifierFlags.intersection([.shift,.option,.command,.control]).isEmpty{window?.makeFirstResponder(self);focusSentence?(position(event));return}
        if event.modifierFlags.contains(.control){context?(position(event),event);return}
        super.mouseDown(with:event)
    }
    override func mouseUp(with event:NSEvent){
        if event.clickCount==1,event.modifierFlags.intersection([.shift,.option,.command,.control]).isEmpty{focusSentence?(position(event));return}
        super.mouseUp(with:event)
    }
    override func rightMouseDown(with event:NSEvent){context?(position(event),event)}
    override func mouseMoved(with event:NSEvent){hoverSentence?(position(event))}
    override func mouseExited(with event:NSEvent){hoverSentence?(nil)}
    override func updateTrackingAreas(){super.updateTrackingAreas();if let tracking{removeTrackingArea(tracking)};let area=NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil);addTrackingArea(area);tracking=area}
    override func keyDown(with event:NSEvent){if !event.modifierFlags.intersection([.command,.control,.option]).isEmpty {super.keyDown(with:event);return};if let key=event.charactersIgnoringModifiers,[" ","\u{f702}","\u{f703}"].contains(key){keyAction?(key)}else{super.keyDown(with:event)}}
}

/// PDFKit's internal document views own mouse events, so speech interaction sits above them.
final class PDFInteractionSurface:NSView {
    var focusSentence:((NSEvent)->Void)?
    var contextSentence:((NSEvent)->Void)?
    var hoverSentence:((NSEvent?)->Void)?
    var sentenceHit:((NSPoint)->Int?)?
    var textMode=false
    weak var nativePDF:PDFView?
    override var acceptsFirstResponder:Bool{true}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool{true}
    override func keyDown(with event:NSEvent){nativePDF?.keyDown(with:event)}
    private var tracking:NSTrackingArea?
    override func hitTest(_ point:NSPoint)->NSView?{
        if let event=NSApp.currentEvent,event.type == .scrollWheel || !event.modifierFlags.intersection([.shift,.option]).isEmpty{return nil}
        if textMode { guard sentenceHit?(convert(point,to:nil)) != nil else{return nil} }
        return super.hitTest(point)
    }
    override func mouseDown(with event:NSEvent){window?.makeFirstResponder(self);if event.modifierFlags.contains(.control){contextSentence?(event)}else{focusSentence?(event)}}
    override func rightMouseDown(with event:NSEvent){contextSentence?(event)}
    override func mouseMoved(with event:NSEvent){hoverSentence?(event)}
    override func mouseExited(with event:NSEvent){hoverSentence?(nil)}
    override func scrollWheel(with event:NSEvent){nativePDF?.scrollWheel(with:event)}
    override func updateTrackingAreas(){super.updateTrackingAreas();if let tracking{removeTrackingArea(tracking)};let area=NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil);addTrackingArea(area);tracking=area}
}

final class PDFReaderContainer:NSView {
    var didLayout:(()->Void)?
    var mouseLeft:(()->Void)?
    var mouseMovedHandler:((NSEvent)->Void)?
    override func mouseMoved(with event:NSEvent){mouseMovedHandler?(event)}
    override func mouseEntered(with event:NSEvent){mouseMovedHandler?(event)}
    private var tracking:NSTrackingArea?
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();window?.acceptsMouseMovedEvents=true}
    override func updateTrackingAreas(){super.updateTrackingAreas();if let tracking{removeTrackingArea(tracking)};let area=NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil);addTrackingArea(area);tracking=area}
    override func mouseExited(with event:NSEvent){mouseLeft?()}
    override func layout(){super.layout();didLayout?()}
}

final class PDFReaderController:NSObject,ReaderControlling,NSTextViewDelegate {
    weak var model:AppModel?
    let bookID:String
    let container=PDFReaderContainer()
    let pdf=SpeechPDFView()
    let text=SpeechTextView()
    let scroll=NSScrollView()
    let interaction=PDFInteractionSurface()
    private var index:PDFBookIndex?
    private var page=0
    private var mode="original"
    private var token:NSObjectProtocol?
    private var selectionToken:NSObjectProtocol?
    private var annotations:[PDFAnnotation]=[]
    private var ranges:[NSRange]=[]
    private var currentLocator=""
    private var hoveredLocator=""

    private var disposed=false
    private var updating=false

    init(model:AppModel,bookID:String){
        self.model=model;self.bookID=bookID;super.init()
        pdf.autoScales=true;pdf.displayMode = .singlePage;pdf.displayDirection = .vertical;pdf.displaysPageBreaks=true
        pdf.translatesAutoresizingMaskIntoConstraints=false;scroll.translatesAutoresizingMaskIntoConstraints=false;interaction.translatesAutoresizingMaskIntoConstraints=false;interaction.nativePDF=pdf
        text.isEditable=false;text.isSelectable=true;text.isRichText=true;text.drawsBackground=true;text.delegate=self
        text.isVerticallyResizable=true;text.isHorizontallyResizable=false;text.autoresizingMask=[.width]
        text.textContainer?.widthTracksTextView=true;text.textContainer?.containerSize=NSSize(width:600,height:CGFloat.greatestFiniteMagnitude)
        scroll.documentView=text;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        for v in [pdf,scroll,interaction] as [NSView] {container.addSubview(v);NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo:container.leadingAnchor),v.trailingAnchor.constraint(equalTo:container.trailingAnchor),v.topAnchor.constraint(equalTo:container.topAnchor),v.bottomAnchor.constraint(equalTo:container.bottomAnchor)])}
        container.didLayout={[weak self] in self?.layoutText()}
        container.mouseLeft={[weak self] in self?.setHover(nil)}
        interaction.focusSentence={[weak self] event in guard let self,let i=self.hit(atWindowPoint:event.locationInWindow) else{return};self.send("focus",["index":i])}
        interaction.contextSentence={[weak self] event in guard let self,let i=self.hit(atWindowPoint:event.locationInWindow) else{return};let point=self.container.convert(event.locationInWindow,from:nil);DispatchQueue.main.async{[weak self] in self?.showContext(i,at:point)}}
        interaction.hoverSentence={[weak self] event in guard let self else{return};self.setHover(event.flatMap{self.hit(atWindowPoint:$0.locationInWindow)})}
        interaction.sentenceHit={[weak self] point in self?.hit(atWindowPoint:point)}
        text.focusSentence={[weak self] offset in guard let self,let i=self.ranges.firstIndex(where:{NSLocationInRange(offset,$0)}) else{return};self.send("focus",["index":i])}
        text.context={[weak self] offset,event in guard let self,let i=self.ranges.firstIndex(where:{NSLocationInRange(offset,$0)}) else{return};let point=self.container.convert(event.locationInWindow,from:nil);DispatchQueue.main.async{[weak self] in self?.showContext(i,at:point)}}
        text.hoverSentence={[weak self] offset in guard let self else{return};self.setHover(offset.flatMap{offset in self.ranges.firstIndex(where:{NSLocationInRange(offset,$0)})})}

        let keys:(String)->Void = {[weak self] key in guard let self else{return};if key==" "{self.model?.togglePlayback()}else{self.goPage(self.page+(key=="\u{f703}" ? 1:-1))}}
        pdf.keyAction=keys;text.keyAction=keys
        token=NotificationCenter.default.addObserver(forName:.PDFViewPageChanged,object:pdf,queue:.main){[weak self] _ in
            guard let self,!self.updating,let document=self.pdf.document,let current=self.pdf.currentPage else{return}
            let number=document.index(for:current);if number != self.page{self.page=number;self.publish()}
        }
        selectionToken=NotificationCenter.default.addObserver(forName:.PDFViewSelectionChanged,object:pdf,queue:.main){[weak self] _ in self?.selectionChanged()}
        DispatchQueue.main.async{[weak self] in self?.load()}
    }
    private func load(){
        guard !disposed,let model else{return}
        let id=bookID
        DispatchQueue.global(qos:.userInitiated).async{[weak self,weak model] in
            do{
                let url=PDFService.indexURL(id),backup=AppPaths.book(id).appendingPathComponent("pdf-index-before-v2.json")
                let saved=try Data(contentsOf:url)
                var loaded=try JSONDecoder().decode(PDFBookIndex.self,from:saved)
                var previous:PDFBookIndex?
                if loaded.version<PDFBookIndex.currentVersion {
                    previous=loaded
                    try saved.write(to:backup,options:.atomic)
                    DispatchQueue.main.async{model?.notice=L("Aktualizuję indeks PDF…")}
                    _=try PDFService.importDocument(at:PDFService.sourceURL(id),id:id){current,total in
                        DispatchQueue.main.async{if model?.activeID==id{model?.notice=String(format:L("PDF: strona %d z %d"),current,total)}}
                    }
                    loaded=try JSONDecoder().decode(PDFBookIndex.self,from:Data(contentsOf:url))
                }else if FileManager.default.fileExists(atPath:backup.path){previous=try JSONDecoder().decode(PDFBookIndex.self,from:Data(contentsOf:backup))}
                let ready=loaded,old=previous
                DispatchQueue.main.async{[weak self,weak model] in
                    if let old{model?.migratePDFLocations(id,from:old,to:ready)}
                    guard let self,!self.disposed,model?.activeID==id else{return}
                    self.finishLoading(ready)
                }
            }catch{DispatchQueue.main.async{[weak self] in guard let self,!self.disposed else{return};self.model?.readerError(error.localizedDescription)}}
        }
    }
    private func finishLoading(_ loaded:PDFBookIndex){
        guard let model else{return};index=loaded
        guard let document=PDFDocument(url:PDFService.sourceURL(bookID)),!document.isLocked else{model.readerError(L("Nie można otworzyć tego pliku PDF."));return}
        pdf.document=document
        page=parse(model.activeBook?.location ?? "")?.0 ?? 0
        model.receive("toc",["items":contents(document)])
        settings();goPage(page);model.receive("opened",[:])
    }
    private func contents(_ document:PDFDocument)->[[String:Any]]{
        var items:[[String:Any]]=[]
        func flatten(_ outline:PDFOutline,_ depth:Int){
            for i in 0..<outline.numberOfChildren {guard let child=outline.child(at:i) else{continue};if let target=child.destination?.page{items.append(["label":child.label ?? "","href":locator(document.index(for:target),0),"depth":depth])};flatten(child,depth+1)}
        }
        if let outline=document.outlineRoot{flatten(outline,0)}
        if items.isEmpty {items=(index?.pages.indices ?? 0..<0).map{["label":String(format:L("Strona %d"),$0+1),"href":locator($0,0),"depth":0]}}
        return items
    }
    private var sentences:[PDFSentenceData]{guard let index,index.pages.indices.contains(page) else{return []};return index.pages[page].sentences}
    private func locator(_ page:Int,_ sentence:Int)->String{"pdf:\(page):\(sentence)"}
    private func parse(_ value:String)->(Int,Int)?{let parts=value.split(separator:":");guard parts.count==3,parts[0]=="pdf",let p=Int(parts[1]),let s=Int(parts[2]),let index,index.pages.indices.contains(p),s>=0 else{return nil};return (p,s)}
    private func send(_ type:String,_ body:[String:Any]=[:]){guard !disposed,model?.activeID==bookID else{return};model?.receive(type,body)}
    private func publish(){
        guard let index,index.pages.indices.contains(page) else{return}
        hoveredLocator=""
        renderText(resetPosition:true)
        send("sentences",["chapter":page,"items":sentences.enumerated().map{["id":$0.offset,"text":$0.element.text,"cfi":locator(page,$0.offset)]}])
        let label=String(format:L("Strona %d z %d"),page+1,index.pages.count)+(index.pages[page].ocr ? " · OCR":"")
        send("location",["cfi":locator(page,0),"fraction":Double(page)/Double(max(1,index.pages.count-1)),"label":label])
        redraw()
    }
    private func goPage(_ target:Int){
        guard let index,!index.pages.isEmpty else{return}
        page=max(0,min(target,index.pages.count-1));updating=true
        if let target=pdf.document?.page(at:page){pdf.go(to:target)}
        updating=false;publish()
    }
    private func settings(){
        guard let model else{return}
        hoveredLocator=""
        mode=model.pdfMode;pdf.isHidden=mode=="text";scroll.isHidden=mode != "text";interaction.isHidden=false;interaction.textMode=mode=="text"
        pdf.backgroundColor=NSColor(model.paperColors.0);scroll.backgroundColor=NSColor(model.paperColors.0)
        text.backgroundColor=NSColor(model.paperColors.0);text.textColor=NSColor(model.paperColors.1)
        renderText();redraw()
        if let index,index.pages.indices.contains(page) {
            let label=String(format:L("Strona %d z %d"),page+1,index.pages.count)+(index.pages[page].ocr ? " · OCR":"")
            send("location",["cfi":locator(page,0),"fraction":Double(page)/Double(max(1,index.pages.count-1)),"label":label])
            if let document=pdf.document{send("toc",["items":contents(document)])}
        }
    }
    private func renderText(resetPosition:Bool=false){
        let oldOrigin=scroll.contentView.bounds.origin
        guard let model else{return};ranges=[]
        let string=NSMutableAttributedString(string:"")
        let prefs=model.data.preferences
        let baseFont=NSFont(name:prefs.font,size:prefs.fontSize) ?? NSFont.systemFont(ofSize:prefs.fontSize)
        let font=prefs.bold ? NSFontManager.shared.convert(baseFont,toHaveTrait:.boldFontMask):baseFont
        let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=CGFloat(prefs.fontSize*(prefs.lineHeight-1));paragraph.paragraphSpacing=12;paragraph.alignment=prefs.justify ? .justified:.left
        for sentence in sentences{let start=string.length;string.append(NSAttributedString(string:sentence.text,attributes:[.font:font,.foregroundColor:NSColor(model.paperColors.1),.paragraphStyle:paragraph,.kern:prefs.letterSpacing*prefs.fontSize]));ranges.append(NSRange(location:start,length:string.length-start));string.append(NSAttributedString(string:"\n\n"))}
        if prefs.wordSpacing>0 {
            let content=string.string as NSString
            for i in 0..<content.length where content.character(at:i)==32{string.addAttribute(.kern,value:(prefs.letterSpacing+prefs.wordSpacing)*prefs.fontSize,range:NSRange(location:i,length:1))}
        }
        if string.length==0{string.append(NSAttributedString(string:L("Na tej stronie nie znaleziono tekstu do odczytania."),attributes:[.font:font,.foregroundColor:NSColor.secondaryLabelColor]))}
        text.textStorage?.setAttributedString(string);layoutText()
        text.setSelectedRange(NSRange(location:0,length:0));if resetPosition{text.scrollToBeginningOfDocument(nil)}else{scroll.contentView.scroll(to:oldOrigin)}
    }
    private func layoutText(){
        guard let model else{return}
        let width=max(1,scroll.contentSize.width)
        text.textContainerInset=NSSize(width:max(CGFloat(24+model.data.preferences.margin*2),(width-(820-CGFloat(model.data.preferences.margin)*7))/2),height:36)
    }
    private func redraw(){
        guard let document=pdf.document,let model else{return}
        for annotation in annotations{annotation.page?.removeAnnotation(annotation)};annotations=[]
        if let storage=text.textStorage{storage.removeAttribute(.backgroundColor,range:NSRange(location:0,length:storage.length))}
        func add(_ loc:String,_ color:NSColor){
            guard let (p,s)=parse(loc),let index,index.pages[p].sentences.indices.contains(s),let target=document.page(at:p) else{return}
            for rect in index.pages[p].sentences[s].boxes where !rect.isEmpty{let annotation=PDFAnnotation(bounds:rect,forType:.highlight,withProperties:nil);annotation.color=color;annotation.shouldPrint=false;target.addAnnotation(annotation);annotations.append(annotation)}
            if p==page,ranges.indices.contains(s){text.textStorage?.addAttribute(.backgroundColor,value:color,range:ranges[s])}
        }
        for mark in model.data.marks where mark.bookID==bookID && mark.kind != "bookmark"{add(mark.cfi,NSColor.systemYellow.withAlphaComponent(0.25))}
        if !hoveredLocator.isEmpty{add(hoveredLocator,NSColor.systemBlue.withAlphaComponent(0.20))}
        if !currentLocator.isEmpty{add(currentLocator,NSColor.systemGreen.withAlphaComponent(0.30))}
    }
    private func highlight(_ loc:String,_ follow:Bool){
        currentLocator=loc
        if let (p,s)=parse(loc),follow,model?.data.preferences.follow==true{
            if p != page{goPage(p)}
            if mode=="text",ranges.indices.contains(s){text.scrollRangeToVisible(ranges[s])}
            else if let target=pdf.document?.page(at:p),let rect=index?.pages[p].sentences[safe:s]?.boxes.first{pdf.go(to:rect,on:target)}
        }
        redraw()
    }
    private func hit(atWindowPoint pointInWindow:NSPoint)->Int? {
        if mode=="original" {
            let point=pdf.convert(pointInWindow,from:nil)
            guard let target=pdf.page(for:point,nearest:false),let document=pdf.document,document.index(for:target)==page else{return nil}
            return PDFSentenceHitTesting.sentence(at:pdf.convert(point,to:target),boxes:sentences.map{$0.boxes})
        }
        let point=text.convert(pointInWindow,from:nil)
        guard let layout=text.layoutManager,let textContainer=text.textContainer else{return nil}
        let local=NSPoint(x:point.x-text.textContainerOrigin.x,y:point.y-text.textContainerOrigin.y)
        let rectangles=ranges.map{range->[CGRect] in
            var result:[CGRect]=[]
            let glyphs=layout.glyphRange(forCharacterRange:range,actualCharacterRange:nil)
            layout.enumerateEnclosingRects(forGlyphRange:glyphs,withinSelectedGlyphRange:NSRange(location:NSNotFound,length:0),in:textContainer){rect,_ in result.append(rect)}
            return result
        }
        return PDFSentenceHitTesting.sentence(at:local,boxes:rectangles)
    }
    private func setHover(_ index:Int?){
        let locator=index.map{self.locator(page,$0)} ?? ""
        guard locator != hoveredLocator else{return};hoveredLocator=locator;redraw()
        if index != nil{NSCursor.pointingHand.set()}else{NSCursor.arrow.set()}
    }
    private func contextAt(_ point:NSPoint){
        guard let target=pdf.page(for:point,nearest:false),let document=pdf.document,document.index(for:target)==page else{return}
        if let index=PDFSentenceHitTesting.sentence(at:pdf.convert(point,to:target),boxes:sentences.map{$0.boxes}){contextSentence(index)}
    }
    private func showContext(_ i:Int,at point:NSPoint){
        guard !disposed,sentences.indices.contains(i),let model else{return}
        setHover(i)
        let menu=model.contextMenu(index:i,cfi:locator(page,i),text:sentences[i].text)
        menu.popUp(positioning:nil,at:point,in:container)
    }
    private func contextSentence(_ i:Int){guard sentences.indices.contains(i) else{return};send("context",["index":i,"cfi":locator(page,i),"text":sentences[i].text])}
    private func selectionChanged(){
        guard let selection=pdf.currentSelection,let target=selection.pages.first,let document=pdf.document,let index,let selected=selection.string,!selected.isEmpty else{return}
        let p=document.index(for:target);guard index.pages.indices.contains(p) else{return}
        let bounds=selection.bounds(for:target)
        if let s=index.pages[p].sentences.firstIndex(where:{$0.boxes.contains(where:{$0.intersects(bounds)})}){send("selection",["text":selected,"cfi":locator(p,s)])}
    }
    func textViewDidChangeSelection(_ notification:Notification){let selected=text.selectedRange();guard selected.length>0,let i=ranges.firstIndex(where:{NSIntersectionRange($0,selected).length>0}) else{return};send("selection",["text":(text.string as NSString).substring(with:selected),"cfi":locator(page,i)])}
    func call(_ name:String,_ args:[Any]){
        guard !disposed else{return}
        switch name{
        case "settings":settings()
        case "next":goPage(page+1)
        case "prev":goPage(page-1)
        case "go":if let loc=args.first as? String,let(p,s)=parse(loc){goPage(p);highlight(locator(p,s),true)}
        case "fraction":if let f=args.first as? Double,let index{goPage(Int((Double(index.pages.count-1)*min(1,max(0,f))).rounded()))}
        case "highlight":highlight(args.first as? String ?? "",args.count>1 ? args[1] as? Bool ?? false:false)
        case "begin","resume":
            if let loc=args.first as? String,let(p,s)=parse(loc){goPage(p);send("start",["index":min(s,max(0,sentences.count-1))])}
            else{send("start",["index":0])}
        case "nextChapter":
            let from=args.first as? Int ?? page;var next=from+1
            while let index,next<index.pages.count,index.pages[next].sentences.isEmpty{next+=1}
            if let index,next<index.pages.count{goPage(next);send("start",["index":0])}else{send("end")}
        case "bookmark":send("bookmark",["cfi":locator(page,0),"text":String(format:L("Strona %d"),page+1)])
        case "annotation","removeAnnotation":redraw()
        case "zoomIn":pdf.zoomIn(nil)
        case "zoomOut":pdf.zoomOut(nil)
        case "search":
            let query=args.first as? String ?? "";var items:[[String:String]]=[]
            if !query.isEmpty,let index {outer:for(p,data) in index.pages.enumerated(){for(s,sentence) in data.sentences.enumerated() where sentence.text.localizedCaseInsensitiveContains(query){items.append(["cfi":locator(p,s),"text":String(format:L("Strona %d"),p+1)+" · "+sentence.text]);if items.count>=150{break outer}}}}
            send("search",["items":items])
        default:break
        }
    }
    func dispose(){disposed=true;if let token{NotificationCenter.default.removeObserver(token)};if let selectionToken{NotificationCenter.default.removeObserver(selectionToken)};pdf.document=nil}
    deinit{if let token{NotificationCenter.default.removeObserver(token)};if let selectionToken{NotificationCenter.default.removeObserver(selectionToken)}}
}
extension Array {subscript(safe index:Int)->Element?{indices.contains(index) ? self[index]:nil}}
struct PDFReader:NSViewRepresentable{
    @ObservedObject var model:AppModel
    let bookID:String
    func makeCoordinator()->PDFReaderController{PDFReaderController(model:model,bookID:bookID)}
    func makeNSView(context:Context)->NSView{model.reader=context.coordinator;return context.coordinator.container}
    func updateNSView(_ view:NSView,context:Context){}
    static func dismantleNSView(_ view:NSView,coordinator:PDFReaderController){coordinator.dispose()}
}
