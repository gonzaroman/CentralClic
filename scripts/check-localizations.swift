// Checks that every language in Resources/*.lproj has exactly the keys used in Sources/*.swift
// (calls to L("...")), and that each translation keeps the same format specifiers (%@, %ld, %%).
//
//   check-localizations <repo root>          → exits 1 if anything is wrong
//   check-localizations <repo root> --keys   → prints the keys found in the sources
import Foundation

let args = CommandLine.arguments
let root = URL(fileURLWithPath: args.count > 1 ? args[1] : ".")
let fm = FileManager.default

func swiftKeys() -> [String] {
    let regex = try! NSRegularExpression(pattern: #"\bL\("((?:[^"\\]|\\.)*)""#)
    var keys: [String] = []
    let sources = root.appendingPathComponent("Sources")
    for name in (try? fm.contentsOfDirectory(atPath: sources.path))?.sorted() ?? [] where name.hasSuffix(".swift") {
        let text = (try? String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)) ?? ""
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let key = String(text[Range(match.range(at: 1), in: text)!])
            if !keys.contains(key) { keys.append(key) }
        }
    }
    return keys
}

func specifiers(_ s: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: #"%(?:%|@|ld|d|lu|f|\.\d+f)"#)
    return regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
        .map { String(s[Range($0.range, in: s)!]) }
        .sorted()
}

let keys = swiftKeys()
if args.contains("--keys") {
    keys.forEach { print($0) }
    exit(0)
}

var problems: [String] = []
let resources = root.appendingPathComponent("Resources")
let languages = ((try? fm.contentsOfDirectory(atPath: resources.path)) ?? []).filter { $0.hasSuffix(".lproj") }.sorted()
if languages.isEmpty { problems.append("No .lproj folders in Resources") }

for lproj in languages {
    let file = resources.appendingPathComponent(lproj).appendingPathComponent("Localizable.strings")
    guard let table = NSDictionary(contentsOf: file) as? [String: String] else {
        problems.append("\(lproj): Localizable.strings is missing or can't be parsed")
        continue
    }
    for key in keys {
        guard let value = table[key] else { problems.append("\(lproj): missing “\(key)”"); continue }
        if value.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("\(lproj): empty “\(key)”") }
        if specifiers(key) != specifiers(value) { problems.append("\(lproj): format specifiers differ in “\(key)”") }
    }
    for key in table.keys where !keys.contains(key) { problems.append("\(lproj): unused “\(key)”") }
}

if problems.isEmpty {
    print("Localizations OK: \(languages.count) languages, \(keys.count) keys")
} else {
    problems.forEach { print("✗ " + $0) }
    exit(1)
}
