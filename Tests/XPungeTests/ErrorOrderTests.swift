import Foundation
import Testing
@testable import xpunge

@Suite(.serialized) struct ErrorOrderTests {
    /// Sends stdout and stderr into one pipe, the way a tool capturing output sees them.
    func captureBothStreams(_ body: () -> Void) throws -> String {
        var fds: [Int32] = [0, 0]
        try #require(pipe(&fds) == 0)
        fflush(stdout)
        let savedOut = dup(STDOUT_FILENO), savedErr = dup(STDERR_FILENO)
        dup2(fds[1], STDOUT_FILENO)
        dup2(fds[1], STDERR_FILENO)
        body()
        fflush(stdout)
        dup2(savedOut, STDOUT_FILENO)
        dup2(savedErr, STDERR_FILENO)
        close(savedOut); close(savedErr); close(fds[1])
        let data = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true).readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    @Test func errorComesAfterBufferedOutput() throws {
        let marker = UUID().uuidString
        let output = try captureBothStreams {
            // No newline, so stdout keeps it buffered whether it's a terminal or a pipe.
            print("table-\(marker)", terminator: "")
            printError("refused-\(marker)")
        }
        let table = try #require(output.range(of: "table-\(marker)"))
        let error = try #require(output.range(of: "xpunge: refused-\(marker)"))
        #expect(table.lowerBound < error.lowerBound)
    }
}
