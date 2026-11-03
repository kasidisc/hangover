import Foundation

private var registered: [(String, () throws -> Void)] = []
var failures = 0

func test(_ name: String, _ body: @escaping () throws -> Void) {
    registered.append((name, body))
}

func expect(_ cond: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
    if !cond {
        failures += 1
        print("    ✗ \((file as NSString).lastPathComponent):\(line) \(msg)")
    }
}

func expectThrows(_ body: () throws -> Void, contains: String, file: String = #file, line: Int = #line) {
    do {
        try body()
        expect(false, "expected an error containing '\(contains)'", file: file, line: line)
    } catch {
        let text = "\(error)"
        expect(text.contains(contains), "error '\(text)' does not contain '\(contains)'", file: file, line: line)
    }
}

/// Fresh empty temp directory for a test.
func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("hangover-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func fixtureURL(_ name: String) -> URL {
    URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
}

func runAllTests() -> Int32 {
    for (name, body) in registered {
        let before = failures
        do { try body() } catch {
            failures += 1
            print("    ✗ threw \(error)")
        }
        print(failures == before ? "  ✓ \(name)" : "  ✗ \(name)")
    }
    print(failures == 0 ? "all \(registered.count) tests passed" : "\(failures) failure(s)")
    return failures == 0 ? 0 : 1
}
