import Foundation
import ArgumentParser

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install Foundry environment on this machine."
    )

    func run() throws {
        let fm = FileManager.default

        do {
            try sh("xcode-select -p > /dev/null 2>&1")
        } catch {
            throw RuntimeError(description: """
            Xcode Command Line Tools are not installed.

            Install:
              xcode-select --install

            Docs:
              https://developer.apple.com/xcode/
            """)
        }

        try ensureEnvironmentReady()

        try ensureDir(P.config)
        try ensureDir(P.miseDir)
        if !fm.fileExists(atPath: P.miseToml.path) {
            try write(P.miseToml, """
            [tools]
            tuist = "4.0.0"
            swiftlint = "0.63.2"
            swiftformat = "0.58.0"
            """)
        }

        print("Foundry install complete.")
    }
}
