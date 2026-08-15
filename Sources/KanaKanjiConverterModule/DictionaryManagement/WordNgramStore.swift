//
//  WordNgramStore.swift
//  KanaKanjiConverterModule
//
//  Created for KanaKanjiConverter Word N-gram Language Model
//

public import Foundation
import SwiftUtils

/// 64-bit FNV-1a ハッシュ関数
@inlinable
package func fnv1a64(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    let prime: UInt64 = 0x100000001b3
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* prime
    }
    return hash
}

/// コーパスから生成された単語2-gramバイナリ（mmap対応・ゼロコピー）を保持・検索するストア
public final class WordNgramStore: Sendable {
    private let data: Data
    private let entryCount: Int
    private let headerSize = 16
    private let entrySize = 16

    package init?(data: Data) {
        guard data.count >= 16 else { return nil }
        // Magic header check: "AZWNGRAM"
        let magic = data.prefix(8)
        guard magic.elementsEqual("AZWNGRAM".utf8) else { return nil }

        let version = data[8..<12].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard version == 1 else { return nil }

        let count = Int(data[12..<16].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        let expectedSize = 16 + count * 16
        guard data.count >= expectedSize else { return nil }

        self.data = data
        self.entryCount = count
    }

    /// 辞書ディレクトリから word_ngram.binary を mmap (alwaysMapped) でロード
    package static func load(dictionaryURL: URL) -> WordNgramStore? {
        let fileURL = dictionaryURL.appendingPathComponent("word_ngram.binary", isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let mappedData = try Data(contentsOf: fileURL, options: .alwaysMapped)
            return WordNgramStore(data: mappedData)
        } catch {
            return nil
        }
    }

    /// 2単語の連接スコア（ボーナス/ペナルティ）を二分探索で取得
    package func getScore(prevWord: String, currentWord: String) -> PValue? {
        guard entryCount > 0 else { return nil }
        let targetHash = fnv1a64("\(prevWord)\t\(currentWord)")

        return data.withUnsafeBytes { rawBuffer -> PValue? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            let entriesPtr = baseAddress.advanced(by: headerSize)

            var low = 0
            var high = entryCount - 1

            while low <= high {
                let mid = (low + high) &>> 1
                let offset = mid * entrySize
                let entryHash = entriesPtr.loadUnaligned(fromByteOffset: offset, as: UInt64.self)

                if entryHash < targetHash {
                    low = mid + 1
                } else if entryHash > targetHash {
                    high = mid - 1
                } else {
                    let score = entriesPtr.loadUnaligned(fromByteOffset: offset + 8, as: Float32.self)
                    return PValue(score)
                }
            }
            return nil
        }
    }
}
