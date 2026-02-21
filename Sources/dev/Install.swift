import Foundation
import ArgumentParser

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install Foundry environment on this machine."
    )

    func run() throws {

        print("Checking Xcode Command Line Tools...")

        let xcodeCheck = Process()
        xcodeCheck.launchPath = "/usr/bin/xcode-select"
        xcodeCheck.arguments = ["-p"]

        do {
            try xcodeCheck.run()
            xcodeCheck.waitUntilExit()
            if xcodeCheck.terminationStatus != 0 {
                throw NSError()
            }
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
