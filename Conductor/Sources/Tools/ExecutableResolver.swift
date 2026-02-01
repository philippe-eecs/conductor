import Foundation

enum ExecutableResolver {
    static func resolve(
        name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path

        var searchPaths: [String] = []

        if let path = environment["PATH"], !path.isEmpty {
            searchPaths.append(contentsOf: path.split(separator: ":").map(String.init))
        } else {
            // Common default paths for GUI-launched apps.
            searchPaths.append(contentsOf: [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
                "/bin",
                "/usr/sbin",
                "/sbin"
            ])
        }

        // Add common user-local bins.
        searchPaths.append(contentsOf: [
            "\(home)/.local/bin",
            "\(home)/bin"
        ])

        // De-duplicate while preserving order.
        var seen = Set<String>()
        searchPaths = searchPaths.filter { seen.insert($0).inserted }

        for dir in searchPaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
            guard fileManager.fileExists(atPath: candidate.path) else { continue }
            guard fileManager.isExecutableFile(atPath: candidate.path) else { continue }
            return candidate
        }

        return nil
    }
}

