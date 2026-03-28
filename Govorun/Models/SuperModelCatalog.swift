import Foundation

enum SuperModelCatalog {
    /// GigaChat 3.1 10B-A1.8B Q4_K_M — pinned на конкретный commit HF репо.
    /// При обновлении модели: новый commit SHA + новый SHA256 файла.
    static let current: SuperModelDownloadSpec = {
        guard let url = URL(string: "https://huggingface.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF/resolve/97045b260251cfa86f5ad25638fa2dd074153446/GigaChat3.1-10B-A1.8B-q4_K_M.gguf") else {
            fatalError("SuperModelCatalog: невалидный URL модели")
        }
        return SuperModelDownloadSpec(
            url: url,
            destination: URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".govorun/models/gigachat-gguf.gguf"),
            expectedSHA256: "68a8732fb5cee04f83ebffd7924e15c534d4442c5a43d2ba9e2041fe310b8deb",
            expectedSize: 6_474_702_976
        )
    }()

    static let minimumDiskSpaceBuffer: Int64 = 500_000_000
}
