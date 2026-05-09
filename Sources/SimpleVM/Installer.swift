import Foundation
import Virtualization

@MainActor
final class Installer: NSObject {
    private var progressObservation: NSKeyValueObservation?

    func installMac(ipsw: URL, bundle: VMBundle, diskSizeGB: Int) async throws {
        try bundle.ensureDirectory()

        print("Loading restore image: \(ipsw.lastPathComponent)")
        let restoreImage = try await VZMacOSRestoreImage.image(from: ipsw)
        guard let macConfig = restoreImage.mostFeaturefulSupportedConfiguration else {
            throw VMError.ipswFailed("no supported configuration")
        }
        guard macConfig.hardwareModel.isSupported else {
            throw VMError.ipswFailed("hardware model not supported on this host")
        }

        try macConfig.hardwareModel.dataRepresentation.write(to: bundle.hardwareModelFile)
        try VMConfiguration.createDiskImage(at: bundle.diskImage, sizeGB: diskSizeGB)

        if !FileManager.default.fileExists(atPath: bundle.auxStorage.path) {
            _ = try VZMacAuxiliaryStorage(
                creatingStorageAt: bundle.auxStorage,
                hardwareModel: macConfig.hardwareModel,
                options: []
            )
        }

        var settings = VMSettings.load(from: bundle.settingsFile)
        settings.guestType = .mac
        try settings.save(to: bundle.settingsFile)

        let vmConfig = try VMConfiguration.buildMac(
            bundle: bundle,
            settings: settings,
            restoreImage: restoreImage
        )
        let vm = VZVirtualMachine(configuration: vmConfig)

        let installer = VZMacOSInstaller(virtualMachine: vm, restoringFromImageAt: ipsw)
        progressObservation = installer.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
            let pct = Int(progress.fractionCompleted * 100)
            print("Install progress: \(pct)%")
        }

        print("Starting macOS install (this takes 10–30 minutes)…")
        try await installer.install()
        progressObservation = nil
        print("Install complete. Bundle at: \(bundle.directory.path)")
    }

    /// Set up a Linux bundle: disk, EFI vars, identifier, settings. Booting the
    /// distro installer is a separate step (`simple-vm --iso path.iso`).
    func setupLinux(bundle: VMBundle, diskSizeGB: Int, enableRosetta: Bool) async throws {
        try bundle.ensureDirectory()
        try VMConfiguration.createDiskImage(at: bundle.diskImage, sizeGB: diskSizeGB)
        _ = try bundle.loadOrCreateEFIVarStore()
        _ = try bundle.loadOrCreateGenericIdentifier()

        var settings = VMSettings.load(from: bundle.settingsFile)
        settings.guestType = .linux
        settings.enableRosetta = enableRosetta
        try settings.save(to: bundle.settingsFile)

        if enableRosetta {
            try await ensureRosettaInstalled()
        }

        print("""
        Linux bundle ready at: \(bundle.directory.path)

        Boot the installer with your distro ISO (arm64):
          simple-vm --bundle \(bundle.directory.path) --iso /path/to/distro.iso

        After install completes, shut down the guest, then boot from disk:
          simple-vm --bundle \(bundle.directory.path)
        """)
    }

    private func ensureRosettaInstalled() async throws {
        switch VZLinuxRosettaDirectoryShare.availability {
        case .installed:
            return
        case .notInstalled:
            print("Installing Rosetta for Linux (a system prompt may appear)…")
            try await VZLinuxRosettaDirectoryShare.installRosetta()
        case .notSupported:
            print("Rosetta for Linux is not supported on this host; continuing without it.")
        @unknown default:
            return
        }
    }

    static func downloadIPSW(from url: URL, to destination: URL) async throws -> URL {
        let session = URLSession(configuration: .default)
        let (tmp, response) = try await session.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw VMError.ipswFailed("download returned HTTP \(http.statusCode)")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
        print("Downloaded IPSW to \(destination.path)")
        return destination
    }
}

extension VZMacOSRestoreImage {
    static func image(from url: URL) async throws -> VZMacOSRestoreImage {
        try await withCheckedThrowingContinuation { cont in
            VZMacOSRestoreImage.load(from: url) { result in
                cont.resume(with: result)
            }
        }
    }
}
