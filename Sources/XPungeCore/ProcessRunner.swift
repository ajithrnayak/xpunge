import Foundation

struct ProcessResult: Sendable {
    var status: Int32
    var stdout: Data
    var stderr: Data
}

enum ProcessRunner {
    /// Runs a program and collects its output. stderr goes through a temp file so large
    /// output on both streams cannot deadlock the pipe.
    static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }

        let stdout = Pipe()
        let errURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xpunge-\(UUID().uuidString).stderr")
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: errURL) }
        let errHandle = try FileHandle(forWritingTo: errURL)

        process.standardOutput = stdout
        process.standardError = errHandle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try? errHandle.close()
        let err = (try? Data(contentsOf: errURL)) ?? Data()
        return ProcessResult(status: process.terminationStatus, stdout: out, stderr: err)
    }
}
