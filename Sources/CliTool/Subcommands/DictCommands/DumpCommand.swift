import ArgumentParser
import Foundation
import KanaKanjiConverterModule

extension Subcommands.Dict {
    struct Dump: ParsableCommand {
        @Option(name: [.customLong("dictionary_dir"), .customShort("d")], help: "The directory for dictionary data.")
        var dictionaryDirectory: String = "./Sources/KanaKanjiConverterModuleWithDefaultDictionary/azooKey_dictionary_storage/Dictionary"

        @Option(name: [.customLong("output"), .customShort("o")], help: "The output file path.")
        var outputPath: String = "../existing_words.tsv"

        @Option(name: [.customLong("format"), .customShort("f")], help: "Output format: 'csv' (ruby,word) or 'tsv' (ruby,word,lcid,rcid,mid,score).")
        var format: String = "tsv"

        @Flag(name: [.customLong("include_shared"), .customShort("s")], help: "Include shared_*.louds files in dump.")
        var includeShared: Bool = false

        static let configuration = CommandConfiguration(
            commandName: "dump",
            abstract: "Dump all words in default dictionary into a file"
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
            
            let loudsFiles = files.filter { file in
                guard file.pathExtension == "louds" else { return false }
                if !includeShared && file.lastPathComponent.hasPrefix("shared_") {
                    return false
                }
                return true
            }
            
            print("Found \(loudsFiles.count) dictionary shard files.")

            let store = DicdataStore(dictionaryURL: dictURL)
            let state = store.prepareState()

            var allElements: [DicdataElement] = []
            var uniqueWords: [String: Set<String>] = [:]

            for loudsFile in loudsFiles {
                let filename = loudsFile.deletingPathExtension().lastPathComponent
                guard let louds = LOUDS.load(filename, dictionaryURL: dictURL) else {
                    continue
                }

                let nodeIndices = louds.prefixNodeIndices(chars: [], maxDepth: .max, maxCount: .max)
                if nodeIndices.isEmpty { continue }

                let rawTarget = unescapeIdentifier(filename)

                let dicdata = store.getDicdataFromLoudstxt3(identifier: rawTarget, indices: nodeIndices, state: state)
                for element in dicdata {
                    if !element.ruby.isEmpty && !element.word.isEmpty {
                        if format == "tsv" {
                            allElements.append(element)
                        } else {
                            uniqueWords[element.ruby, default: []].insert(element.word)
                        }
                    }
                }
            }

            print("Writing output to \(outputPath)...")
            var count = 0
            var outputContent = ""

            if format == "tsv" {
                // ruby \t word \t lcid \t rcid \t mid \t score
                // Sort by ruby
                allElements.sort { $0.ruby < $1.ruby }
                for el in allElements {
                    outputContent += "\(el.ruby)\t\(el.word)\t\(el.lcid)\t\(el.rcid)\t\(el.mid)\t\(el.value())\n"
                    count += 1
                }
            } else {
                outputContent = "よみ,表記\n"
                for (ruby, words) in uniqueWords.sorted(by: { $0.key < $1.key }) {
                    for word in words.sorted() {
                        let escapedRuby = escapeCSVField(ruby)
                        let escapedWord = escapeCSVField(word)
                        outputContent += "\(escapedRuby),\(escapedWord)\n"
                        count += 1
                    }
                }
            }

            try outputContent.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)

            print(
                """
                === Extraction Summary ===
                - Output path: \(outputPath)
                - Format: \(format)
                - Total entries dumped: \(count)
                - Time elapsed: \(Date().timeIntervalSince(start))s
                """
            )
        }

        private func unescapeIdentifier(_ filename: String) -> String {
            var name = filename
            let isShared = name.hasPrefix("shared_")
            if isShared {
                name = String(name.dropFirst(7))
            }
            guard name.hasPrefix("[") && name.hasSuffix("]") else {
                return isShared ? "shared_\(name)" : name
            }
            let content = name.dropFirst().dropLast()
            let parts = content.components(separatedBy: "_")
            var utf16CodeUnits: [UInt16] = []
            for part in parts {
                if let val = UInt16(part, radix: 16) {
                    utf16CodeUnits.append(val)
                }
            }
            let unescaped = String(decoding: utf16CodeUnits, as: UTF16.self)
            return isShared ? "shared_\(unescaped)" : unescaped
        }

        private func escapeCSVField(_ field: String) -> String {
            if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
                return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return field
        }
    }
}
