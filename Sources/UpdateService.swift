import SwiftUI
import Combine
import Sparkle

@MainActor final class UpdateService:NSObject,ObservableObject {
    static let shared=UpdateService()
    private var controller:SPUStandardUpdaterController!
    @Published var canCheck=false
    @Published var automaticallyChecks=false
    private var observation:AnyCancellable?
    override init(){
        super.init()
        controller=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:nil,userDriverDelegate:nil)
        observation=controller.updater.publisher(for:\.canCheckForUpdates).receive(on:DispatchQueue.main).sink{[weak self] in self?.canCheck=$0}
    }
    func start(){
        controller.startUpdater()
        automaticallyChecks=controller.updater.automaticallyChecksForUpdates
    }
    func check(){controller.checkForUpdates(nil)}
    func setAutomatic(_ enabled:Bool){
        automaticallyChecks=enabled
        controller.updater.automaticallyChecksForUpdates=enabled
    }
}
struct CheckUpdatesButton:View {
    @ObservedObject private var updater=UpdateService.shared
    var body:some View {Button(L("Sprawdź aktualizacje…")){updater.check()}.disabled(!updater.canCheck)}
}
struct UpdateSettings:View {
    @ObservedObject private var updater=UpdateService.shared
    var body:some View {
        VStack(alignment:.leading,spacing:10){
            Text(L("Aktualizacje aplikacji")).font(.headline)
            CheckUpdatesButton()
            Toggle(L("Automatycznie sprawdzaj aktualizacje"),isOn:Binding(get:{updater.automaticallyChecks},set:{updater.setAutomatic($0)}))
            Text(L("Aktualizacje są pobierane z GitHuba i weryfikowane przed instalacją. Biblioteka pozostaje na Macu.")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
