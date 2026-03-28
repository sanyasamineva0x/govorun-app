import Foundation

protocol SuperModelDownloading: AnyObject, Sendable {
    var state: SuperModelDownloadState { get }
    var isActive: Bool { get }
    var onStateChanged: (@MainActor @Sendable (SuperModelDownloadState) -> Void)? { get set }
    func download(from spec: SuperModelDownloadSpec) async
    func cancel()
    func clearPartialDownload(for spec: SuperModelDownloadSpec)
    func restoreStateFromDisk(for spec: SuperModelDownloadSpec)
}
