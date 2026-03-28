import Foundation

enum SuperModelCatalog {
    /// ⚠️ BLOCKER: перед merge/release заполнить реальные значения.
    /// Отдельный коммит: загрузить GGUF на HF, получить pinned commit URL + SHA256.
    /// Без этого resume и integrity check не работают корректно.
    ///
    /// Как получить:
    ///   1. huggingface-cli upload <repo> gigachat-gguf.gguf
    ///   2. URL: https://huggingface.co/<repo>/resolve/<commit-sha>/gigachat-gguf.gguf
    ///   3. SHA256: shasum -a 256 gigachat-gguf.gguf
    static let current = SuperModelDownloadSpec(
        url: URL(string: "https://huggingface.co/sanyasamineva0x/gigachat-gguf/resolve/FILL_COMMIT_SHA/gigachat-gguf.gguf")!,
        destination: URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".govorun/models/gigachat-gguf.gguf"),
        expectedSHA256: "FILL_SHA256_HASH",
        expectedSize: 5_832_014_592
    )

    static let minimumDiskSpaceBuffer: Int64 = 500_000_000
}
