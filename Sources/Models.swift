import Foundation
import SwiftUI
import AppKit

struct Book: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var author: String
    var cover: String = ""
    var fingerprint: String = ""
    var added = Date()
    var lastOpened: Date?
    var location = ""
    var speechLocation = ""
    var progress: Double = 0
    var status = "W trakcie"
    var collection = ""
    var format: String? = nil
    var pdfIndexVersion: Int? = nil
    var isPDF: Bool { format == "pdf" }
}
struct Mark: Codable, Identifiable {
    var id = UUID().uuidString
    var bookID: String
    var cfi: String
    var text: String
    var note = ""
    var kind = "bookmark"
    var color = "#d6b65b"
    var created = Date()
}
struct Preferences: Codable, Equatable {
    var paper = "cream"
    var appearance = "system"
    var font = "Charter"
    var fontSize: Double = 21
    var lineHeight: Double = 1.65
    var margin: Double = 8
    var letterSpacing: Double = 0
    var wordSpacing: Double = 0
    var columns = 1
    var flow = "paginated"
    var bold = false
    var justify = false
    var follow = true
    var skipCode = true
    var skipNotes = true
    var speed: Float = 1
}
struct LibraryData: Codable {
    var books: [Book] = []
    var marks: [Mark] = []
    var collections: [String] = []
    var preferences = Preferences()
}
struct Sentence: Identifiable {
    var id: Int
    var text: String
    var cfi: String
}
struct TOCItem: Identifiable {
    var id = UUID()
    var label: String
    var href: String
    var depth: Int
}
struct SearchHit: Identifiable {
    var id = UUID()
    var cfi: String
    var text: String
}
enum Panel: String { case contents, search, marks }

extension Color {
    static let moss = Color(red: 0.37, green: 0.44, blue: 0.31)
}
enum AppPaths {
    static let root: URL = {
        if let path=ProcessInfo.processInfo.environment["TALKIEBOOK_DATA_DIR"] {return URL(fileURLWithPath:path,isDirectory:true)}
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lektura", isDirectory: true)
    }()
    static let books = root.appendingPathComponent("Books", isDirectory: true)
    static let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Lektura/Audio", isDirectory: true)
    static let library = root.appendingPathComponent("library.json")
    static func book(_ id: String) -> URL { books.appendingPathComponent(id, isDirectory: true) }
    static func source(_ id: String) -> URL { book(id).appendingPathComponent("source.epub") }
}
