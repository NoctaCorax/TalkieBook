import SwiftUI
import AppKit

final class AppDelegate:NSObject,NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification:Notification){NSApp.setActivationPolicy(.regular);UpdateService.shared.start()}
    func application(_ sender:NSApplication,openFiles filenames:[String]) {for path in filenames{AppModel.shared.importFile(URL(fileURLWithPath:path))};sender.reply(toOpenOrPrint:.success)}
    func applicationWillTerminate(_ notification:Notification){AppModel.shared.shutdown()}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
}
@main
struct TalkieBookApp:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model=AppModel.shared
    var body:some Scene {
        WindowGroup("TalkieBook",id:"main") {ContentView(model:model).environment(\.locale,Locale(identifier:model.language))}
        .defaultSize(width:1180,height:820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after:.appInfo){CheckUpdatesButton()}
            CommandGroup(replacing:.newItem){
                Button(L("Importuj książkę…")){model.chooseFiles()}.keyboardShortcut("o")
                Button(L("Wklej tekst…")){model.showPaste=true}.keyboardShortcut("n")
                Divider()
                Button(L("Biblioteka")){model.closeBook()}.keyboardShortcut("l")
            }
            CommandGroup(replacing:.textEditing){
                Button(L("Szukaj w książce")){if model.activeID != nil{model.panel = .search}}.keyboardShortcut("f").disabled(model.activeID==nil)
            }
            CommandMenu(L("Czytanie")){
                Button(model.isPlaying ? L("Wstrzymaj"):L("Czytaj")){model.togglePlayback()}.keyboardShortcut("p",modifiers:[.command,.shift]).disabled(!model.ready)
                Button(L("Poprzednie zdanie")){model.stepSentence(-1)}.keyboardShortcut(.leftArrow,modifiers:[.command,.option]).disabled(!model.ready)
                Button(L("Następne zdanie")){model.stepSentence(1)}.keyboardShortcut(.rightArrow,modifiers:[.command,.option]).disabled(!model.ready)
                Divider()
                Button(L("Dodaj zakładkę")){model.reader?.call("bookmark")}.keyboardShortcut("d").disabled(!model.ready)
                Button(L("Wygląd i kolor strony")){model.showSettings=true}.keyboardShortcut("t",modifiers:[.command,.shift]).disabled(!model.ready)
            }
        }
    }
}
