import Foundation

/// Uses native .strings resources; the override persists without changing book language.
func L(_ key:String)->String {
    let language=UserDefaults.standard.string(forKey:"interfaceLanguage") ?? (Locale.preferredLanguages.first?.hasPrefix("pl")==true ? "pl":"en")
    guard let path=Bundle.main.path(forResource:language,ofType:"lproj"),let bundle=Bundle(path:path) else{return key}
    return bundle.localizedString(forKey:key,value:key,table:"Localizable")
}
