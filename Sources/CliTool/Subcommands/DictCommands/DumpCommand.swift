import ArgumentParser
import Foundation
import KanaKanjiConverterModule

extension Subcommands.Dict {
    struct Dump: ParsableCommand {
        @Option(name: [.customLong("dictionary_dir"), .customShort("d")], help: "The directory for dictionary data.")
        var dictionaryDirectory: String = "./Sources/KanaKanjiConverterModuleWithDefaultDictionary/azooKey_dictionary_storage/Dictionary"

        @Option(name: [.customLong("output"), .customShort("o")], help: "The output CSV path.")
        var outputPath: String = "../existing_words.csv"

        static let configuration = CommandConfiguration(
            commandName: "dump",
            abstract: "Dump all words in default dictionary into a CSV file"
        )

        mutating func run() throws {
            let start = Date()
            let dictURL = URL(fileURLWithPath: dictionaryDirectory)
            let loudsDir = dictURL.appendingPathComponent("louds", isDirectory: true)

            guard FileManager.default.fileExists(atPath: loudsDir.path) else {
                print("Error: Directory not found at \(loudsDir.path)")
                return
            }

            print("Scanning dictionary files in \(loudsDir.path)...")

            let files = try FileManager.default.contentsOfDirectory(at: loudsDir, includingPropertiesForKeys: nil)
            
            // *.loudsファイルを探し、それがshared_で始まらないものを抽出する
            let loudsFiles = files.filter { $0.pathExtension == "louds" && !$0.lastPathComponent.hasPrefix("shared_") }
            
            print("Found \(loudsFiles.count) dictionary shard files.")

            var uniqueWords: [String: Set<String>] = [:]
            let store = DicdataStore(dictionaryURL: dictURL)
            let state = store.prepareState()

            for loudsFile in loudsFiles {
                let filename = loudsFile.deletingPathExtension().lastPathComponent
                guard let louds = LOUDS.load(filename, dictionaryURL: dictURL) else {
                    continue
                }

                // すべてのノードインデックスを取得
                let nodeIndices = louds.prefixNodeIndices(chars: [], maxDepth: .max, maxCount: .max)
                if nodeIndices.isEmpty { continue }

                // ファイル名から元の識別子を復元
                let rawTarget = unescapeIdentifier(filename)

                let dicdata = store.getDicdataFromLoudstxt3(identifier: rawTarget, indices: nodeIndices, state: state)
                for element in dicdata {
                    if !element.ruby.isEmpty && !element.word.isEmpty {
                        uniqueWords[element.ruby, default: []].insert(element.word)
                    }
                }
            }

            print("Writing output to \(outputPath)...")
            var csvContent = "よみ,表記\n"
            var count = 0
            for (ruby, words) in uniqueWords.sorted(by: { $0.key < $1.key }) {
                for word in words.sorted() {
                    let escapedRuby = escapeCSVField(ruby)
                    let escapedWord = escapeCSVField(word)
                    csvContent += "\(escapedRuby),\(escapedWord)\n"
                    count += 1
                }
            }

            try csvContent.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)

            print(
                """
                === Extraction Summary ===
                - Output path: \(outputPath)
                - Unique rubies (よみ): \(uniqueWords.count)
                - Total word pairs (単語ペア数): \(count)
                - Time elapsed: \(Date().timeIntervalSince(start))s
                """
            )
        }

        private func unescapeIdentifier(_ filename: String) -> String {
            guard filename.hasPrefix("[") && filename.hasSuffix("]") else {
                return filename
            }
            let content = filename.dropFirst().dropLast()
            let parts = content.components(separatedBy: "_")
            var utf16CodeUnits: [UInt16] = []
            for part in parts {
                if let val = UInt16(part, radix: 16) {
                    utf16CodeUnits.append(val)
                }
            }
            return String(decoding: utf16CodeUnits, as: UTF16.self)
        }

        private func escapeCSVField(_ field: String) -> String {
            if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
                return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return field
        }
    }
}
