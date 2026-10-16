import AppKit
import PDFKit
import Vision
import NaturalLanguage

struct PDFSentenceData: Codable {
    let text: String
    let start: Int
    let length: Int
    let boxes: [CGRect]
}
struct PDFPageData: Codable {
    let label: String
    let sentences: [PDFSentenceData]
    let ocr: Bool
}
struct PDFBookIndex: Codable {
    static let currentVersion = 2
    var version = currentVersion
    let pages: [PDFPageData]
}

struct PDFTextLine {
    let text: String
    let range: NSRange
    let bounds: CGRect
}
private struct PDFPageInput {
    let text:String
    let lines:[PDFTextLine]
    let bounds:CGRect
    let label:String
    let ocr:Bool
}

enum PDFService {
    static func indexURL(_ id:String)->URL {AppPaths.book(id).appendingPathComponent("pdf-index.json")}
    static func sourceURL(_ id:String)->URL {AppPaths.book(id).appendingPathComponent("source.pdf")}

    static func importDocument(at url:URL,id:String,progress:@escaping(Int,Int)->Void) throws -> Book {
        guard let document=PDFDocument(url:url),document.pageCount>0 else{throw EngineError(message:L("Nie można otworzyć tego pliku PDF."))}
        guard !document.isLocked else{throw EngineError(message:L("Ten PDF wymaga hasła. Obsługa zaszyfrowanych dokumentów nie jest jeszcze dostępna."))}
        guard document.allowsCopying else{throw EngineError(message:L("Ten PDF nie zezwala na wyodrębnianie tekstu."))}
        // Collect lines before segmentation: running matter can otherwise merge with body sentences.
        var inputs:[PDFPageInput]=[]
        for number in 0..<document.pageCount {
            try autoreleasepool {
                guard let page=document.page(at:number) else{throw EngineError(message:L("Nie można odczytać strony PDF."))}
                let raw=page.string ?? "",bounds=page.bounds(for:.cropBox)
                if raw.filter({$0.isLetter}).count>=12 {
                    inputs.append(PDFPageInput(text:raw,lines:textLines(page),bounds:bounds,label:page.label ?? String(number+1),ocr:false))
                }else{
                    let lines=try recognizeLines(page)
                    let raw=lines.map{$0.text}.joined(separator:"\n")
                    inputs.append(PDFPageInput(text:raw,lines:lines,bounds:bounds,label:page.label ?? String(number+1),ocr:true))
                }
                progress(number+1,document.pageCount)
            }
        }
        var counts:[String:Int]=[:]
        for input in inputs {
            for key in Set(input.lines.compactMap{runningKey($0,bounds:input.bounds)}){counts[key,default:0]+=1}
        }
        // Two occurrences also catch alternating odd/even and chapter-specific running heads.
        let repeated=Set(counts.filter{$0.value>=2}.map{$0.key})
        var pages:[PDFPageData]=[]
        for (number,input) in inputs.enumerated() {
            autoreleasepool {
                let excluded=input.lines.filter {line in
                    guard let key=runningKey(line,bounds:input.bounds) else{return false}
                    return repeated.contains(key) || isPageNumber(line.text)
                }.map{$0.range}
                let sentences=segment(input.text,excluding:excluded) {range in
                    if input.ocr {return input.lines.filter{NSIntersectionRange($0.range,range).length>0}.map{$0.bounds}}
                    return document.page(at:number)?.selection(for:range)?.selectionsByLine().map{$0.bounds(for:document.page(at:number)!)} ?? []
                }.map{PDFSentenceData(text:$0.text,start:input.ocr ? -1:$0.start,length:input.ocr ? 0:$0.length,boxes:$0.boxes)}
                pages.append(PDFPageData(label:input.label,sentences:sentences,ocr:input.ocr))
            }
        }
        guard pages.contains(where:{!$0.sentences.isEmpty}) else{throw EngineError(message:L("Nie znaleziono tekstu w PDF. Sprawdź jakość skanu."))}
        try JSONEncoder().encode(PDFBookIndex(pages:pages)).write(to:indexURL(id),options:.atomic)
        var cover=""
        if let page=document.page(at:0) {
            let image=page.thumbnail(of:NSSize(width:360,height:520),for:.cropBox)
            if let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:]){
                try png.write(to:AppPaths.book(id).appendingPathComponent("cover.png"),options:.atomic);cover="cover.png"
            }
        }
        return Book(id:id,title:url.deletingPathExtension().lastPathComponent,author:document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String ?? "",cover:cover,format:"pdf",pdfIndexVersion:PDFBookIndex.currentVersion)
    }
    static func textLines(_ page:PDFPage)->[PDFTextLine] {
        guard let raw=page.string else{return []};var result:[PDFTextLine]=[]
        raw.enumerateSubstrings(in:raw.startIndex..<raw.endIndex,options:.byLines){text,range,_,_ in
            guard let text,!clean(text).isEmpty else{return};let ns=NSRange(range,in:raw)
            guard let selection=page.selection(for:ns) else{return}
            result.append(PDFTextLine(text:text,range:ns,bounds:selection.bounds(for:page)))
        }
        return result
    }
    static func runningKey(_ line:PDFTextLine,bounds:CGRect)->String? {
        guard !line.bounds.isEmpty,line.text.count<220,bounds.height>0 else{return nil}
        let y=(line.bounds.midY-bounds.minY)/bounds.height
        guard y>=0.88 || y<=0.13 else{return nil}
        // Position keeps repeated body prose separate from marginal text.
        return "\(y>0.5 ? "top":"bottom"):\(Int((y*20).rounded())):\(edgeKey(line.text))"
    }
    static func isPageNumber(_ text:String)->Bool {
        clean(text).range(of:"^[–—\\-\\s]*[0-9]+[–—\\-\\s]*$",options:.regularExpression) != nil
    }
    static func edgeKey(_ text:String)->String {
        clean(text).lowercased().replacingOccurrences(of:"\\d+",with:"#",options:.regularExpression)
            .replacingOccurrences(of:"[^\\p{L}#]+",with:"",options:.regularExpression)
    }
    static func segment(_ raw:String,excluding:[NSRange],geometry:(NSRange)->[CGRect])->[PDFSentenceData] {
        let (normalized,offsets)=normalizedText(raw,excluding:excluding)
        guard !normalized.isEmpty else{return []}
        let tokenizer=NLTokenizer(unit:.sentence);tokenizer.string=normalized
        if let language=NLLanguageRecognizer.dominantLanguage(for:normalized){tokenizer.setLanguage(language)}
        var result:[PDFSentenceData]=[]
        tokenizer.enumerateTokens(in:normalized.startIndex..<normalized.endIndex){range,_ in
            let token=NSRange(range,in:normalized);var start=token.location
            let normalizedSource=normalized as NSString
            while start<NSMaxRange(token) {
                var end=min(start+1000,NSMaxRange(token))
                if end<NSMaxRange(token){let space=normalizedSource.rangeOfCharacter(from:.whitespacesAndNewlines,options:.backwards,range:NSRange(location:start,length:end-start));if space.location>start && space.location != NSNotFound{end=NSMaxRange(space)}}
                let tokenPart=NSRange(location:start,length:end-start)
                let sourceRange=NSRange(location:offsets[start],length:offsets[end-1]+1-offsets[start])
                // Use normalized speech text, not the encompassing source range which may contain skipped matter.
                let text=clean(normalizedSource.substring(with:tokenPart))
                if text.contains(where:{$0.isLetter}) {
                    let pieces=subtract(excluding,from:sourceRange)
                    let boxes=pieces.flatMap{geometry($0)}.filter{!$0.isEmpty && !$0.isInfinite}
                    result.append(PDFSentenceData(text:text,start:sourceRange.location,length:sourceRange.length,boxes:boxes))
                }
                start=end
            }
            return true
        }
        return result
    }
    static func subtract(_ exclusions:[NSRange],from range:NSRange)->[NSRange] {
        var pieces=[range]
        for excluded in exclusions {
            pieces=pieces.flatMap{piece->[NSRange] in
                let overlap=NSIntersectionRange(piece,excluded);guard overlap.length>0 else{return [piece]}
                var parts:[NSRange]=[]
                if overlap.location>piece.location{parts.append(NSRange(location:piece.location,length:overlap.location-piece.location))}
                if NSMaxRange(overlap)<NSMaxRange(piece){parts.append(NSRange(location:NSMaxRange(overlap),length:NSMaxRange(piece)-NSMaxRange(overlap)))}
                return parts
            }
        }
        return pieces
    }
    /// Layout whitespace is collapsed without losing UTF-16 offsets into the PDF text layer.
    static func normalizedText(_ raw:String,excluding:[NSRange]=[])->(String,[Int]) {
        let units=Array(raw.utf16);var output:[UInt16]=[],offsets:[Int]=[]
        var skip=[Bool](repeating:false,count:units.count)
        for r in excluding where r.location>=0 && r.location<units.count{for i in r.location..<min(NSMaxRange(r),units.count){skip[i]=true}}
        var i=0
        while i<units.count {
            let unit=units[i]
            if skip[i]{i+=1;continue}
            let space=UnicodeScalar(unit).map{CharacterSet.whitespacesAndNewlines.contains($0)} ?? false
            // Heal line-end hyphenation in the tokenized text too.
            if [45,0x2010,0x00ad].contains(unit),i+1<units.count {
                var next=i+1
                while next<units.count,UnicodeScalar(units[next]).map({CharacterSet.whitespacesAndNewlines.contains($0)})==true{next+=1}
                if next>i+1,next<units.count,UnicodeScalar(units[next]).map({CharacterSet.lowercaseLetters.contains($0)})==true{i=next;continue}
            }
            if unit==0x00ad{i+=1;continue}
            if space {if !output.isEmpty,output.last != 32{output.append(32);offsets.append(i)}}
            else{output.append(unit);offsets.append(i)}
            i+=1
        }
        while output.last==32{output.removeLast();offsets.removeLast()}
        return (String(decoding:output,as:UTF16.self),offsets)
    }
    static func clean(_ text:String)->String {
        text.replacingOccurrences(of:"\u{00ad}",with:"")
            .replacingOccurrences(of:"([\\p{L}])[-‐]\\s*\\n\\s*([\\p{Ll}])",with:"$1$2",options:.regularExpression)
            .replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func remapLocator(_ locator:String,from old:PDFBookIndex,to new:PDFBookIndex)->String {
        let parts=locator.split(separator:":");guard parts.count==3,parts[0]=="pdf",let page=Int(parts[1]),let sentence=Int(parts[2]),new.pages.indices.contains(page) else{return locator}
        guard old.pages.indices.contains(page),old.pages[page].sentences.indices.contains(sentence) else{return "pdf:\(page):0"}
        let before=old.pages[page].sentences[sentence],candidates=new.pages[page].sentences
        guard !candidates.isEmpty else{return "pdf:\(page):0"}
        let words=Set(before.text.lowercased().split(whereSeparator:{!$0.isLetter}).map(String.init))
        let best=candidates.enumerated().max{a,b in
            func score(_ item:PDFSentenceData)->Double{
                let other=Set(item.text.lowercased().split(whereSeparator:{!$0.isLetter}).map(String.init))
                let common=Double(words.intersection(other).count)/Double(max(1,words.union(other).count))
                let overlap=before.start>=0 && item.start>=0 ? Double(NSIntersectionRange(NSRange(location:before.start,length:before.length),NSRange(location:item.start,length:item.length)).length)/Double(max(1,before.length)):0
                return common+overlap
            }
            return score(a.element)<score(b.element)
        }?.offset ?? 0
        return "pdf:\(page):\(best)"
    }
    static func recognizeLines(_ page:PDFPage) throws->[PDFTextLine] {
        let bounds=page.bounds(for:.cropBox),scale=min(2.5,2200/max(bounds.width,bounds.height))
        let image=page.thumbnail(of:NSSize(width:bounds.width*scale,height:bounds.height*scale),for:.cropBox)
        var rect=NSRect(origin:.zero,size:image.size)
        guard let cg=image.cgImage(forProposedRect:&rect,context:nil,hints:nil) else{return []}
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.usesLanguageCorrection=true
        let supported=try request.supportedRecognitionLanguages();request.recognitionLanguages=["pl-PL","en-US"].filter{supported.contains($0)};request.automaticallyDetectsLanguage=true
        try VNImageRequestHandler(cgImage:cg,options:[:]).perform([request])
        let observations=(request.results ?? []).sorted{abs($0.boundingBox.midY-$1.boundingBox.midY)>0.012 ? $0.boundingBox.midY>$1.boundingBox.midY:$0.boundingBox.minX<$1.boundingBox.minX}
        var result:[PDFTextLine]=[],offset=0
        for observation in observations {
            guard let candidate=observation.topCandidates(1).first,candidate.confidence>0.2 else{continue}
            let b=observation.boundingBox,value=candidate.string
            result.append(PDFTextLine(text:value,range:NSRange(location:offset,length:(value as NSString).length),bounds:CGRect(x:bounds.minX+b.minX*bounds.width,y:bounds.minY+b.minY*bounds.height,width:b.width*bounds.width,height:b.height*bounds.height)))
            offset += (value as NSString).length+1
        }
        return result
    }
    static func recognize(_ page:PDFPage) throws->[PDFSentenceData] {
        let lines=try recognizeLines(page),raw=lines.map{$0.text}.joined(separator:"\n")
        return segment(raw,excluding:[]){range in lines.filter{NSIntersectionRange($0.range,range).length>0}.map{$0.bounds}}
    }
}
