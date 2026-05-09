import Foundation
import Virtualization

enum VMConfiguration {
    static func build(
        bundle: VMBundle,
        settings: VMSettings,
        restoreImage: VZMacOSRestoreImage? = nil,
        isoURL: URL? = nil
    ) throws -> VZVirtualMachineConfiguration {
        switch settings.guestType {
        case .mac:   return try buildMac(bundle: bundle, settings: settings, restoreImage: restoreImage)
        case .linux: return try buildLinux(bundle: bundle, settings: settings, isoURL: isoURL)
        }
    }

    static func buildMac(
        bundle: VMBundle,
        settings: VMSettings,
        restoreImage: VZMacOSRestoreImage? = nil
    ) throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()

        let macConfig = restoreImage?.mostFeaturefulSupportedConfiguration
        let hostCPU = ProcessInfo.processInfo.activeProcessorCount
        let minCPU = macConfig?.minimumSupportedCPUCount ?? 2
        config.cpuCount = max(minCPU, min(settings.cpuCount, hostCPU))

        let requestedMem = UInt64(settings.memoryGB) * 1024 * 1024 * 1024
        let minMem = macConfig?.minimumSupportedMemorySize ?? (2 * 1024 * 1024 * 1024)
        config.memorySize = max(minMem, requestedMem)

        let platform = VZMacPlatformConfiguration()
        platform.hardwareModel = try macConfig?.hardwareModel ?? bundle.loadHardwareModel()
        platform.auxiliaryStorage = bundle.loadAuxStorage()
        platform.machineIdentifier = try bundle.loadOrCreateMacIdentifier()
        config.platform = platform

        config.bootLoader = VZMacOSBootLoader()

        let attachment = try VZDiskImageStorageDeviceAttachment(url: bundle.diskImage, readOnly: false)
        config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: attachment)]

        let net = VZVirtioNetworkDeviceConfiguration()
        net.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [net]

        let graphics = VZMacGraphicsDeviceConfiguration()
        graphics.displays = [
            VZMacGraphicsDisplayConfiguration(
                widthInPixels: settings.displayWidth,
                heightInPixels: settings.displayHeight,
                pixelsPerInch: settings.displayPPI
            )
        ]
        config.graphicsDevices = [graphics]

        config.keyboards = [VZMacKeyboardConfiguration()]
        config.pointingDevices = [VZMacTrackpadConfiguration()]

        config.audioDevices = [defaultAudioDevice()]

        try validate(config)
        return config
    }

    static func buildLinux(
        bundle: VMBundle,
        settings: VMSettings,
        isoURL: URL? = nil
    ) throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()

        let hostCPU = ProcessInfo.processInfo.activeProcessorCount
        config.cpuCount = max(1, min(settings.cpuCount, hostCPU))
        let requestedMem = UInt64(settings.memoryGB) * 1024 * 1024 * 1024
        config.memorySize = max(512 * 1024 * 1024, requestedMem)

        let platform = VZGenericPlatformConfiguration()
        platform.machineIdentifier = try bundle.loadOrCreateGenericIdentifier()
        config.platform = platform

        let bootLoader = VZEFIBootLoader()
        bootLoader.variableStore = try bundle.loadOrCreateEFIVarStore()
        config.bootLoader = bootLoader

        var storage: [VZStorageDeviceConfiguration] = []
        let disk = try VZDiskImageStorageDeviceAttachment(url: bundle.diskImage, readOnly: false)
        storage.append(VZVirtioBlockDeviceConfiguration(attachment: disk))
        if let iso = isoURL {
            guard FileManager.default.fileExists(atPath: iso.path) else {
                throw VMError.isoMissing(iso.path)
            }
            let isoAttach = try VZDiskImageStorageDeviceAttachment(url: iso, readOnly: true)
            storage.append(VZUSBMassStorageDeviceConfiguration(attachment: isoAttach))
        }
        config.storageDevices = storage

        let net = VZVirtioNetworkDeviceConfiguration()
        net.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [net]

        let graphics = VZVirtioGraphicsDeviceConfiguration()
        graphics.scanouts = [
            VZVirtioGraphicsScanoutConfiguration(
                widthInPixels: settings.displayWidth,
                heightInPixels: settings.displayHeight
            )
        ]
        config.graphicsDevices = [graphics]

        config.keyboards = [VZUSBKeyboardConfiguration()]
        config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

        config.audioDevices = [defaultAudioDevice()]

        if settings.enableRosetta, VZLinuxRosettaDirectoryShare.availability == .installed {
            let rosetta = try VZLinuxRosettaDirectoryShare()
            let fs = VZVirtioFileSystemDeviceConfiguration(tag: "rosetta")
            fs.share = rosetta
            config.directorySharingDevices = [fs]
        }

        try validate(config)
        return config
    }

    /// Sparse-allocate a disk image at `url`. No-op if the file already exists.
    static func createDiskImage(at url: URL, sizeGB: Int) throws {
        if FileManager.default.fileExists(atPath: url.path) { return }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(sizeGB) * 1024 * 1024 * 1024)
    }

    private static func defaultAudioDevice() -> VZVirtioSoundDeviceConfiguration {
        let audio = VZVirtioSoundDeviceConfiguration()
        let outStream = VZVirtioSoundDeviceOutputStreamConfiguration()
        outStream.sink = VZHostAudioOutputStreamSink()
        let inStream = VZVirtioSoundDeviceInputStreamConfiguration()
        inStream.source = VZHostAudioInputStreamSource()
        audio.streams = [outStream, inStream]
        return audio
    }

    private static func validate(_ config: VZVirtualMachineConfiguration) throws {
        do {
            try config.validate()
        } catch {
            throw VMError.configInvalid("\(error). Did you codesign with the virtualization entitlement?")
        }
    }
}
