import Foundation
import ArgumentParser

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Validate local Foundry environment."
    )

    func run() throws {
        let fm = FileManager.default

        try check("Xcode") {
            try sh("xcode-select -p > /dev/null 2>&1")
        }

        try check("Git") {
            try sh("git --version > /dev/null 2>&1")
        }

        try check("mise") {
            try sh("command -v mise > /dev/null 2>&1")
        }

        try check("tuist") {
            try sh("mise exec tuist -- tuist version > /dev/null 2>&1")
        }

        try check("Developer directory") {
            let path = NSHomeDirectory() + "/Developer"
            if !fm.fileExists(atPath: path) {
                throw RuntimeError(description: "Missing ~/Developer")
            }
        }

        print("Environment OK")
    }

    private func check(_ name: String, _ block: () throws -> Void) throws {
        do {
            try block()
            print("✓ \(name)")
        } catch {
            print("✗ \(name)")
            throw ExitCode.failure
        }
    }
}
