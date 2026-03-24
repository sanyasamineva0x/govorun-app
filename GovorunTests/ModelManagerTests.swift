@testable import Govorun
import XCTest

@MainActor
final class ModelManagerTests: XCTestCase {
    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "govorun_model_test_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        super.tearDown()
    }

    // MARK: - checkModelStatus

    func test_checkModelStatus_no_cache_dir_returns_notDownloaded() {
        let sut = ModelManager(modelCacheDir: tempDir + "/nonexistent")

        sut.checkModelStatus()

        XCTAssertEqual(sut.downloadState, .notDownloaded)
        XCTAssertEqual(sut.modelSizeBytes, 0)
        XCTAssertFalse(sut.isModelDownloaded)
    }

    func test_checkModelStatus_empty_cache_dir_returns_notDownloaded() {
        let sut = ModelManager(modelCacheDir: tempDir)

        sut.checkModelStatus()

        XCTAssertEqual(sut.downloadState, .notDownloaded)
        XCTAssertEqual(sut.modelSizeBytes, 0)
    }

    func test_checkModelStatus_no_snapshots_returns_notDownloaded() throws {
        // snapshots/ есть, но пустая
        try FileManager.default.createDirectory(
            atPath: tempDir + "/snapshots",
            withIntermediateDirectories: true
        )

        let sut = ModelManager(modelCacheDir: tempDir)
        sut.checkModelStatus()

        XCTAssertEqual(sut.downloadState, .notDownloaded)
    }

    func test_checkModelStatus_partial_download_returns_notDownloaded() {
        // Только 2 из 3 файлов
        let snapshotDir = createSnapshotDir()
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_encoder.onnx", size: 1_000)
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_decoder.onnx", size: 500)
        // v3_e2e_rnnt_joint.onnx отсутствует

        let sut = ModelManager(modelCacheDir: tempDir)
        sut.checkModelStatus()

        XCTAssertEqual(sut.downloadState, .notDownloaded)
        XCTAssertEqual(sut.modelSizeBytes, 0)
    }

    func test_checkModelStatus_all_files_present_returns_downloaded() {
        let snapshotDir = createSnapshotDir()
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_encoder.onnx", size: 1_000)
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_decoder.onnx", size: 500)
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_joint.onnx", size: 200)

        let sut = ModelManager(modelCacheDir: tempDir)
        sut.checkModelStatus()

        XCTAssertEqual(sut.downloadState, .downloaded)
        XCTAssertTrue(sut.isModelDownloaded)
        XCTAssertEqual(sut.modelSizeBytes, 1_700)
    }

    func test_checkModelStatus_zero_size_file_returns_notDownloaded() {
        let snapshotDir = createSnapshotDir()
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_encoder.onnx", size: 1_000)
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_decoder.onnx", size: 0)
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_joint.onnx", size: 200)

        let sut = ModelManager(modelCacheDir: tempDir)
        sut.checkModelStatus()

        XCTAssertEqual(sut.downloadState, .notDownloaded)
    }

    // MARK: - deleteModel

    func test_deleteModel_removes_cache_directory() throws {
        let snapshotDir = createSnapshotDir()
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_encoder.onnx", size: 100)
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_decoder.onnx", size: 100)
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_joint.onnx", size: 100)

        let sut = ModelManager(modelCacheDir: tempDir)
        sut.checkModelStatus()
        XCTAssertTrue(sut.isModelDownloaded)

        try sut.deleteModel()

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir))
        XCTAssertEqual(sut.downloadState, .notDownloaded)
        XCTAssertEqual(sut.modelSizeBytes, 0)
    }

    func test_deleteModel_nonexistent_does_not_throw() throws {
        let sut = ModelManager(modelCacheDir: tempDir + "/nonexistent")
        XCTAssertNoThrow(try sut.deleteModel())
    }

    // MARK: - formattedSize

    func test_formattedSize_zero_returns_dash() {
        let sut = ModelManager(modelCacheDir: tempDir + "/nonexistent")
        sut.checkModelStatus()
        XCTAssertEqual(sut.formattedSize, "—")
    }

    func test_formattedSize_returns_human_readable() {
        let snapshotDir = createSnapshotDir()
        // ~1 MB total
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_encoder.onnx", size: 900_000)
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_decoder.onnx", size: 50_000)
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_joint.onnx", size: 50_000)

        let sut = ModelManager(modelCacheDir: tempDir)
        sut.checkModelStatus()

        XCTAssertTrue(sut.isModelDownloaded)
        // Формат зависит от локали, но должен содержать число
        XCTAssertFalse(sut.formattedSize.isEmpty)
        XCTAssertNotEqual(sut.formattedSize, "—")
    }

    // MARK: - isModelDownloaded

    func test_isModelDownloaded_false_by_default() {
        let sut = ModelManager(modelCacheDir: tempDir)
        XCTAssertFalse(sut.isModelDownloaded)
    }

    func test_isModelDownloaded_true_after_check() {
        let snapshotDir = createSnapshotDir()
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_encoder.onnx", size: 100)
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_decoder.onnx", size: 100)
        createFakeONNX(in: snapshotDir, name: "v3_e2e_rnnt_joint.onnx", size: 100)

        let sut = ModelManager(modelCacheDir: tempDir)
        XCTAssertFalse(sut.isModelDownloaded)

        sut.checkModelStatus()
        XCTAssertTrue(sut.isModelDownloaded)
    }

    // MARK: - defaultModelCacheDir

    func test_defaultModelCacheDir_points_to_huggingface_cache() {
        let path = ModelManager.defaultModelCacheDir
        XCTAssertTrue(path.contains(".cache/huggingface/hub"))
        XCTAssertTrue(path.contains("gigaam-v3-onnx"))
        XCTAssertFalse(path.contains("~"))
    }

    // MARK: - expectedFiles

    func test_expectedFiles_contains_three_onnx() {
        XCTAssertEqual(ModelManager.expectedFiles.count, 3)
        XCTAssertTrue(ModelManager.expectedFiles.allSatisfy { $0.hasSuffix(".onnx") })
    }

    // MARK: - Helpers

    @discardableResult
    private func createSnapshotDir() -> String {
        let snapshotDir = tempDir + "/snapshots/abc123"
        try! FileManager.default.createDirectory(
            atPath: snapshotDir,
            withIntermediateDirectories: true
        )
        return snapshotDir
    }

    private func createFakeONNX(in dir: String, name: String, size: Int) {
        let path = (dir as NSString).appendingPathComponent(name)
        let data = Data(repeating: 0x42, count: size)
        FileManager.default.createFile(atPath: path, contents: data)
    }
}
