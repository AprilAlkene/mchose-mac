import Foundation

public enum ManifestError: Error, LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let name):
            return "Device manifest \(name).json not found in the app bundle"
        }
    }
}

public enum ManifestLoader {
    public static func load(from url: URL) throws -> DeviceManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DeviceManifest.self, from: data)
    }

    public static func loadBundled(
        named name: String = "ace68_turbo_16k"
    ) throws -> DeviceManifest {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "json"),
            Bundle.main.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "DeviceManifests"
            ),
        ].compactMap { $0 }

        guard let url = candidates.first else {
            throw ManifestError.notFound(name)
        }
        return try load(from: url)
    }
}
