import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView:View {
    @ObservedObject var model:AppModel
    @Environment(\.colorScheme) var colorScheme
    @State private var dropTarget=false
    var body:some View {
        Group {
            if let id=model.activeID {ReaderScreen(model:model,bookID:id).id(id)}
            else {LibraryScreen(model:model)}
        }
        .frame(minWidth:920,minHeight:650)
        .tint(.moss)
        .onChange(of:model.data.preferences){model.applyPreferences()}
        .onChange(of:colorScheme){model.applyPreferences()}
        .onDrop(of:[UTType.fileURL],isTargeted:$dropTarget){providers in
            for p in providers {p.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil){item,_ in
                let url:URL?
                if let data=item as? Data {url=URL(dataRepresentation:data,relativeTo:nil)} else {url=item as? URL}
                if let url {DispatchQueue.main.async{model.importFile(url)}}
            }}
            return true
        }
        .overlay {if dropTarget {RoundedRectangle(cornerRadius:16).stroke(Color.moss,lineWidth:3).padding(8).allowsHitTesting(false)}}
        .alert("TalkieBook",isPresented:Binding(get:{model.error != nil},set:{if !$0{model.error=nil}})){Button("OK"){model.error=nil}}message:{Text(model.error ?? "")}
        .sheet(isPresented:$model.showPaste){PasteSheet(model:model)}
        .sheet(isPresented:$model.showCollection){CollectionSheet(model:model)}
        .sheet(isPresented:$model.showNote){NoteSheet(model:model)}
    }
}

struct LibraryScreen:View {
    @ObservedObject var model:AppModel
    var body:some View {
        HStack(spacing:0){
            VStack(alignment:.leading,spacing:0){
                HStack(spacing:10){Image(systemName:"book.closed.fill").font(.title2).foregroundStyle(Color.moss);Text("TalkieBook").font(.system(size:23,weight:.semibold,design:.serif))}.padding(.horizontal,24).padding(.top,48).padding(.bottom,30)
                sidebarRow("Start",icon:"house")
                sidebarRow("Wszystkie",icon:"books.vertical")
                Text("BIBLIOTEKA").font(.system(size:10,weight:.semibold)).tracking(1.4).foregroundStyle(.secondary).padding(.leading,26).padding(.top,30).padding(.bottom,9)
                sidebarRow("W trakcie",icon:"book")
                sidebarRow("Chcę przeczytać",icon:"bookmark")
                sidebarRow("Skończone",icon:"checkmark.circle")
                HStack {Text("KOLEKCJE").font(.system(size:10,weight:.semibold)).tracking(1.4);Spacer();Button{model.showCollection=true}label:{Image(systemName:"plus")}.buttonStyle(.plain).help("Nowa kolekcja")}.foregroundStyle(.secondary).padding(.horizontal,26).padding(.top,30).padding(.bottom,9)
                ForEach(model.data.collections,id:\.self){name in sidebarRow(name,icon:"folder")}
                Spacer()
                VStack(alignment:.leading,spacing:10){
                    Label("Piper · MC Speech A2",systemImage:"waveform").font(.system(size:11,weight:.medium))
                    Text("Lokalnie na Twoim Macu").font(.system(size:10)).foregroundStyle(.secondary)
                }.padding(24)
            }.frame(width:218).background(Color(nsColor:.windowBackgroundColor))
            Divider()
            VStack(spacing:0){
                HStack {
                    HStack(spacing:7){Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("Szukaj w bibliotece",text:$model.libraryQuery).textFieldStyle(.plain)}.padding(9).frame(width:240).background(.quaternary.opacity(0.45),in:RoundedRectangle(cornerRadius:8))
                    Spacer()
                    Button{model.showPaste=true}label:{Label("Wklej tekst",systemImage:"doc.on.clipboard")}.buttonStyle(.borderless)
                    Button{model.chooseFiles()}label:{Label("Importuj książkę",systemImage:"plus")}.buttonStyle(.borderedProminent).controlSize(.large)
                }.padding(.horizontal,34).padding(.top,30).padding(.bottom,20)
                ScrollView {
                    VStack(alignment:.leading,spacing:26){
                        VStack(alignment:.leading,spacing:8){Text(model.section == "Start" ? "Dobrze tu wrócić." : model.section).font(.system(size:36,weight:.medium,design:.serif));Text(model.section == "Start" ? "Twoje książki, w Twoim rytmie." : "\(model.visibleBooks.count) \(model.visibleBooks.count == 1 ? "książka":"książki") w bibliotece").font(.system(size:14)).foregroundStyle(.secondary)}
                        if model.section == "Start",model.libraryQuery.isEmpty,let book=model.visibleBooks.first {
                            ContinueCard(model:model,book:book)
                        }
                        HStack {
                            Text(model.section == "Start" ? "Na Twojej półce":"Książki").font(.system(size:18,weight:.medium,design:.serif))
                            Spacer()
                            Picker("Sortowanie",selection:$model.sort){ForEach(["Ostatnie","Tytuł","Autor"],id:\.self){Text($0)}}.labelsHidden().frame(width:115)
                            Button{model.listLayout.toggle()}label:{Image(systemName:model.listLayout ? "square.grid.2x2":"list.bullet")}.buttonStyle(.borderless).help("Zmień widok biblioteki")
                        }
                        if model.visibleBooks.isEmpty {
                            VStack(spacing:15){Image(systemName:"books.vertical").font(.system(size:40,weight:.ultraLight)).foregroundStyle(Color.moss);Text(model.libraryQuery.isEmpty ? "Miejsce na Twoje książki":"Nie znaleziono książek").font(.title3);Text(model.libraryQuery.isEmpty ? "Przeciągnij EPUB lub TXT do okna albo wybierz Importuj książkę.":"Spróbuj innego tytułu lub nazwiska autora.").foregroundStyle(.secondary).multilineTextAlignment(.center)}.frame(maxWidth:.infinity,minHeight:240)
                        } else if model.listLayout {
                            LazyVStack(spacing:0){ForEach(model.visibleBooks){book in
                                Button{model.open(book)}label:{HStack(spacing:18){BookCover(book:book).frame(width:48,height:72);VStack(alignment:.leading,spacing:5){Text(book.title).font(.system(size:15,weight:.medium)).lineLimit(2);Text(book.author).foregroundStyle(.secondary)};Spacer();Text("\(Int(book.progress*100))%").monospacedDigit().foregroundStyle(.secondary);Image(systemName:"chevron.right").foregroundStyle(.tertiary)}.padding(.vertical,12).contentShape(Rectangle())}.buttonStyle(.plain).contextMenu{BookMenu(model:model,book:book)}
                                Divider()
                            }}
                        } else {
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:160,maximum:200),spacing:30,alignment:.top)],alignment:.leading,spacing:32){ForEach(model.visibleBooks){BookCard(model:model,book: $0)}}
                        }
                    }.padding(.horizontal,38).padding(.top,12).padding(.bottom,40)
                }
                HStack {if model.importing>0 {ProgressView().controlSize(.small);Text("Importuję \(model.importing) \(model.importing == 1 ? "plik":"pliki")…")}else{Text(model.notice.isEmpty ? "EPUB i TXT · bez połączenia z chmurą":model.notice)};Spacer();Text("\(model.data.books.count) na półce")}.font(.system(size:11)).foregroundStyle(.secondary).padding(.horizontal,34).padding(.vertical,12)
            }.background(Color(nsColor:.textBackgroundColor))
        }
    }
    func sidebarRow(_ title:String,icon:String)->some View {
        Button{model.section=title}label:{HStack(spacing:12){Image(systemName:icon).frame(width:19);Text(title).lineLimit(1);Spacer();if title=="Wszystkie"{Text("\(model.data.books.count)").font(.caption).foregroundStyle(.secondary)}}.font(.system(size:13,weight:model.section==title ? .medium:.regular)).padding(.horizontal,12).padding(.vertical,10).background(model.section==title ? Color.moss.opacity(0.13):Color.clear,in:RoundedRectangle(cornerRadius:8)).contentShape(Rectangle())}.buttonStyle(.plain).padding(.horizontal,14).padding(.vertical,1)
    }
}

struct BookCover:View {
    let book:Book
    var body:some View {
        GeometryReader{geo in
            if !book.cover.isEmpty,let image=NSImage(contentsOf:AppPaths.book(book.id).appendingPathComponent(book.cover)) {
                Image(nsImage:image).resizable().scaledToFit().frame(width:geo.size.width,height:geo.size.height,alignment:.bottom).clipShape(RoundedRectangle(cornerRadius:3))
            } else {
                ZStack(alignment:.leading){Rectangle().fill(Color(red:0.34,green:0.40,blue:0.32));Rectangle().fill(.black.opacity(0.15)).frame(width:6);VStack(alignment:.leading,spacing:12){Text("TALKIEBOOK").font(.system(size:8,weight:.medium)).tracking(2);Spacer();Text(book.title).font(.system(size:max(14,geo.size.width*0.12),weight:.medium,design:.serif)).lineLimit(5);Rectangle().frame(width:28,height:1).opacity(0.5);Text(book.author).font(.system(size:max(8,geo.size.width*0.065))).lineLimit(2);Spacer()}.foregroundStyle(Color(red:0.94,green:0.91,blue:0.83)).padding(max(9,geo.size.width*0.13))}.clipShape(RoundedRectangle(cornerRadius:3))
            }
        }
    }
}
struct BookCard:View {
    @ObservedObject var model:AppModel
    let book:Book
    var body:some View {
        Button{model.open(book)}label:{VStack(alignment:.leading,spacing:10){BookCover(book:book).aspectRatio(0.67,contentMode:.fit);Text(book.title).font(.system(size:13,weight:.medium)).lineLimit(2).frame(height:34,alignment:.topLeading);Text(book.author).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1);HStack{ProgressView(value:book.progress).tint(.moss);Text("\(Int(book.progress*100))%").font(.system(size:10)).foregroundStyle(.secondary).monospacedDigit()}}.contentShape(Rectangle())}.buttonStyle(.plain).contextMenu{BookMenu(model:model,book:book)}
    }
}
struct ContinueCard:View {
    @ObservedObject var model:AppModel
    let book:Book
    var body:some View {
        HStack(spacing:24){BookCover(book:book).frame(width:86,height:130);VStack(alignment:.leading,spacing:10){Text("KONTYNUUJ LEKTURĘ").font(.system(size:10,weight:.semibold)).tracking(1.5).foregroundStyle(Color.moss);Text(book.title).font(.system(size:23,weight:.medium,design:.serif)).lineLimit(2);Text(book.author).font(.system(size:13)).foregroundStyle(.secondary);HStack(spacing:12){Button("Otwórz książkę"){model.open(book)}.buttonStyle(.borderedProminent);Text("\(Int(book.progress*100))% przeczytane").font(.caption).foregroundStyle(.secondary)}};Spacer(minLength:0)}.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(Color.moss.opacity(0.065),in:RoundedRectangle(cornerRadius:12))
    }
}
struct BookMenu:View {
    @ObservedObject var model:AppModel
    let book:Book
    var body:some View {
        Button("Otwórz"){model.open(book)}
        Menu("Status"){ForEach(["W trakcie","Chcę przeczytać","Skończone"],id:\.self){s in Button(s){model.update(book.id){$0.status=s}}}}
        Menu("Kolekcja"){Button("Bez kolekcji"){model.update(book.id){$0.collection=""}};ForEach(model.data.collections,id:\.self){c in Button(c){model.update(book.id){$0.collection=c}}}}
        Divider();Button("Eksportuj plik EPUB…"){model.exportSource(book)}
        Button("Usuń z biblioteki",role:.destructive){model.removeBook(book)}
    }
}

struct ReaderScreen:View {
    @ObservedObject var model:AppModel
    let bookID:String
    var body:some View {
        VStack(spacing:0){
            HStack(spacing:16){
                Button{model.closeBook()}label:{Label("Biblioteka",systemImage:"chevron.left")}.help("Wróć do biblioteki")
                Divider().frame(height:17)
                tool("list.bullet",help:"Spis treści",active:model.panel == .contents){model.togglePanel(.contents)}
                tool("bookmark",help:"Zakładki i notatki",active:model.panel == .marks){model.togglePanel(.marks)}
                Spacer(minLength:10)
                Text(model.activeBook?.title ?? "").font(.system(size:12,weight:.medium)).lineLimit(1).foregroundStyle(.secondary)
                Spacer(minLength:10)
                tool("magnifyingglass",help:"Szukaj w książce",active:model.panel == .search){model.togglePanel(.search)}
                Button{model.showSettings.toggle()}label:{Image(systemName:"textformat.size")}.help("Kolor strony, dzień / noc i typografia").popover(isPresented:$model.showSettings,arrowEdge:.trailing){AppearancePanel(model:model).foregroundStyle(Color.primary).environment(\.colorScheme,model.dark ? .dark:.light)}
                tool("bookmark.fill",help:"Dodaj zakładkę"){model.reader?.call("bookmark")}
            }.buttonStyle(.borderless).padding(.horizontal,24).padding(.top,30).padding(.bottom,16).opacity(model.chrome ? 1:0.15)
            Divider().opacity(0.4)
            HStack(spacing:0){
                if let panel=model.panel {ReaderSidePanel(model:model,panel:panel).frame(width:290);Divider()}
                ZStack{
                    ReaderWeb(model:model,bookID:bookID)
                    if !model.ready {VStack(spacing:14){ProgressView();Text("Otwieram książkę…").font(.callout).foregroundStyle(.secondary)}.padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))}
                }
            }
            if !model.selectedText.isEmpty {
                HStack{Text(model.selectedText).font(.caption).lineLimit(1).foregroundStyle(.secondary);Spacer();Button("Wyróżnij"){model.addHighlight()};Button("Notatka"){model.noteText="";model.showNote=true};Button{model.selectedText="";model.selectedCFI=""}label:{Image(systemName:"xmark")}}.padding(.horizontal,24).padding(.vertical,8).background(.thinMaterial)
            }
            HStack{
                Button{model.reader?.call("prev")}label:{Image(systemName:"chevron.left")}.help("Poprzednia strona")
                Text(model.chapterLabel.isEmpty ? "Książka":model.chapterLabel).font(.system(size:11)).lineLimit(1).frame(maxWidth:230,alignment:.leading)
                Slider(value:Binding(get:{model.currentFraction},set:{model.currentFraction=$0}),in:0...1,onEditingChanged:{editing in if !editing{model.reader?.call("fraction",[model.currentFraction])}}).help("Miejsce w książce")
                Text("\(Int(model.currentFraction*100))%").font(.system(size:11)).monospacedDigit().frame(width:34)
                Button{model.reader?.call("next")}label:{Image(systemName:"chevron.right")}.help("Następna strona")
            }.buttonStyle(.borderless).foregroundStyle(.secondary).padding(.horizontal,28).padding(.vertical,9)
            Divider().opacity(0.4)
            PlayerBar(model:model)
        }.background(model.paperColors.0).foregroundStyle(model.paperColors.1).environment(\.colorScheme,model.dark ? .dark:.light)
    }
    func tool(_ icon:String,help:String,active:Bool=false,action:@escaping ()->Void)->some View {Button(action:action){Image(systemName:icon).foregroundStyle(active ? Color.moss:Color.primary)}.help(help)}
}

struct PlayerBar:View {
    @ObservedObject var model:AppModel
    var body:some View {
        HStack(spacing:16){
            Image(systemName:"waveform").font(.system(size:20)).foregroundStyle(Color.moss)
            VStack(alignment:.leading,spacing:4){Text(model.buffering ? "Przygotowuję głos…":model.isPlaying ? "Czytam dla Ciebie":"MC Speech · A2").font(.system(size:12,weight:.medium));Text(model.currentText.isEmpty ? "Zacznij słuchać od bieżącego miejsca":model.currentText).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)}.frame(maxWidth:.infinity,alignment:.leading)
            HStack(spacing:16){
                Button{model.stepSentence(-1)}label:{Image(systemName:"backward.end.fill")}.help("Poprzednie zdanie")
                Button{model.togglePlayback()}label:{ZStack{Circle().fill(Color.moss).frame(width:42,height:42);if model.buffering{ProgressView().controlSize(.small).tint(.white)}else{Image(systemName:model.isPlaying ? "pause.fill":"play.fill").font(.system(size:16)).foregroundStyle(.white).offset(x:model.isPlaying ? 0:1)}}}.disabled(!model.ready).help("Odtwórz / pauza · spacja")
                Button{model.stepSentence(1)}label:{Image(systemName:"forward.end.fill")}.help("Następne zdanie")
            }.buttonStyle(.plain)
            Picker("Tempo",selection:$model.data.preferences.speed){ForEach([Float(0.75),1,1.15,1.25,1.5,1.75,2],id:\.self){speed in Text(String(format:"%g×",speed)).tag(speed)}}.labelsHidden().frame(width:76).help("Tempo odtwarzania")
            Menu{Button("Wyłączony"){model.sleepUntil=nil};ForEach([5,10,15,30,45,60],id:\.self){minutes in Button("Za \(minutes) minut"){model.sleepUntil=Date().addingTimeInterval(Double(minutes)*60)}}}label:{Image(systemName:model.sleepUntil == nil ? "moon":"moon.fill")}.menuStyle(.borderlessButton).frame(width:28).help("Wyłącznik czasowy")
            Button{model.followVoice()}label:{Image(systemName:"scope")}.buttonStyle(.borderless).help("Wróć do lektora i podążaj za głosem")
        }.padding(.horizontal,28).padding(.vertical,15)
    }
}

struct ReaderSidePanel:View {
    @ObservedObject var model:AppModel
    let panel:Panel
    var body:some View {
        VStack(alignment:.leading,spacing:0){
            HStack{Text(panel == .contents ? "Spis treści":panel == .search ? "Szukaj":"Zakładki i notatki").font(.system(size:18,weight:.medium,design:.serif));Spacer();Button{model.panel=nil}label:{Image(systemName:"xmark")}.buttonStyle(.plain).foregroundStyle(.secondary)}.padding(20)
            if panel == .search {TextField("Szukaj w tej książce",text:$model.bookQuery).textFieldStyle(.roundedBorder).padding(.horizontal,16).padding(.bottom,12).onChange(of:model.bookQuery){model.searchBook()};if model.searching{ProgressView().controlSize(.small).padding(16)}}
            ScrollView{
                LazyVStack(alignment:.leading,spacing:0){
                    if panel == .contents {ForEach(model.toc){item in Button{model.navigate(item.href)}label:{Text(item.label).font(.system(size:item.depth==0 ? 13:12,weight:item.depth==0 ? .medium:.regular)).foregroundStyle(item.depth==0 ? .primary:.secondary).multilineTextAlignment(.leading).padding(.leading,CGFloat(min(item.depth,3))*12).padding(.vertical,9).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())}.buttonStyle(.plain)}}
                    if panel == .search {ForEach(model.searchHits){hit in Button{model.navigate(hit.cfi)}label:{Text(hit.text).font(.system(size:12)).lineLimit(4).multilineTextAlignment(.leading).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,12).contentShape(Rectangle())}.buttonStyle(.plain);Divider()};if !model.searching && !model.bookQuery.isEmpty && model.searchHits.isEmpty{Text("Brak wyników.").font(.callout).foregroundStyle(.secondary).padding(.vertical,16)}}
                    if panel == .marks {ForEach(model.bookMarks){mark in VStack(alignment:.leading,spacing:8){HStack{Label(mark.kind=="bookmark" ? "Zakładka":mark.kind=="note" ? "Notatka":"Wyróżnienie",systemImage:mark.kind=="bookmark" ? "bookmark":"pencil.line").font(.system(size:10,weight:.medium)).foregroundStyle(Color.moss);Spacer();Button{model.removeMark(mark)}label:{Image(systemName:"trash").font(.caption)}.buttonStyle(.plain).foregroundStyle(.secondary)};Button{model.navigate(mark.cfi)}label:{VStack(alignment:.leading,spacing:7){Text(mark.text).lineLimit(4);if !mark.note.isEmpty{Text(mark.note).italic().foregroundStyle(.secondary)}}.font(.system(size:12)).multilineTextAlignment(.leading).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain)}.padding(.vertical,12);Divider()};if model.bookMarks.isEmpty {Text("Dodaj zakładkę przyciskiem w pasku albo zaznacz tekst, aby zapisać wyróżnienie i notatkę.").font(.callout).foregroundStyle(.secondary).padding(.vertical,12)}}
                }.padding(.horizontal,20).padding(.bottom,20)
            }
        }.background(Color(nsColor:.windowBackgroundColor).opacity(0.65))
    }
}

struct AppearancePanel:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            HStack{Text("Tak, jak lubisz").font(.system(size:22,weight:.medium,design:.serif));Spacer();Button{model.showSettings=false}label:{Image(systemName:"xmark")}.buttonStyle(.plain).foregroundStyle(.secondary)}
            Picker("Ustawienia",selection:$model.settingsTab){Text("Wygląd").tag(0);Text("Czytanie").tag(1)}.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment:.leading,spacing:20){
                    if model.settingsTab==0 {
                        VStack(alignment:.leading,spacing:10){caption("KOLOR PAPIERU");HStack(spacing:12){paper("white","Biały",Color(red:1,green:0.996,blue:0.984));paper("cream","Krem",Color(red:0.965,green:0.937,blue:0.875));paper("sepia","Sepia",Color(red:0.918,green:0.847,blue:0.725));paper("gray","Szary",Color(red:0.91,green:0.93,blue:0.934))}}
                        VStack(alignment:.leading,spacing:10){caption("DZIEŃ I NOC");Picker("Wygląd",selection:$model.data.preferences.appearance){Label("Dzień",systemImage:"sun.max").tag("light");Label("Noc",systemImage:"moon").tag("dark");Label("System",systemImage:"circle.lefthalf.filled").tag("system")}.pickerStyle(.segmented).labelsHidden();Text("Każdy papier ma dopasowany wariant nocny.").font(.caption).foregroundStyle(.secondary)}
                        Divider()
                        Picker("Czcionka",selection:$model.data.preferences.font){ForEach(["Charter","Georgia","Palatino","Athelas","Iowan Old Style","Avenir Next","Helvetica Neue"],id:\.self){Text($0).font(.custom($0,size:14))}}
                        settingSlider("Wielkość tekstu",value:$model.data.preferences.fontSize,range:14...34,suffix:" pkt",format:"%.0f")
                        settingSlider("Interlinia",value:$model.data.preferences.lineHeight,range:1.2...2.3,suffix:"",format:"%.2f")
                        settingSlider("Marginesy",value:$model.data.preferences.margin,range:4...22,suffix:"%",format:"%.0f")
                        Picker("Układ",selection:$model.data.preferences.flow){Text("Strony").tag("paginated");Text("Przewijanie").tag("scrolled")}.pickerStyle(.segmented)
                        if model.data.preferences.flow=="paginated" {Picker("Kolumny",selection:$model.data.preferences.columns){Text("Jedna").tag(1);Text("Dwie").tag(2)}.pickerStyle(.segmented)}
                        DisclosureGroup("Dokładne ustawienia tekstu"){
                            VStack(spacing:14){Toggle("Pogrubienie",isOn:$model.data.preferences.bold);Toggle("Justowanie",isOn:$model.data.preferences.justify);settingSlider("Odstępy znaków",value:$model.data.preferences.letterSpacing,range:0...0.12,suffix:" em",format:"%.2f");settingSlider("Odstępy wyrazów",value:$model.data.preferences.wordSpacing,range:0...0.3,suffix:" em",format:"%.2f")}.padding(.top,12)
                        }
                    } else {
                        VStack(alignment:.leading,spacing:8){caption("LOKALNY LEKTOR");Text("MC Speech · wariant A2").font(.headline);Text("Piper przygotowuje kolejne zdania w tle. Głos i tekst pozostają na Twoim Macu.").font(.callout).foregroundStyle(.secondary)}
                        Divider()
                        Toggle("Podążaj za czytanym zdaniem",isOn:$model.data.preferences.follow)
                        Toggle("Pomijaj bloki kodu",isOn:$model.data.preferences.skipCode)
                        Toggle("Pomijaj przypisy w tekście",isOn:$model.data.preferences.skipNotes)
                        Text("Zmiana pomijanych fragmentów zaczyna obowiązywać po ponownym uruchomieniu odczytu.").font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Text("Skróty").font(.headline)
                        shortcut("Odtwórz / pauza","Spacja")
                        shortcut("Poprzednia / następna strona","← / →")
                        shortcut("Szukaj w książce","⌘F")
                        shortcut("Biblioteka","⌘L")
                        shortcut("Importuj książkę","⌘O")
                        Text("Kliknij zdanie prawym przyciskiem myszy, aby rozpocząć od niego słuchanie.").font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(.trailing,4)
            }
        }.padding(24).frame(width:365,height:610)
    }
    func caption(_ text:String)->some View {Text(text).font(.system(size:10,weight:.semibold)).tracking(1.2).foregroundStyle(.secondary)}
    func shortcut(_ text:String,_ key:String)->some View {HStack{Text(text);Spacer();Text(key).foregroundStyle(.secondary)}.font(.system(size:12))}
    func paper(_ id:String,_ title:String,_ color:Color)->some View {Button{model.data.preferences.paper=id}label:{VStack(spacing:7){ZStack{RoundedRectangle(cornerRadius:9).fill(color).frame(width:64,height:46);Text("Aa").font(.system(size:22,design:.serif)).foregroundStyle(Color.black.opacity(0.75))}.overlay{RoundedRectangle(cornerRadius:9).stroke(model.data.preferences.paper==id ? Color.moss:Color.gray.opacity(0.3),lineWidth:model.data.preferences.paper==id ? 2:0.5)};Text(title).font(.system(size:11)).foregroundStyle(.primary)}}.buttonStyle(.plain)}
    func settingSlider(_ title:String,value:Binding<Double>,range:ClosedRange<Double>,suffix:String,format:String)->some View {VStack(alignment:.leading,spacing:6){HStack{Text(title);Spacer();Text(String(format:format,value.wrappedValue)+suffix).foregroundStyle(.secondary).monospacedDigit()}.font(.system(size:12));Slider(value:value,in:range)}}
}

struct PasteSheet:View {
    @ObservedObject var model:AppModel
    @State private var title=""
    @State private var text=""
    var body:some View {VStack(alignment:.leading,spacing:18){Text("Z tekstu w lekturę").font(.system(size:28,design:.serif));Text("Wklej artykuł, opowiadanie albo dowolny tekst do posłuchania.").foregroundStyle(.secondary);TextField("Tytuł",text:$title).textFieldStyle(.roundedBorder);TextEditor(text:$text).font(.system(size:15)).padding(8).background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:8)).overlay{RoundedRectangle(cornerRadius:8).stroke(.quaternary)};HStack{Text("\(text.count) znaków").font(.caption).foregroundStyle(.secondary);Spacer();Button("Anuluj"){model.showPaste=false}.keyboardShortcut(.cancelAction);Button("Dodaj i otwórz"){model.addText(text,title:title);model.showPaste=false}.buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}.padding(28).frame(width:660,height:540)}
}
struct CollectionSheet:View {
    @ObservedObject var model:AppModel
    @State private var name=""
    var body:some View {VStack(alignment:.leading,spacing:20){Text("Nowa kolekcja").font(.title2);TextField("Nazwa kolekcji",text:$name).textFieldStyle(.roundedBorder);HStack{Spacer();Button("Anuluj"){model.showCollection=false}.keyboardShortcut(.cancelAction);Button("Utwórz"){model.addCollection(name);model.showCollection=false}.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}.padding(28).frame(width:380)}
}
struct NoteSheet:View {
    @ObservedObject var model:AppModel
    var body:some View {VStack(alignment:.leading,spacing:18){Text("Twoja notatka").font(.system(size:25,design:.serif));Text(model.selectedText).font(.callout).foregroundStyle(.secondary).lineLimit(4);TextEditor(text:$model.noteText).font(.system(size:15)).frame(height:160).padding(8).overlay{RoundedRectangle(cornerRadius:8).stroke(.quaternary)};HStack{Spacer();Button("Anuluj"){model.showNote=false}.keyboardShortcut(.cancelAction);Button("Zapisz"){model.addHighlight(note:model.noteText);model.showNote=false}.keyboardShortcut(.defaultAction).disabled(model.noteText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}.padding(28).frame(width:490)}
}
