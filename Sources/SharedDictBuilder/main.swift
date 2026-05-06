import Foundation
import ArgumentParser
import KanaKanjiConverterModule
import SwiftUtils

struct SharedDictBuilder: ParsableCommand {
    @Option(name: .shortAndLong, help: "SharedKit dictionary directory path")
    var inputDir: String

    @Option(name: .shortAndLong, help: "Output directory path")
    var outputDir: String

    @Option(name: .shortAndLong, help: "Path to charID.chid file")
    var charIdPath: String

    func run() throws {
        let inputURL = URL(fileURLWithPath: inputDir)
        let outputURL = URL(fileURLWithPath: outputDir)
        let charIdURL = URL(fileURLWithPath: charIdPath)

        if !FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        }

        print("Reading dictionaries from \(inputURL.path)...")

        var allEntries: [DicdataElement] = []

        // 1. CustomDictionary (CID: 1285 - 一般名詞)
        allEntries += try parseSwiftDict(url: inputURL.appendingPathComponent("CustomDictionary.swift"), cid: 1285)
        
        // 2. KaomojiDictionary (CID: 1317 - カスタム顔文字)
        allEntries += try parseSwiftDict(url: inputURL.appendingPathComponent("KaomojiDictionary.swift"), cid: 1317)
        
        // 3. EmojiDictionary (CID: 1318 - カスタム絵文字)
        allEntries += try parseSwiftDict(url: inputURL.appendingPathComponent("EmojiDictionary.swift"), cid: 1318)

        print("Total entries: \(allEntries.count)")

        print("Building LOUDS files...")
        try DictionaryBuilder.exportDictionary(
            entries: allEntries,
            to: outputURL,
            baseName: "shared",
            shardByFirstCharacter: true,
            charIDFileURL: charIdURL
        )

        print("Successfully generated LOUDS files in \(outputURL.path)")
    }

    private func parseSwiftDict(url: URL, cid: Int) throws -> [DicdataElement] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Warning: File not found at \(url.path)")
            return []
        }

        let content = try String(contentsOf: url)
        
        // 正規表現で "読み": ["候補1", "候補2"], // score: -10.0 を抽出
        // scoreコメントはオプションです。カンマが存在する場合も考慮します。
        let pattern = "\"([^\"]+)\":\\s*\\[([^\\]]+)\\](?:\\s*,)?(?:\\s*//\\s*score:\\s*(-?\\d+(?:\\.\\d+)?))?"
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        
        var entries: [DicdataElement] = []
        
        regex.enumerateMatches(in: content, options: [], range: nsRange) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 3 else { return }
            
            let rubyRange = Range(match.range(at: 1), in: content)!
            let wordsRange = Range(match.range(at: 2), in: content)!
            
            let ruby = String(content[rubyRange])
            let wordsString = String(content[wordsRange])
            
            // スコアの抽出 (存在しない場合はデフォルトの -2.5)
            var score: Float = -2.5
            if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
                let scoreRange = Range(match.range(at: 3), in: content)!
                if let parsedScore = Float(content[scoreRange]) {
                    score = parsedScore
                }
            }
            
            // 候補リストを分割 (カンマと引用符を除去)
            let words = wordsString.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                .filter { !$0.isEmpty }
            
            for word in words {
                // AzooKeyの仕様に合わせて、読み（ruby）をカタカナに変換して登録します。
                let katakanaRuby = ruby.toKatakana()
                // AzooKeyの標準的な絵文字の接続ID（MID: 237）に合わせることで、学習効果を最大化します。
                let mid = (cid == 1318) ? 237 : 500
                
                // 解析されたスコア（またはデフォルト値）を使用
                let entry = DicdataElement(word: word, ruby: katakanaRuby, cid: cid, mid: mid, value: score)
                entries.append(entry)
            }
        }
        
        print("Parsed \(url.lastPathComponent): \(entries.count) entries (CID: \(cid))")
        return entries
    }
}

SharedDictBuilder.main()
