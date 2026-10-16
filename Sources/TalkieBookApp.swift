import SwiftUI
import AppKit

final class AppDelegate:NSObject,NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification:Notification){NSApp.setActivationPolicy(.regular)}
    func application(_ sender:NSApplication,openFiles filenames:[String]) {for path in filenames{AppModel.shared.importFile(URL(fileURLWithPath:path))};sender.reply(toOpenOrPrint:.success)}
    func applicationWillTerminate(_ notification:Notification){AppModel.shared.shutdown()}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
}
@main
struct TalkieBookApp:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model=AppModel.shared
    var body:some Scene {
        WindowGroup("TalkieBook",id:"main") {ContentView(model:model)}
        .defaultSize(width:1180,height:820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing:.newItem){
                Button("Importuj książkę…"){model.chooseFiles()}.keyboardShortcut("o")
                Button("Wklej tekst…"){model.showPaste=true}.keyboardShortcut("n")
                Divider()
                Button("Biblioteka"){model.closeBook()}.keyboardShortcut("l")
            }
            CommandGroup(replacing:.textEditing){
                Button("Szukaj w książce"){if model.activeID != nil{model.panel = .search}}.keyboardShortcut("f").disabled(model.activeID==nil)
            }
            CommandMenu("Czytanie"){
                Button(model.isPlaying ? "Wstrzymaj":"Czytaj"){model.togglePlayback()}.keyboardShortcut("p",modifiers:[.command,.shift]).disabled(!model.ready)
                Button("Poprzednie zdanie"){model.stepSentence(-1)}.keyboardShortcut(.leftArrow,modifiers:[.command,.option]).disabled(!model.ready)
                Button("Następne zdanie"){model.stepSentence(1)}.keyboardShortcut(.rightArrow,modifiers:[.command,.option]).disabled(!model.ready)
                Divider()
                Button("Dodaj zakładkę"){model.reader?.call("bookmark")}.keyboardShortcut("d").disabled(!model.ready)
                Button("Wygląd i kolor strony"){model.showSettings=true}.keyboardShortcut("t",modifiers:[.command,.shift]).disabled(!model.ready)
            }
        }
    }
}
