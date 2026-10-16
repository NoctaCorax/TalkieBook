import SwiftUI
import AppKit
import AVFoundation
import CryptoKit
import UniformTypeIdentifiers

final class AppModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AppModel()
    @Published var data = LibraryData()
    @Published var activeID: String?
    @Published var section = "Start"
    @Published var libraryQuery = ""
    @Published var sort = "Ostatnie"
    @Published var listLayout = false
    @Published var panel: Panel?
    @Published var toc: [TOCItem] = []
    @Published var searchHits: [SearchHit] = []
    @Published var bookQuery = ""
    @Published var searching = false
    @Published var ready = false
    @Published var error: String?
    @Published var notice = ""
    @Published var importing = 0
    @Published var showPaste = false
    @Published var showCollection = false
    @Published var showNote = false
    @Published var showSettings = false
    @Published var settingsTab = 0
    @Published var selectedText = ""
    @Published var selectedCFI = ""
    @Published var noteText = ""
    @Published var isPlaying = false
    @Published var buffering = false
    @Published var currentText = ""
    @Published var sentenceIndex = 0
    @Published var sentenceCount = 0
    @Published var chapterLabel = ""
    @Published var currentFraction: Double = 0
    @Published var sleepUntil: Date?
    @Published var chrome = true
    var reader: (any ReaderControlling)?
    @Published var language = UserDefaults.standard.string(forKey:"interfaceLanguage") ?? (Locale.preferredLanguages.first?.hasPrefix("pl") == true ? "pl":"en")
    @Published var pdfMode = UserDefaults.standard.string(forKey:"pdfMode") ?? "original"
    @Published var importProgress = ""
    private let pdfImportQueue = DispatchQueue(label:"app.talkiebook.pdf-import",qos:.userInitiated)

    func setLanguage(_ value:String){language=value;UserDefaults.standard.set(value,forKey:"interfaceLanguage");notice="";applyPreferences()}
    func setPDFMode(_ value:String){pdfMode=value;UserDefaults.standard.set(value,forKey:"pdfMode");reader?.call("settings",[webPreferences])}
    let engine = Engine()
    private var saveJob: DispatchWorkItem?
    private var searchJob: DispatchWorkItem?
    private var timer: Timer?
    private var audio: AVAudioPlayer?
    private var sentences: [Sentence] = []
    private var visibleChapter = 0
    private var spoken: [Sentence] = []
    private var spokenChapter = 0
    private var audioFiles: [Int: URL] = [:]
    private var pending = Set<Int>()
    private var speechToken = UUID()
    private var nextChapterPending = false
    private var startingAtCFI: String?

    var activeBook: Book? {data.books.first {$0.id == activeID}}
    var dark: Bool {
        if data.preferences.appearance == "dark" {return true}
        if data.preferences.appearance == "light" {return false}
        return NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
    }
    var paperColors: (Color,Color) {
        switch (data.preferences.paper,dark) {
        case ("white",false):return (Color(red:1,green:0.996,blue:0.984),Color(red:0.145,green:0.149,blue:0.165))
        case ("cream",false):return (Color(red:0.965,green:0.937,blue:0.875),Color(red:0.22,green:0.20,blue:0.16))
        case ("sepia",false):return (Color(red:0.918,green:0.847,blue:0.725),Color(red:0.275,green:0.216,blue:0.149))
        case ("gray",false):return (Color(red:0.91,green:0.93,blue:0.934),Color(red:0.18,green:0.22,blue:0.24))
        case ("cream",true):return (Color(red:0.145,green:0.133,blue:0.114),Color(red:0.914,green:0.875,blue:0.808))
        case ("sepia",true):return (Color(red:0.169,green:0.129,blue:0.102),Color(red:0.898,green:0.804,blue:0.69))
        case ("gray",true):return (Color(red:0.125,green:0.141,blue:0.153),Color(red:0.843,green:0.875,blue:0.882))
        default:return (Color(red:0.106,green:0.11,blue:0.125),Color(red:0.89,green:0.894,blue:0.906))
        }
    }
    var webPreferences: [String: Any] {
        var result = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(data.preferences))) as? [String:Any] ?? [:]
        result["dark"] = dark
        result["language"] = language
        return result
    }
    var visibleBooks: [Book] {
        let filtered = data.books.filter {book in
            let category = section == "Start" || section == "Wszystkie" || book.status == section || book.collection == section
            return category && (libraryQuery.isEmpty || (book.title+" "+book.author).localizedCaseInsensitiveContains(libraryQuery))
        }
        return filtered.sorted {a,b in
            switch sort {case "Tytuł":return a.title.localizedStandardCompare(b.title) == .orderedAscending
            case "Autor":return a.author.localizedStandardCompare(b.author) == .orderedAscending
            default:return (a.lastOpened ?? a.added) > (b.lastOpened ?? b.added)}
        }
    }
    var bookMarks: [Mark] {data.marks.filter {$0.bookID == activeID}.sorted {$0.created > $1.created}}
    override init() {
        super.init()
        do {
            for folder in [AppPaths.root,AppPaths.books,AppPaths.cache] {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}
            if FileManager.default.fileExists(atPath:AppPaths.library.path) {
                do {data = try JSONDecoder().decode(LibraryData.self,from:Data(contentsOf:AppPaths.library))}
                catch {self.error=String(format:L("Nie udało się odczytać biblioteki. Zachowano plik library.json. %@"),error.localizedDescription)}
            }
        } catch {self.error=error.localizedDescription}
        timer = Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) {[weak self] _ in
            guard let self else {return}
            if let deadline=self.sleepUntil,Date()>=deadline {self.pause();self.sleepUntil=nil;self.notice=L("Odtwarzanie zatrzymane przez wyłącznik czasowy.")}
        }
        if data.books.isEmpty && error == nil {
            DispatchQueue.main.async {[weak self] in self?.addText(Self.welcome,title:"Witaj w TalkieBook",open:false)}
        }
        NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) {[weak self] _ in self?.applyPreferences()}
    }
    func save(immediate: Bool = false) {
        saveJob?.cancel()
        let job = DispatchWorkItem {[weak self] in
            guard let self else {return}
            do {let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];try encoder.encode(self.data).write(to:AppPaths.library,options:.atomic)}
            catch {self.error=String(format:L("Nie udało się zapisać biblioteki: %@"),error.localizedDescription)}
        }
        if immediate {job.perform()} else {saveJob=job;DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:job)}
    }
    func update(_ id: String, _ edit: (inout Book)->Void) {
        if let i=data.books.firstIndex(where:{$0.id==id}) {edit(&data.books[i]);save()}
    }
    func open(_ book: Book) {
        stop()
        reader?.dispose();reader=nil
        activeID=book.id;ready=false;toc=[];searchHits=[];bookQuery="";panel=nil;selectedText="";selectedCFI=""
        currentFraction=book.progress;chapterLabel="";sentences=[];chrome=true;startingAtCFI=book.speechLocation.isEmpty ? nil:book.speechLocation
        update(book.id) {$0.lastOpened=Date()}
    }
    func closeBook() {stop();reader?.dispose();reader=nil;activeID=nil;ready=false;save(immediate:true)}
    func applyPreferences() {
        reader?.call("settings",[webPreferences]);audio?.rate=data.preferences.speed;save()
    }
    func chooseFiles() {
        let p=NSOpenPanel();p.allowedContentTypes=[UTType(filenameExtension:"epub") ?? .data,.plainText,.pdf];p.allowsMultipleSelection=true;p.canChooseDirectories=false
        p.message=L("Wybierz pliki EPUB, PDF lub TXT bez DRM.")
        if p.runModal() == .OK {for url in p.urls {importFile(url)}}
    }
    func importFile(_ url: URL) {
        let ext=url.pathExtension.lowercased()
        guard ["epub","txt","pdf"].contains(ext) else {error=L("Obsługiwane są pliki EPUB, PDF i TXT.");return}
        do {
            let attributes=try url.resourceValues(forKeys:[.fileSizeKey])
            guard (attributes.fileSize ?? 0)<500*1024*1024 else {throw EngineError(message:L("Plik przekracza limit 500 MB."))}
            let hash=SHA256.hash(data:try Data(contentsOf:url)).map{String(format:"%02x",$0)}.joined()
            if let existing=data.books.first(where:{$0.fingerprint==hash}) {open(existing);notice=L("Ta książka jest już w bibliotece.");return}
            let id=UUID().uuidString, folder=AppPaths.book(id)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            if ext=="pdf" {
                let target=PDFService.sourceURL(id)
                try FileManager.default.copyItem(at:url,to:target)
                importing+=1
                pdfImportQueue.async {[weak self] in
                    do {
                        var book=try PDFService.importDocument(at:target,id:id) {current,total in
                            DispatchQueue.main.async {self?.importProgress=String(format:L("PDF: strona %d z %d"),current,total)}
                        }
                        book.title=url.deletingPathExtension().lastPathComponent;book.fingerprint=hash
                        DispatchQueue.main.async {guard let self else{return};self.importing-=1;self.importProgress=""
                            if self.data.books.contains(where:{$0.fingerprint==hash}){try? FileManager.default.removeItem(at:folder);return}
                            self.data.books.append(book);self.save();self.notice=L("Dodano książkę do biblioteki.")
                        }
                    }catch{DispatchQueue.main.async {self?.importing-=1;self?.importProgress="";self?.error=error.localizedDescription;try? FileManager.default.removeItem(at:folder)}}
                }
                return
            }
            var req:[String:Any]=["cmd":"inspect","path":AppPaths.source(id).path]
            if ext=="epub" {try FileManager.default.copyItem(at:url,to:AppPaths.source(id))}
            else {req=["cmd":"text","source":url.path,"title":url.deletingPathExtension().lastPathComponent,"path":AppPaths.source(id).path]}
            importing+=1
            engine.request(req) {[weak self] result in
                guard let self else {return};self.importing-=1
                switch result {
                case .success(let meta):
                    // A second import may have completed while this one was queued.
                    if self.data.books.contains(where:{$0.fingerprint==hash}) {try? FileManager.default.removeItem(at:folder);return}
                    self.data.books.append(Book(id:id,title:meta["title"] as? String ?? L("Książka"),author:meta["author"] as? String ?? "",cover:meta["cover"] as? String ?? "",fingerprint:hash));self.save();self.notice=L("Dodano książkę do biblioteki.")
                case .failure(let e):try? FileManager.default.removeItem(at:folder);self.error=e.localizedDescription
                }
            }
        } catch {self.error=error.localizedDescription}
    }
    func addText(_ text: String, title: String, open shouldOpen: Bool = true) {
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {error=L("Wklej tekst do przeczytania.");return}
        let id=UUID().uuidString,folder=AppPaths.book(id)
        do {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}catch{self.error=error.localizedDescription;return}
        importing+=1
        engine.request(["cmd":"text","text":text,"title":title.isEmpty ? L("Wklejony tekst"):title,"path":AppPaths.source(id).path]) {[weak self] result in
            guard let self else {return};self.importing-=1
            switch result {
            case .success(let meta):let book=Book(id:id,title:meta["title"] as? String ?? title,author:L("Twój tekst"));self.data.books.append(book);self.save();if shouldOpen {self.open(book)}
            case .failure(let e):try? FileManager.default.removeItem(at:folder);self.error=e.localizedDescription
            }
        }
    }
    func receive(_ type: String, _ value:[String:Any]) {
        switch type {
        case "opened":ready=true;notice=""
        case "error":readerError(value["message"] as? String ?? L("Błąd czytnika."))
        case "toc":toc=(value["items"] as? [[String:Any]] ?? []).map {TOCItem(label:$0["label"] as? String ?? L("Rozdział"),href:$0["href"] as? String ?? "",depth:$0["depth"] as? Int ?? 0)}
        case "location":
            guard let id=activeID else {return}
            let cfi=value["cfi"] as? String ?? ""
            currentFraction=min(1,max(0,value["fraction"] as? Double ?? 0));chapterLabel=value["label"] as? String ?? ""
            update(id) {$0.location=cfi;$0.progress=self.currentFraction}
        case "sentences":
            visibleChapter=value["chapter"] as? Int ?? 0
            sentences=(value["items"] as? [[String:Any]] ?? []).map {Sentence(id:$0["id"] as? Int ?? 0,text:$0["text"] as? String ?? "",cfi:$0["cfi"] as? String ?? "")}
        case "start":startAt(value["index"] as? Int ?? 0)
        case "end":stop();notice=L("Koniec książki.");if let id=activeID{update(id){$0.status="Skończone";$0.progress=1}}
        case "togglePlay":togglePlayback()
        case "escape":panel=nil;showSettings=false
        case "chrome":chrome.toggle()
        case "selection":selectedText=value["text"] as? String ?? "";selectedCFI=value["cfi"] as? String ?? ""
        case "focus":seekToSentence(value["index"] as? Int ?? -1)
        case "context":
            let menu=contextMenu(index:value["index"] as? Int ?? 0,cfi:value["cfi"] as? String ?? "",text:value["text"] as? String ?? "")
            menu.popUp(positioning:nil,at:NSEvent.mouseLocation,in:nil)
        case "bookmark":addBookmark(cfi:value["cfi"] as? String ?? "",text:value["text"] as? String ?? L("Zakładka"))
        case "search":searching=false;searchHits=(value["items"] as? [[String:Any]] ?? []).map {SearchHit(cfi:$0["cfi"] as? String ?? "",text:$0["text"] as? String ?? "")}
        default:break
        }
    }
    func contextMenu(index:Int,cfi:String,text:String)->NSMenu {
        selectedText=text;selectedCFI=cfi
        let menu=NSMenu(title:"TalkieBook")
        let actions:[(String,()->Void)]=[
            (L("Czytaj od tego zdania"),{[weak self] in guard let self else{return};if self.activeBook?.isPDF==true{self.reader?.call("resume",[cfi])}else{self.startAt(index)}}),
            (L("Wyróżnij fragment"),{[weak self] in self?.addHighlight()}),
            (L("Dodaj notatkę"),{[weak self] in self?.noteText="";self?.showNote=true})]
        for(title,action) in actions{menu.addItem(ClosureMenuItem(title:title,action:action))}
        return menu
    }
    func readerError(_ message:String) {
        if message.contains("AbortError") {return}
        error=String(format:L("Nie udało się wyświetlić fragmentu książki: %@"),message);buffering=false
    }
    func navigate(_ cfi:String) {startingAtCFI=nil;selectedText="";selectedCFI="";reader?.call("go",[cfi])}
    func togglePanel(_ p:Panel) {panel = panel == p ? nil:p}
    func searchBook() {
        searchJob?.cancel();searching=true
        let job=DispatchWorkItem {[weak self] in guard let self else{return};self.reader?.call("search",[self.bookQuery])}
        searchJob=job;DispatchQueue.main.asyncAfter(deadline:.now()+0.35,execute:job)
    }
    func togglePlayback() {
        guard ready else {return}
        if isPlaying {pause();return}
        if let audio, !spoken.isEmpty {isPlaying=true;buffering=false;audio.rate=data.preferences.speed;audio.play();return}
        if !spoken.isEmpty {isPlaying=true;playCurrent();return}
        if let cfi=startingAtCFI {startingAtCFI=nil;reader?.call("resume",[cfi])}
        else {reader?.call("begin",[""])}
    }
    func startAt(_ index:Int) {
        stop();spoken=sentences;spokenChapter=visibleChapter;sentenceCount=spoken.count;sentenceIndex=max(0,min(index,spoken.count-1));isPlaying=true
        if spoken.isEmpty {nextChapterPending=true;reader?.call("nextChapter",[spokenChapter]);return}
        playCurrent()
    }
    /// Seeking while paused changes the next playback position without starting audio.
    func seekToSentence(_ index:Int) {
        guard sentences.indices.contains(index) else{return}
        let playing=isPlaying
        stop();startingAtCFI=nil;selectedText="";selectedCFI=""
        spoken=sentences;spokenChapter=visibleChapter;sentenceCount=spoken.count;sentenceIndex=index
        currentText=spoken[index].text
        reader?.call("highlight",[spoken[index].cfi,false])
        if let id=activeID{update(id){$0.speechLocation=self.spoken[index].cfi}}
        isPlaying=playing
        if playing{playCurrent()}
    }
    func migratePDFLocations(_ id:String,from old:PDFBookIndex,to new:PDFBookIndex){
        guard let i=data.books.firstIndex(where:{$0.id==id}),(data.books[i].pdfIndexVersion ?? 1)<new.version else{return}
        data.books[i].location=PDFService.remapLocator(data.books[i].location,from:old,to:new)
        data.books[i].speechLocation=PDFService.remapLocator(data.books[i].speechLocation,from:old,to:new)
        for mark in data.marks.indices where data.marks[mark].bookID==id{data.marks[mark].cfi=PDFService.remapLocator(data.marks[mark].cfi,from:old,to:new)}
        data.books[i].pdfIndexVersion=new.version
        if activeID==id{startingAtCFI=data.books[i].speechLocation.isEmpty ? nil:data.books[i].speechLocation}
        save(immediate:true)
    }
    private func playCurrent() {
        guard isPlaying,spoken.indices.contains(sentenceIndex) else {return}
        let s=spoken[sentenceIndex];currentText=s.text;buffering=true
        if let file=audioFiles[sentenceIndex] {play(file,sentence:s)}
        else {prepare(sentenceIndex)}
        prepare(sentenceIndex+1);prepare(sentenceIndex+2)
        for key in Array(audioFiles.keys) where key<sentenceIndex-2 || key>sentenceIndex+3 {audioFiles.removeValue(forKey:key)}
    }
    private func prepare(_ index:Int) {
        guard spoken.indices.contains(index),audioFiles[index]==nil,!pending.contains(index) else{return}
        pending.insert(index);let token=speechToken;let s=spoken[index]
        engine.request(["cmd":"synthesize","text":s.text,"cache":AppPaths.cache.path],cancellable:true) {[weak self] result in
            guard let self,self.speechToken==token else{return};self.pending.remove(index)
            switch result {
            case .success(let result):
                guard let path=result["path"] as? String else{return}
                self.audioFiles[index]=URL(fileURLWithPath:path)
                if self.isPlaying && self.sentenceIndex==index && self.buffering {self.play(URL(fileURLWithPath:path),sentence:s)}
            case .failure(let error):self.pause();self.error=String(format:L("Nie udało się wygenerować mowy: %@"),error.localizedDescription)
            }
        }
    }
    private func play(_ url:URL,sentence:Sentence) {
        do {
            let player=try AVAudioPlayer(contentsOf:url);player.delegate=self;player.enableRate=true;player.rate=data.preferences.speed;player.prepareToPlay()
            audio=player;buffering=false
            reader?.call("highlight",[sentence.cfi,true])
            if let id=activeID{update(id){$0.speechLocation=sentence.cfi}}
            if !player.play(){throw EngineError(message:L("Nie udało się uruchomić odtwarzacza."))}
        } catch {pause();self.error=error.localizedDescription}
    }
    func audioPlayerDidFinishPlaying(_ player:AVAudioPlayer,successfully flag:Bool) {
        guard audio===player,isPlaying else{return}
        audio=nil
        if !flag {pause();error=L("Odtwarzanie zostało przerwane.");return}
        sentenceIndex+=1
        if sentenceIndex>=spoken.count {nextChapterPending=true;buffering=true;reader?.call("nextChapter",[spokenChapter])}
        else {playCurrent()}
    }
    func audioPlayerDecodeErrorDidOccur(_ player:AVAudioPlayer,error:Error?) {pause();self.error=error?.localizedDescription ?? L("Uszkodzony fragment audio.")}
    func pause() {isPlaying=false;buffering=false;audio?.pause();save()}
    func stop() {
        audio?.stop();audio=nil;isPlaying=false;buffering=false;spoken=[];audioFiles=[:];pending=[];speechToken=UUID();engine.invalidate();currentText="";sentenceCount=0;sentenceIndex=0;nextChapterPending=false
        reader?.call("highlight",["",false])
    }
    func stepSentence(_ delta:Int) {
        if spoken.isEmpty {reader?.call("begin",[""]);return}
        audio?.stop();audio=nil
        let next=sentenceIndex+delta
        if next>=spoken.count {isPlaying=true;buffering=true;reader?.call("nextChapter",[spokenChapter]);return}
        sentenceIndex=max(0,next);isPlaying=true;playCurrent()
    }
    func followVoice() {
        guard spoken.indices.contains(sentenceIndex) else{return}
        data.preferences.follow=true;applyPreferences();reader?.call("highlight",[spoken[sentenceIndex].cfi,true])
    }
    func addBookmark(cfi:String,text:String) {
        guard let id=activeID,!cfi.isEmpty else{return}
        if data.marks.contains(where:{$0.bookID==id&&$0.kind=="bookmark"&&$0.cfi==cfi}) {notice=L("To miejsce ma już zakładkę.");return}
        data.marks.append(Mark(bookID:id,cfi:cfi,text:text));save();notice=L("Dodano zakładkę.")
    }
    func addHighlight(note:String="",color:String="#d6b65b") {
        guard let id=activeID,!selectedCFI.isEmpty else{return}
        let mark=Mark(bookID:id,cfi:selectedCFI,text:selectedText,note:note,kind:note.isEmpty ? "highlight":"note",color:color)
        data.marks.append(mark);reader?.call("annotation",[["value":mark.cfi,"color":mark.color]]);save();notice=note.isEmpty ? L("Wyróżniono fragment."):L("Zapisano notatkę.");selectedText="";selectedCFI=""
    }
    func removeMark(_ mark:Mark) {data.marks.removeAll{$0.id==mark.id};if mark.kind != "bookmark" {reader?.call("removeAnnotation",[mark.cfi])};save()}
    func addCollection(_ name:String) {let name=name.trimmingCharacters(in:.whitespacesAndNewlines);guard !name.isEmpty,!data.collections.contains(name) else{return};data.collections.append(name);section=name;save()}
    func removeBook(_ book:Book) {
        do {
            if activeID==book.id{closeBook()}
            if FileManager.default.fileExists(atPath:AppPaths.book(book.id).path) {try FileManager.default.trashItem(at:AppPaths.book(book.id),resultingItemURL:nil)}
            data.books.removeAll{$0.id==book.id};data.marks.removeAll{$0.bookID==book.id};save()
        }catch{self.error=error.localizedDescription}
    }
    func exportSource(_ book:Book) {
        let panel=NSSavePanel();panel.allowedContentTypes=[book.isPDF ? .pdf:(UTType(filenameExtension:"epub") ?? .data)];panel.nameFieldStringValue=book.title+(book.isPDF ? ".pdf":".epub")
        if panel.runModal() == .OK,let url=panel.url {do{if FileManager.default.fileExists(atPath:url.path){try FileManager.default.removeItem(at:url)};try FileManager.default.copyItem(at:book.isPDF ? PDFService.sourceURL(book.id):AppPaths.source(book.id),to:url)}catch{self.error=error.localizedDescription}}
    }
    func shutdown() {pause();save(immediate:true);engine.shutdown()}
    static let welcome = """
    Twoja biblioteka. Twój rytm.

    Witaj w TalkieBook — miejscu, w którym możesz czytać i słuchać swoich książek. Wszystko działa lokalnie na Twoim Macu. Ten krótki tekst pomoże Ci wypróbować lektora i ustawienia wyglądu.

    Naciśnij przycisk odtwarzania na dole okna. Aktualnie czytane zdanie zostanie podświetlone, a kolejne fragmenty będą przygotowywane w tle. Spacja zatrzymuje i wznawia odtwarzanie. Przyciski obok pozwalają wrócić do poprzedniego zdania lub przejść do następnego.

    Możesz zmienić kolor papieru, wybrać jasny lub ciemny wygląd, dostosować czcionkę i interlinię. Ustawienia znajdziesz pod przyciskiem wyglądu. Spróbuj kremowej strony z czcionką Charter albo ciepłego odcienia sepii.

    Aby dodać książkę, wróć do biblioteki i wybierz „Importuj książkę”. Możesz również przeciągnąć plik EPUB lub TXT do okna aplikacji. Jeśli masz sam tekst, wybierz „Wklej tekst”.

    Zaznacz fragment, aby go wyróżnić lub zapisać notatkę. Kliknięcie prawym przyciskiem myszy pozwala rozpocząć słuchanie od wybranego zdania. Twoje miejsce i zakładki zostaną zapisane automatycznie.

    To jest dobry moment, żeby zwolnić. Znaleźć wygodne miejsce, otworzyć książkę i po prostu posłuchać.
    """
}

final class ClosureMenuItem:NSMenuItem {
    let handler:()->Void
    init(title:String,action:@escaping ()->Void){handler=action;super.init(title:title,action:#selector(invoke),keyEquivalent:"");target=self}
    required init(coder:NSCoder){fatalError("Not supported")}
    @objc func invoke(){handler()}
}
