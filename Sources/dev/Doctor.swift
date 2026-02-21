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
            if !fm.fileExists(atPath: P.root.path) {
                throw RuntimeError(description: "Missing ~/Developer")
            }
        }

        try check("Templates") {
            if !fm.fileExists(atPath: P.templates.path) {
                throw RuntimeError(description: "Missing templates")
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
