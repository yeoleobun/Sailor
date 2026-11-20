import Foundation

struct NetworkLocation: Identifiable, Hashable, Sendable {
    let id: String      // scselect set UUID
    let name: String    // Display name, e.g. "Automatic", "Home", "Work"
    let isCurrent: Bool
}

enum NetworkLocationError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}

struct NetworkLocationManager: Sendable {
    private static let scselectPath = "/usr/sbin/scselect"

    /// Reads all configured macOS Network Locations and identifies the active one via `scselect`.
    func fetchLocations() -> [NetworkLocation] {
        let result = runProcess(executable: Self.scselectPath, arguments: [])
        let output = result.stdout.isEmpty ? result.stderr : result.stdout
        return Self.parseLocations(from: output)
    }

    /// Switches the active macOS Network Location using `scselect <name_or_uuid>`.
    /// Uses UUID when available so names with spaces or special characters always work.
    @discardableResult
    func switchLocation(to location: NetworkLocation) throws -> String {
        let result = runProcess(executable: Self.scselectPath, arguments: [location.id])
        guard result.exitCode == 0 else {
            let msg = [result.stderr, result.stdout]
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NetworkLocationError.commandFailed(
                msg.isEmpty ? "scselect exited with code \(result.exitCode)" : msg
            )
        }
        return location.name
    }

    /// Switches by location display name (looks up UUID first if available).
    @discardableResult
    func switchLocation(named name: String) throws -> String {
        let locations = fetchLocations()
        if let match = locations.first(where: { $0.name == name }) {
            return try switchLocation(to: match)
        }
        let result = runProcess(executable: Self.scselectPath, arguments: [name])
        guard result.exitCode == 0 else {
            let msg = [result.stderr, result.stdout]
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NetworkLocationError.commandFailed(
                msg.isEmpty ? "scselect exited with code \(result.exitCode)" : msg
            )
        }
        return name
    }

    static func parseLocations(from output: String) -> [NetworkLocation] {
        // Expected format from `scselect`:
        // Defined sets include: (* == current set)
        //  * 8C6D22CF-23BD-431C-9DAF-13C3D7496C98\t(Automatic)
        //    E4C53ECD-3B2F-444D-B7FE-4CF07BBC096F\t(Home)
        var results: [NetworkLocation] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            guard let openParen = line.firstIndex(of: "("),
                  let closeParen = line.lastIndex(of: ")"),
                  openParen < closeParen
            else { continue }

            // Skip header line containing `(* == current set)`
            if line.contains("Defined sets include") { continue }

            let name = String(line[line.index(after: openParen)..<closeParen])
            let prefix = String(line[..<openParen]).trimmingCharacters(in: .whitespaces)
            let isCurrent = prefix.hasPrefix("*")
            let uuid = prefix
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)

            guard !uuid.isEmpty, !name.isEmpty else { continue }
            results.append(NetworkLocation(id: uuid, name: name, isCurrent: isCurrent))
        }
        return results
    }

    private func runProcess(executable: String, arguments: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            return (process.terminationStatus, stdout, stderr)
        } catch {
            return (-1, "", error.localizedDescription)
        }
    }
}
