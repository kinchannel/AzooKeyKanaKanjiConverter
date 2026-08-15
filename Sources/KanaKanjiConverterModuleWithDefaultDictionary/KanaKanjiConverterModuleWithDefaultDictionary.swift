import Foundation
@_exported public import KanaKanjiConverterModule

public extension DicdataStore {
    static func withDefaultDictionary(preloadDictionary: Bool = false) -> Self {
        let dictionaryDirectory: URL = {
            if let url = Bundle.module.url(forResource: "Dictionary", withExtension: nil) {
                return url
            }
            if let resourceURL = Bundle.module.resourceURL {
                let candidate = resourceURL.appendingPathComponent("Dictionary", isDirectory: true)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            return Bundle.module.bundleURL.appendingPathComponent("Dictionary", isDirectory: true)
        }()

        return .init(dictionaryURL: dictionaryDirectory, preloadDictionary: preloadDictionary)
    }
}

public extension KanaKanjiConverter {
    static func withDefaultDictionary(preloadDictionary: Bool = false) -> Self {
        .init(dicdataStore: .withDefaultDictionary(preloadDictionary: preloadDictionary))
    }
}

public extension TextReplacer {
    static func withDefaultEmojiDictionary() -> Self {
        self.init {
            let directoryName = "EmojiDictionary"
            let directory: URL = {
                if let url = Bundle.module.url(forResource: directoryName, withExtension: nil) {
                    return url
                }
                if let resourceURL = Bundle.module.resourceURL {
                    let candidate = resourceURL.appendingPathComponent(directoryName, isDirectory: true)
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        return candidate
                    }
                }
                return Bundle.module.bundleURL.appendingPathComponent(directoryName, isDirectory: true)
            }()

            return if #available(iOS 18.4, macOS 15.3, *) {
                directory.appendingPathComponent("emoji_all_E16.0.txt", isDirectory: false)
            } else if #available(iOS 17.4, macOS 14.4, *) {
                directory.appendingPathComponent("emoji_all_E15.1.txt", isDirectory: false)
            } else if #available(iOS 16.4, macOS 14.0, *) {
                directory.appendingPathComponent("emoji_all_E15.0.txt", isDirectory: false)
            } else if #available(iOS 15.4, *) {
                directory.appendingPathComponent("emoji_all_E14.0.txt", isDirectory: false)
            } else {
                directory.appendingPathComponent("emoji_all_E13.1.txt", isDirectory: false)
            }
        }
    }
}
