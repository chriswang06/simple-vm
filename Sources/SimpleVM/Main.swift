import Foundation
import Virtualization

struct CLI {
    var mode: Mode = .run
    var guest: GuestType = .mac
    var bundle: URL = URL(fileURLWithPath: NSString(string: "~/VMs/SimpleVM").expandingTildeInPath)
    var ipsw: URL?
    var iso: URL?
    var diskSizeGB: Int = 64
    var headless: Bool = false
    var download: Bool = false
    var rosetta: Bool = false

    enum Mode { case install, run, validate }

    static func parse(_ argv: [String]) -> CLI {
        var cli = CLI()
        var i = 1
        while i < argv.count {
            let a = argv[i]
            switch a {
            case "--install":  cli.mode = .install
            case "--run":      cli.mode = .run
            case "--validate": cli.mode = .validate
            case "--headless": cli.headless = true
            case "--download": cli.download = true
            case "--rosetta":  cli.rosetta = true
            case "--guest":
                i += 1
                guard let g = GuestType(rawValue: argv[i]) else {
                    FileHandle.standardError.write(Data("Unknown guest: \(argv[i]). Use 'mac' or 'linux'.\n".utf8))
                    exit(2)
                }
                cli.guest = g
            case "--bundle":
                i += 1
                cli.bundle = URL(fileURLWithPath: NSString(string: argv[i]).expandingTildeInPath)
            case "--ipsw":
                i += 1
                cli.ipsw = URL(fileURLWithPath: NSString(string: argv[i]).expandingTildeInPath)
            case "--iso":
                i += 1
                cli.iso = URL(fileURLWithPath: NSString(string: argv[i]).expandingTildeInPath)
            case "--disk-gb":
                i += 1
                cli.diskSizeGB = Int(argv[i]) ?? 64
            case "--help", "-h":
                printUsage(); exit(0)
            default:
                FileHandle.standardError.write(Data("Unknown arg: \(a)\n".utf8))
                printUsage(); exit(2)
            }
            i += 1
        }
        return cli
    }

    static func printUsage() {
        print("""
        SimpleVM — minimal macOS / Linux guest VM on Apple Silicon

        Usage:
          simple-vm --validate [--bundle <dir>]
          simple-vm --install --guest mac (--ipsw <path> | --download) [--bundle <dir>] [--disk-gb N]
          simple-vm --install --guest linux [--bundle <dir>] [--disk-gb N] [--rosetta]
          simple-vm [--run] [--bundle <dir>] [--iso <path>] [--headless]

        Modes:
          --validate    Build a VM config and run validate(). No IPSW download.
          --install     Create or restore a bundle.
                          --guest mac    requires --ipsw <path> or --download (~14 GB)
                          --guest linux  creates an empty bundle; boot with --iso to install
          --run         (default) Boot an existing bundle. Auto-detects guest type
                        from settings.json. For Linux first-boot, pass --iso <path>.
          --headless    Run without the SwiftUI window (use with --run).
          --rosetta     (Linux only) Enable Rosetta-for-Linux x86_64 binary translation.

        Defaults:
          --bundle  ~/VMs/SimpleVM
          --guest   mac
          --disk-gb 64
        """)
    }
}

extension Runner {
    @MainActor static var activeForSignal: Runner?
}

@main
struct SimpleVMApp {
    static func main() {
        let cli = CLI.parse(CommandLine.arguments)
        let bundle = VMBundle(directory: cli.bundle)

        switch cli.mode {
        case .validate:
            runMainActor(label: "Validate") {
                try await runValidate(bundle: bundle)
                print("OK — configuration validates.")
            }
        case .install:
            runMainActor(label: "Install") {
                switch cli.guest {
                case .mac:
                    let ipsw = try await resolveIPSW(cli: cli)
                    try await Installer().installMac(ipsw: ipsw, bundle: bundle, diskSizeGB: cli.diskSizeGB)
                case .linux:
                    try await Installer().setupLinux(
                        bundle: bundle,
                        diskSizeGB: cli.diskSizeGB,
                        enableRosetta: cli.rosetta
                    )
                }
            }
        case .run:
            if cli.headless {
                runMainActor(label: "Run") { try await runHeadless(bundle: bundle, isoURL: cli.iso) }
            } else {
                MainActor.assumeIsolated { runApp(bundle: bundle, isoURL: cli.iso) }
            }
        }
    }

    /// Run an async @MainActor task as the program's entry, exit(0) on success or
    /// stderr+exit(1) on failure. dispatchMain() yields control to the main runloop
    /// so MainActor work can execute.
    static func runMainActor(label: String, _ work: @escaping @MainActor () async throws -> Void) -> Never {
        Task { @MainActor in
            do {
                try await work()
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("\(label) failed: \(error)\n".utf8))
                exit(1)
            }
        }
        dispatchMain()
    }

    @MainActor
    static func runHeadless(bundle: VMBundle, isoURL: URL?) async throws {
        let runner = Runner()
        _ = try runner.makeVM(bundle: bundle, isoURL: isoURL)
        try await runner.start()
        Runner.activeForSignal = runner
        print("VM running. Send SIGINT (ctrl-C) to stop.")
        signal(SIGINT) { _ in
            Task { @MainActor in Runner.activeForSignal?.requestStop() }
        }
        await runner.waitUntilStopped()
    }

    /// Decide where to get the IPSW: explicit path, or download from Apple.
    @MainActor
    static func resolveIPSW(cli: CLI) async throws -> URL {
        if let p = cli.ipsw { return p }
        guard cli.download else {
            FileHandle.standardError.write(Data("--install --guest mac requires --ipsw <path> or --download\n".utf8))
            exit(2)
        }
        let cache = URL(fileURLWithPath: NSString(string: "~/VMs/cache").expandingTildeInPath)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let dest = cache.appendingPathComponent("UniversalMac_latest.ipsw")
        if FileManager.default.fileExists(atPath: dest.path) {
            print("Reusing cached IPSW at \(dest.path)")
            return dest
        }
        print("Fetching latest macOS restore image metadata…")
        let restore = try await VZMacOSRestoreImage.latestSupported
        print("Downloading IPSW from \(restore.url.absoluteString) (~14 GB)…")
        return try await Installer.downloadIPSW(from: restore.url, to: dest)
    }

    /// Validate the config end-to-end without doing an IPSW download.
    /// Uses an existing bundle when present (fastest, no network), otherwise
    /// builds a temp Mac bundle whose hardware model comes from Apple's metadata.
    @MainActor
    static func runValidate(bundle: VMBundle) async throws {
        let settingsExists = FileManager.default.fileExists(atPath: bundle.settingsFile.path)
        if settingsExists {
            print("Validating against existing bundle: \(bundle.directory.path)")
            let settings = VMSettings.load(from: bundle.settingsFile)
            _ = try VMConfiguration.build(bundle: bundle, settings: settings)
            return
        }

        print("No bundle found; fetching latest restore-image metadata for validation…")
        let restore = try await VZMacOSRestoreImage.latestSupported
        let tmp = try makeTempBundle()
        defer { try? FileManager.default.removeItem(at: tmp.directory) }

        guard let macConfig = restore.mostFeaturefulSupportedConfiguration else {
            throw VMError.ipswFailed("restore image has no supported configuration")
        }
        try macConfig.hardwareModel.dataRepresentation.write(to: tmp.hardwareModelFile)
        try VMConfiguration.createDiskImage(at: tmp.diskImage, sizeGB: 1)
        _ = try VZMacAuxiliaryStorage(
            creatingStorageAt: tmp.auxStorage,
            hardwareModel: macConfig.hardwareModel,
            options: []
        )
        let settings = VMSettings()
        _ = try VMConfiguration.buildMac(bundle: tmp, settings: settings, restoreImage: restore)
    }

    static func makeTempBundle() throws -> VMBundle {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimpleVM-validate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return VMBundle(directory: dir)
    }
}
