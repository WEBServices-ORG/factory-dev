import Foundation
import ArgumentParser
import Logging
// (no new deps)

enum P {
  static let home = FileManager.default.homeDirectoryForCurrentUser
  static let root = home.appendingPathComponent("Developer")
  static let tooling = root.appendingPathComponent("tooling")
  static let templates = root.appendingPathComponent("templates")
  static let config = root.appendingPathComponent("config")
  static let staging = root.appendingPathComponent(".staging")
  static let workPersonal = root
  static let miseDir = config.appendingPathComponent("mise")
  static let miseToml = miseDir.appendingPathComponent("mise.toml")
  static let templatesCache = config.appendingPathComponent("templates-cache")
}

enum TemplateSource {
  static let repoURL = "https://github.com/WEBServices-ORG/factory-templates.git"
  static let ref = "550f746ab65b477eb206539c8445c4bcd5f0cf94"
}

struct RuntimeError: Error, CustomStringConvertible { let description: String }
@discardableResult
func sh(_ cmd: String, cwd: URL? = nil, env: [String:String] = [:]) throws -> String {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/bin/zsh")
  p.arguments = ["-lc", cmd]
  if let cwd { p.currentDirectoryURL = cwd }
  var e = ProcessInfo.processInfo.environment
  env.forEach { e[$0.key] = $0.value }
  p.environment = e
  let out = Pipe(); let err = Pipe()
  p.standardOutput = out; p.standardError = err
  try p.run(); p.waitUntilExit()
  let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  let e2 = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  if p.terminationStatus != 0 { throw RuntimeError(description: "\(cmd)\n\(e2)\n\(o)") }
  return o.trimmingCharacters(in: .whitespacesAndNewlines)
}

func ensureDir(_ u: URL) throws { try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true) }
func write(_ u: URL, _ s: String) throws { try ensureDir(u.deletingLastPathComponent()); try s.data(using: .utf8)!.write(to: u, options: .atomic) }

func copyTree(from: URL, to: URL) throws {
  try ensureDir(to)
  let items = try FileManager.default.contentsOfDirectory(atPath: from.path)
  for it in items {
    let src = from.appendingPathComponent(it)
    let dst = to.appendingPathComponent(it)
    if FileManager.default.fileExists(atPath: dst.path) { try FileManager.default.removeItem(at: dst) }
    try FileManager.default.copyItem(at: src, to: dst)
  }
}

func replaceTokens(in url: URL, tokens: [String:String]) throws {
  let data = try Data(contentsOf: url)
  guard var s = String(data: data, encoding: .utf8) else { return }
  for (k,v) in tokens { s = s.replacingOccurrences(of: k, with: v) }
  try write(url, s)
}

func requireXcodeCLT() throws {
  do {
    _ = try sh("xcode-select -p")
  } catch {
    throw RuntimeError(description:
      """
      Xcode Command Line Tools are not installed.

      Install:
        xcode-select --install

      Docs:
        https://developer.apple.com/xcode/
      """
    )
  }
}

func requireMise() throws {
  guard (try? sh("command -v mise")) != nil else {
    throw RuntimeError(description:
      """
      Required tool 'mise' is not installed.

      Install mise:
        https://mise.jdx.dev/
      """
    )
  }
}

func ensureEnvironmentReady() throws {
  let fm = FileManager.default

  try ensureDir(P.root)
  try ensureDir(P.tooling)
  try ensureDir(P.config)
  try ensureDir(P.templates)
  try ensureDir(P.templatesCache)

  let localTemplate = P.templates.appendingPathComponent("macos-swiftui")
  if fm.fileExists(atPath: localTemplate.path) {
    return
  }

  let cachedTemplate = P.templatesCache.appendingPathComponent("macos-swiftui")
  let templatesRepo = P.templates.appendingPathComponent("factory-templates")
  let sourceTemplate = templatesRepo.appendingPathComponent("swiftui-macos-app")

  try? fm.removeItem(at: templatesRepo)

  do {
    let cloneCmd = "git clone --depth 1 '\(TemplateSource.repoURL)' '\(templatesRepo.path)'"
    _ = try sh(cloneCmd)
    _ = try sh("git -C '\(templatesRepo.path)' checkout '\(TemplateSource.ref)'")

    guard fm.fileExists(atPath: sourceTemplate.path) else {
      throw RuntimeError(description: "Template source '\(sourceTemplate.path)' not found in factory-templates at ref '\(TemplateSource.ref)'.")
    }

    try fm.copyItem(at: sourceTemplate, to: localTemplate)
    try? fm.removeItem(at: cachedTemplate)
    try fm.copyItem(at: sourceTemplate, to: cachedTemplate)
  } catch {
    if fm.fileExists(atPath: cachedTemplate.path) {
      try fm.copyItem(at: cachedTemplate, to: localTemplate)
      return
    }

    throw RuntimeError(description:
      """
      Unable to fetch templates from '\(TemplateSource.repoURL)' at ref '\(TemplateSource.ref)' and no local cache is available.

      Original error:
      \(error)
      """
    )
  }
}

func requireTemplateExists(_ slot: TemplateSlot) throws {
  try ensureEnvironmentReady()
  let src = templatePath(slot)
  guard FileManager.default.fileExists(atPath: src.path) else {
    throw RuntimeError(description: "Template '\(slot.rawValue)' unavailable.")
  }
}

enum TemplateSlot: String, CaseIterable, ExpressibleByArgument {
  case macosSwiftUI = "macos-swiftui"
  case internalLib  = "internal-lib"
  case cliTool      = "cli-tool"
}

func templatePath(_ slot: TemplateSlot) -> URL {
  switch slot {
  case .macosSwiftUI: return P.templates.appendingPathComponent("macos-swiftui")
  case .internalLib:  return P.templates.appendingPathComponent("internal-lib")
  case .cliTool:      return P.templates.appendingPathComponent("cli-tool")
  }
}

let log: Logger = {
  LoggingSystem.bootstrap { label in
    var h = StreamLogHandler.standardOutput(label: label)
    h.logLevel = .info
    return h
  }
  return Logger(label: "dev")
}()

@main
struct Dev: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "dev",
    abstract: "WEBServices local factory CLI (English-only).",
    subcommands: [Install.self, Bootstrap.self, Doctor.self, New.self, Publish.self, Ship.self, Version.self]
  )
}

struct Bootstrap: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Bootstrap local factory.")
  func run() throws {
    // Hard prerequisite first, before touching anything else
    try requireXcodeCLT()
    try requireMise()

    try ensureDir(P.root)
    try ensureDir(P.tooling)
    try ensureDir(P.templates)
    try ensureDir(P.config)
    try ensureDir(P.staging)
    try ensureDir(P.workPersonal)
    try ensureDir(P.root.appendingPathComponent("work/.factory/.smoke"))

    try ensureDir(P.miseDir)
    if !FileManager.default.fileExists(atPath: P.miseToml.path) {
      try write(P.miseToml, """
      [tools]
      tuist = "4.0.0"
      swiftlint = "0.63.2"
      swiftformat = "0.58.0"
      """)
    }

    _ = try sh("command -v mise >/dev/null || (echo 'mise not found' && exit 1)")
    log.info("Installing tools via mise (pinned)…")
    _ = try sh("cd '\(P.miseDir.path)' && mise install")
    log.info("Done. Next: dev doctor")
  }
}

struct New: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Create a new project from a template.")
  @Argument(help: "App name.") var name: String
  @Option(name: .shortAndLong, help: "Template (default: macos-swiftui).") var template: TemplateSlot = .macosSwiftUI
  @Option(help: "Bundle ID prefix.") var org: String = "com.webservicesdev"
  @Option(help: "Deployment target (macOS).") var target: String = "15.0"
  @Option(help: "Output directory (default: ~/Developer/<Name>).") var dir: String?

  func run() throws {
    let fm = FileManager.default

    // ─────────────────────────────────────
    // Prerequisites
    // ─────────────────────────────────────
    try requireTemplateExists(template)
    let tpl = templatePath(template)

    // ─────────────────────────────────────
    // Define final destination
    // ─────────────────────────────────────
    let finalDir: URL = {
      if let dir { return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath) }
      return P.workPersonal.appendingPathComponent(name)
    }()

    if fm.fileExists(atPath: finalDir.path) {
      throw RuntimeError(description: "Directory '\(name)' already exists.")
    }

    // ─────────────────────────────────────
    // Clean staging from previous runs
    // ─────────────────────────────────────
    try? fm.removeItem(at: P.staging)
    try ensureDir(P.staging)

    // ─────────────────────────────────────
    // Staging (transactional)
    // ─────────────────────────────────────
    let stagingDir = P.staging.appendingPathComponent("\(name)-\(UUID().uuidString)")
    try ensureDir(stagingDir)

    defer { try? fm.removeItem(at: stagingDir) }

    do {
      // ─────────────────────────────────────
      // Copy template
      // ─────────────────────────────────────
      try copyTree(from: tpl, to: stagingDir)

      let tokens: [String:String] = [
        "{{PRODUCT_NAME}}": name,
        "{{BUNDLE_PREFIX}}": org,
        "{{DEPLOYMENT_TARGET}}": target
      ]
      try replaceTokens(in: stagingDir.appendingPathComponent("Project.swift"), tokens: tokens)
      try replaceTokens(in: stagingDir.appendingPathComponent("Sources/App/ContentView.swift"), tokens: tokens)

      let optionalFiles = [
        "mise.toml",
        ".github/workflows/ci.yml",
        "factory/git-hooks/pre-commit",
        "Tests/AppTests/{{PRODUCT_NAME}}Tests.swift"
      ]
      for f in optionalFiles {
        let u = stagingDir.appendingPathComponent(f)
        if fm.fileExists(atPath: u.path) {
          try replaceTokens(in: u, tokens: tokens)
        }
      }

      // ─────────────────────────────────────
      // Generate Xcode project
      // ─────────────────────────────────────
      let stagingPath = stagingDir.path
      _ = try sh("cd '\(stagingPath)' && mise trust 2>&1 || true")
      _ = try sh("cd '\(stagingPath)' && mise install 2>&1 || true")
      _ = try sh("cd '\(stagingPath)' && mise exec tuist -- tuist generate --no-open 2>&1 || true")

      // ─────────────────────────────────────
      // Git init + initial commit
      // ─────────────────────────────────────
      _ = try sh("cd '\(stagingPath)' && git init 2>&1")

      let hookDir = stagingDir.appendingPathComponent(".git/hooks")
      try ensureDir(hookDir)
      let srcHook = stagingDir.appendingPathComponent("factory/git-hooks/pre-commit")
      let dstHook = hookDir.appendingPathComponent("pre-commit")
      if fm.fileExists(atPath: srcHook.path) {
        if fm.fileExists(atPath: dstHook.path) { try fm.removeItem(at: dstHook) }
        try fm.copyItem(at: srcHook, to: dstHook)
        _ = try sh("chmod +x '\(dstHook.path)'")
      }

      _ = try sh("cd '\(stagingPath)' && git add .")
      let env = [
        "GIT_AUTHOR_NAME": "WEBServices Factory",
        "GIT_AUTHOR_EMAIL": "admin@webservicesdev.com",
        "GIT_COMMITTER_NAME": "WEBServices Factory",
        "GIT_COMMITTER_EMAIL": "admin@webservicesdev.com",
        "GIT_AUTHOR_DATE": "2000-01-01T00:00:00Z",
        "GIT_COMMITTER_DATE": "2000-01-01T00:00:00Z",
      ]
      _ = try sh("cd '\(stagingPath)' && git commit -m \"Initial commit\"", env: env)

      // ─────────────────────────────────────
      // Atomic move to final destination
      // ─────────────────────────────────────
      try ensureDir(finalDir.deletingLastPathComponent())
      try fm.moveItem(at: stagingDir, to: finalDir)

      // ─────────────────────────────────────
      // Open in Xcode
      // ─────────────────────────────────────
      let workspace = finalDir.appendingPathComponent("\(name).xcworkspace")
      let project = finalDir.appendingPathComponent("\(name).xcodeproj")

      if fm.fileExists(atPath: workspace.path) {
        try sh("open \"\(workspace.path)\"")
      } else if fm.fileExists(atPath: project.path) {
        try sh("open \"\(project.path)\"")
      }

      log.info("Created ✅ \(finalDir.path)")

      // ─────────────────────────────────────
      // Cleanup staging root
      // ─────────────────────────────────────
      try? fm.removeItem(at: P.staging)
    } catch {
      throw error
    }
  }
}

struct Publish: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Publish current repo to GitHub (create repo + origin + push).")

  @Option(help: "GitHub owner/org (default: WEBServices-ORG).") var owner: String? = "WEBServices-ORG"
  @Flag(help: "Create as public (default: private).") var `public`: Bool = false
  @Flag(help: "Skip pushing (create repo + set origin only).") var noPush: Bool = false

  func run() throws {
    let cwdPath = FileManager.default.currentDirectoryPath
    log.info("Current directory: \(cwdPath)")

    _ = try sh("cd '\(cwdPath)' && git rev-parse --is-inside-work-tree")

    let repoName = URL(fileURLWithPath: cwdPath).lastPathComponent

    _ = try? sh("cd '\(cwdPath)' && git branch -M main")

    let hasCommit = (try? sh("cd '\(cwdPath)' && git rev-parse --verify HEAD")) != nil
    if !hasCommit {
      throw RuntimeError(description: "No commits found. Commit first, then run dev publish.")
    }

    _ = try sh("gh auth status")

    let repoSlug: String = {
      if let owner, !owner.isEmpty { return "\(owner)/\(repoName)" }
      return repoName
    }()

    let visibility = self.public ? "--public" : "--private"

    do {
      log.info("Creating GitHub repo: \(repoSlug) (\(self.public ? "public" : "private"))")
      _ = try sh("cd '\(cwdPath)' && gh repo create \(repoSlug) \(visibility) --source=. --remote=origin --push")
      log.info("Published ✅ \(repoSlug)")
      return
    } catch {
      log.info("Repo may already exist. Ensuring origin + pushing…")
      _ = try sh("gh repo view \(repoSlug) --json name >/dev/null")

      let url = try sh("gh repo view \(repoSlug) --json url -q .url")
      if (try? sh("cd '\(cwdPath)' && git remote get-url origin")) != nil {
        _ = try sh("cd '\(cwdPath)' && git remote set-url origin \(url).git")
      } else {
        _ = try sh("cd '\(cwdPath)' && git remote add origin \(url).git")
      }

      if !noPush {
        _ = try sh("cd '\(cwdPath)' && git push -u origin main")
      }

      log.info("Published ✅ \(repoSlug)")
    }
  }
}

struct Ship: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Create a new project and publish it to GitHub org in one command.")

  @Argument(help: "App name.") var name: String
  @Option(name: .shortAndLong, help: "Template (default: macos-swiftui).") var template: TemplateSlot = .macosSwiftUI
  @Option(help: "Bundle ID prefix.") var org: String = "com.webservicesdev"
  @Option(help: "Deployment target.") var target: String = "15.0"
  @Flag(help: "Create GitHub repo as public (default: private).") var `public`: Bool = false

  func run() throws {
    try requireTemplateExists(template)
    let newCmd = try New.parse([name, "--template", template.rawValue, "--org", org, "--target", target])
    try newCmd.run()

    let repoPath = P.workPersonal.appendingPathComponent(name)
    let pubFlag = `public` ? "--public" : ""
    let devPath = P.tooling.appendingPathComponent("dev-cli/.build/release/dev")
    _ = try sh("cd '\(repoPath.path)' && '\(devPath.path)' publish \(pubFlag)")
    log.info("Shipped ✅ WEBServices-ORG/\(name)")
  }
}


// dev version
struct Version: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Print dev CLI version information.")

  static let current = "0.1.31"

  func run() throws {
    // Best-effort git SHA (works in repo builds; harmless otherwise)
    let sha = (try? sh("git rev-parse --short HEAD", cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)))?.trimmingCharacters(in: .whitespacesAndNewlines)

    if let sha, !sha.isEmpty {
      print("foundry \(Version.current) (\(sha))")
    } else {
      print("foundry \(Version.current)")
    }
  }
}
