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

    @Option(name: [.customLong("sumire_tsv")], help: "Path to Sumire vocabulary TSV file")
    var sumireTsvPath: String?

    @Option(name: [.customLong("azookey_tsv")], help: "Path to AzooKey existing vocabulary TSV to prevent duplicates")
    var azookeyTsvPath: String?

    func run() throws {
        let inputURL = URL(fileURLWithPath: inputDir)
        let outputURL = URL(fileURLWithPath: outputDir)
        let charIdURL = URL(fileURLWithPath: charIdPath)

        if !FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        }

        print("Reading dictionaries from \(inputURL.path)...")

        var rawEntries: [DicdataElement] = []

        // 1. CustomDictionary (CID: 1285 - 一般名詞)
        rawEntries += try parseSwiftDict(url: inputURL.appendingPathComponent("CustomDictionary.swift"), cid: 1285)
        
        // 2. KaomojiDictionary (CID: 1317 - カスタム顔文字)
        rawEntries += try parseSwiftDict(url: inputURL.appendingPathComponent("KaomojiDictionary.swift"), cid: 1317)
        
        // 3. EmojiDictionary (CID: 1318 - カスタム絵文字)
        rawEntries += try parseSwiftDict(url: inputURL.appendingPathComponent("EmojiDictionary.swift"), cid: 1318)

        // 4. Sumire Vocabulary TSV (新語・固有名詞・Wikipedia・NEologd)
        if let sumireTsv = sumireTsvPath, FileManager.default.fileExists(atPath: sumireTsv) {
            print("Reading Sumire TSV from \(sumireTsv)...")
            var existingAzooKeyKeys: Set<String> = []
            if let azookeyTsv = azookeyTsvPath, FileManager.default.fileExists(atPath: azookeyTsv) {
                print("Loading AzooKey existing vocabulary from \(azookeyTsv) for zero-redundancy...")
                let azooContent = try String(contentsOfFile: azookeyTsv, encoding: .utf8)
                for line in azooContent.components(separatedBy: .newlines) {
                    if line.isEmpty { continue }
                    let items = line.split(separator: "\t", omittingEmptySubsequences: false)
                    if items.count >= 2 {
                        let r = String(items[0]).toKatakana()
                        let w = String(items[1])
                        existingAzooKeyKeys.insert("\(r)\t\(w)")
                    }
                }
                print("Loaded \(existingAzooKeyKeys.count) existing AzooKey keys.")
            }
            rawEntries += try parseSumireTSV(path: sumireTsv, existingAzooKeyKeys: existingAzooKeyKeys)
        }

        print("Deduplicating all entries...")
        var finalMap: [String: DicdataElement] = [:]
        for entry in rawEntries {
            let key = "\(entry.ruby)\t\(entry.word)"
            if let existing = finalMap[key] {
                if entry.value() > existing.value() {
                    finalMap[key] = entry
                }
            } else {
                finalMap[key] = entry
            }
        }
        let allEntries = Array(finalMap.values)

        print("Total deduplicated unique entries: \(allEntries.count)")

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

    private func parseSumireTSV(path: String, existingAzooKeyKeys: Set<String> = []) throws -> [DicdataElement] {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var uniqueMap: [String: DicdataElement] = [:]
        let allowedCategories: Set<String> = ["system", "web", "neologd", "wiki", "person_name", "places", "kotowaza"]
        var skippedAzooKeyDupCount = 0

        for line in lines {
            if line.isEmpty { continue }
            let items = line.split(separator: "\t", omittingEmptySubsequences: false)
            if items.count < 6 { continue }

            let yomi = String(items[0])
            let tango = String(items[1])
            let posString = String(items[4])
            guard let cost = Float(items[5]) else { continue }
            let category = items.count >= 7 ? String(items[6]) : "system"

            // すみれ辞書の全語彙カテゴリ（system, web, neologd, wiki, places, person_name, kotowaza）を対象
            guard allowedCategories.contains(category) else {
                continue
            }

            if cost > 9500 {
                continue
            }

            // 1文字や長すぎる語はスキップ
            if yomi.count < 2 || yomi.count > 15 || tango.isEmpty {
                continue
            }

            let ruby = yomi.toKatakana()
            let key = "\(ruby)\t\(tango)"

            // 本体辞書にすでに存在する単語は完全スキップ（完全重複排除）
            if existingAzooKeyKeys.contains(key) {
                skippedAzooKeyDupCount += 1
                continue
            }

            let cid = mapPosToCid(posString: posString)
            
            // 共有辞書スコア: -14.5 (高頻度語) 〜 -17.3 (低頻度語)
            // 日常文の基本語彙（-10〜-12）を邪魔せず、新語・複合語の入力時に第1位となる黄金比
            let score = -13.5 - (cost / 1000.0) * 0.4

            if let existing = uniqueMap[key] {
                if score > existing.value() {
                    uniqueMap[key] = DicdataElement(word: tango, ruby: ruby, cid: cid, mid: 501, value: PValue(score))
                }
            } else {
                uniqueMap[key] = DicdataElement(word: tango, ruby: ruby, cid: cid, mid: 501, value: PValue(score))
            }
        }

        let entries = Array(uniqueMap.values)
        print("Parsed High-Reliability Sumire TSV: \(entries.count) unique entries (Skipped \(skippedAzooKeyDupCount) words already in AzooKey base dict)")
        return entries
    }

    private func mapPosToCid(posString: String) -> Int {
        let parts = posString.components(separatedBy: ",")
        let p0 = parts.count > 0 ? parts[0] : ""
        let p1 = parts.count > 1 ? parts[1] : ""
        let p2 = parts.count > 2 ? parts[2] : ""
        let p3 = parts.count > 3 ? parts[3] : ""

        if p0 == "名詞" {
            if p1 == "固有名詞" {
                if p2 == "人名" {
                    if p3 == "姓" { return 1290 }
                    else if p3 == "名" { return 1291 }
                    else { return 1289 }
                } else if p2 == "地域" { return 1293 }
                else if p2 == "組織" { return 1292 }
                else { return 1288 }
            } else if p1 == "サ変接続" { return 1283 }
            else if p1 == "形容動詞語幹" { return 1281 }
            else if p1 == "数" { return 1295 }
            else { return 1285 }
        } else if p0 == "動詞" {
            return 619
        } else if p0 == "形容詞" {
            return 788
        } else if p0 == "副詞" {
            return 19
        } else if p0 == "感動詞" {
            return 3
        } else if p0 == "接続詞" {
            return 1314
        } else if p0 == "連体詞" {
            return 16
        } else if p0 == "助動詞" {
            return 460
        } else if p0 == "助詞" {
            return 261
        } else if p0 == "記号" {
            return 5
        } else {
            return 1285
        }
    }
}

SharedDictBuilder.main()
