import Foundation

struct ComposeMediaFileStore {
    private let fileManager: FileManager
    private let rootURL: URL

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) throws {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = applicationSupport
                .appendingPathComponent("Astrenza", isDirectory: true)
                .appendingPathComponent("ComposeMedia", isDirectory: true)
        }
        try fileManager.createDirectory(
            at: self.rootURL,
            withIntermediateDirectories: true,
            attributes: [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
        )
    }

    func persist(
        data: Data,
        id: UUID,
        fileExtension: String
    ) throws -> URL {
        let safeExtension = fileExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let url = rootURL
            .appendingPathComponent(id.uuidString)
            .appendingPathExtension(safeExtension.isEmpty ? "img" : safeExtension)
        try data.write(to: url, options: [.atomic])
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        return url
    }

    func remove(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}
