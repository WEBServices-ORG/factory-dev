import Foundation
import ArgumentParser

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install Foundry environment on this machine."
    )

    func run() throws {

        print("Checking Xcode Command Line Tools...")

        do {
            try sh("xcode-select -p > /dev/null 2>&1")
        } catch {
            throw RuntimeError(description: """
            Xcode Command Line Tools are not installed.

            Install and run again:
              xcode-select --install

            Docs:
              https://developer.apple.com/xcode/
            """)
        }

        print("Environment looks good.")
        print("Foundry install complete.")
    }
}
