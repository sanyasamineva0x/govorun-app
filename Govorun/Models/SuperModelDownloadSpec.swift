import Foundation

struct SuperModelDownloadSpec: Equatable {
    let url: URL
    let destination: URL
    let expectedSHA256: String
    let expectedSize: Int64
}
