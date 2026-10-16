import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// Serves only bundled web assets and imported EPUBs; never arbitrary filesystem paths.
final class BookScheme: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {return}
        do {
            let parts = url.pathComponents.filter { $0 != "/" }
            let file: URL
            if parts.first == "web" {
                let root = Bundle.main.resourceURL!.appendingPathComponent("Web")
                file = parts.dropFirst().reduce(root) {$0.appendingPathComponent($1)}.standardizedFileURL
                guard file.path.hasPrefix(root.path + "/") else {throw EngineError(message:L("Niedozwolona ścieżka"))}
            } else if parts.count == 3, parts.first == "books", parts.last == "source.epub", UUID(uuidString: parts[1]) != nil {
                file = AppPaths.source(parts[1])
            } else {throw EngineError(message:L("Nieznany zasób"))}
            let data = try Data(contentsOf: file)
            let ext = file.pathExtension
            let mime: String
            switch ext {case "js":mime="text/javascript";case "html":mime="text/html";case "css":mime="text/css";case "epub":mime="application/epub+zip";default:mime=UTType(filenameExtension:ext)?.preferredMIMEType ?? "application/octet-stream"}
            let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: ["js","html","css"].contains(ext) ? "utf-8" : nil)
            task.didReceive(response); task.didReceive(data); task.didFinish()
        } catch {task.didFailWithError(error)}
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class ReaderController: NSObject, WKScriptMessageHandler, WKNavigationDelegate, ReaderControlling {
    weak var model: AppModel?
    let webView: WKWebView
    let bookID: String
    private var ready = false
    init(model: AppModel, bookID: String) {
        self.model = model; self.bookID = bookID
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BookScheme(), forURLScheme: "talkiebook")
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(self, name: "reader")
        webView.navigationDelegate = self
        webView.setValue(false, forKey:"drawsBackground")
        webView.load(URLRequest(url: URL(string:"talkiebook://local/web/reader.html")!))
    }
    func call(_ name: String, _ args: [Any] = []) {
        guard ready else {return}
        let data = try? JSONSerialization.data(withJSONObject: args, options: [.fragmentsAllowed])
        guard let data, let json = String(data: data, encoding:.utf8) else {return}
        webView.evaluateJavaScript("void Promise.resolve(window.reader.\(name)(...\(json))).catch(e => window.webkit.messageHandlers.reader.postMessage({type:'error',message:String(e.message || e)}))") { [weak self] _, error in
            if let self, self.model?.activeID == self.bookID, let error {self.model?.readerError(error.localizedDescription)}
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String:Any], let type = body["type"] as? String,
              let model, model.activeID == bookID else {return}
        if type == "ready" {
            ready = true
            let book = model.activeBook!
            let marks = model.data.marks.filter {$0.bookID == bookID && $0.kind != "bookmark"}.map { ["value":$0.cfi,"color":$0.color] }
            call("open", ["talkiebook://local/books/\(bookID)/source.epub", book.location, model.webPreferences, marks])
        } else {model.receive(type, body)}
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {model?.readerError(error.localizedDescription)}
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {model?.readerError(error.localizedDescription)}
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
        guard let url = action.request.url else {decisionHandler(.cancel);return}
        if ["talkiebook","blob","about"].contains(url.scheme ?? "") {decisionHandler(.allow)}
        else {decisionHandler(.cancel)}
    }
    func dispose() {webView.configuration.userContentController.removeScriptMessageHandler(forName:"reader");webView.stopLoading()}
}
struct ReaderWeb: NSViewRepresentable {
    @ObservedObject var model: AppModel
    let bookID: String
    func makeCoordinator() -> ReaderController {ReaderController(model:model,bookID:bookID)}
    func makeNSView(context: Context) -> WKWebView {model.reader=context.coordinator;return context.coordinator.webView}
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator:ReaderController) {coordinator.dispose()}
}
