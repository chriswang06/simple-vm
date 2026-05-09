import Foundation
import Virtualization

struct VMBundle {
    let directory: URL

    var diskImage: URL              { directory.appendingPathComponent("disk.img") }
    var settingsFile: URL           { directory.appendingPathComponent("settings.json") }

    var auxStorage: URL             { directory.appendingPathComponent("aux.bin") }
    var identifierFile: URL         { directory.appendingPathComponent("identifier.bin") }
    var hardwareModelFile: URL      { directory.appendingPathComponent("hardware-model.bin") }

    var efiVarStoreFile: URL        { directory.appendingPathComponent("efi-vars.bin") }
    var genericIdentifierFile: URL  { directory.appendingPathComponent("generic-id.bin") }

    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: macOS guest

    func loadHardwareModel() throws -> VZMacHardwareModel {
        let data = try Data(contentsOf: hardwareModelFile)
        guard let model = VZMacHardwareModel(dataRepresentation: data) else {
            throw VMError.bundleCorrupt("hardware-model.bin is not a valid VZMacHardwareModel")
        }
        guard model.isSupported else {
            throw VMError.bundleCorrupt("hardware model is not supported on this host")
        }
        return model
    }

    func loadOrCreateMacIdentifier() throws -> VZMacMachineIdentifier {
        if FileManager.default.fileExists(atPath: identifierFile.path) {
            let data = try Data(contentsOf: identifierFile)
            guard let id = VZMacMachineIdentifier(dataRepresentation: data) else {
                throw VMError.bundleCorrupt("identifier.bin is not a valid VZMacMachineIdentifier")
            }
            return id
        }
        let id = VZMacMachineIdentifier()
        try id.dataRepresentation.write(to: identifierFile)
        return id
    }

    func loadAuxStorage() -> VZMacAuxiliaryStorage {
        VZMacAuxiliaryStorage(url: auxStorage)
    }

    // MARK: Linux guest

    func loadOrCreateGenericIdentifier() throws -> VZGenericMachineIdentifier {
        if FileManager.default.fileExists(atPath: genericIdentifierFile.path) {
            let data = try Data(contentsOf: genericIdentifierFile)
            guard let id = VZGenericMachineIdentifier(dataRepresentation: data) else {
                throw VMError.bundleCorrupt("generic-id.bin is not a valid VZGenericMachineIdentifier")
            }
            return id
        }
        let id = VZGenericMachineIdentifier()
        try id.dataRepresentation.write(to: genericIdentifierFile)
        return id
    }

    func loadOrCreateEFIVarStore() throws -> VZEFIVariableStore {
        if FileManager.default.fileExists(atPath: efiVarStoreFile.path) {
            return VZEFIVariableStore(url: efiVarStoreFile)
        }
        return try VZEFIVariableStore(creatingVariableStoreAt: efiVarStoreFile)
    }
}

struct VMSettings: Codable {
    var guestType: GuestType = .mac
    var cpuCount: Int = 4
    var memoryGB: Int = 4
    var displayWidth: Int = 1920
    var displayHeight: Int = 1200
    var displayPPI: Int = 220
    var enableRosetta: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guestType      = try c.decodeIfPresent(GuestType.self, forKey: .guestType) ?? .mac
        cpuCount       = try c.decodeIfPresent(Int.self,       forKey: .cpuCount) ?? 4
        memoryGB       = try c.decodeIfPresent(Int.self,       forKey: .memoryGB) ?? 4
        displayWidth   = try c.decodeIfPresent(Int.self,       forKey: .displayWidth) ?? 1920
        displayHeight  = try c.decodeIfPresent(Int.self,       forKey: .displayHeight) ?? 1200
        displayPPI     = try c.decodeIfPresent(Int.self,       forKey: .displayPPI) ?? 220
        enableRosetta  = try c.decodeIfPresent(Bool.self,      forKey: .enableRosetta) ?? false
    }

    static func load(from url: URL) -> VMSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(VMSettings.self, from: data) else {
            return VMSettings()
        }
        return settings
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }
}

enum VMError: Error, CustomStringConvertible {
    case bundleCorrupt(String)
    case ipswFailed(String)
    case configInvalid(String)
    case isoMissing(String)

    var description: String {
        switch self {
        case .bundleCorrupt(let m): return "Bundle corrupt: \(m)"
        case .ipswFailed(let m):    return "IPSW failed: \(m)"
        case .configInvalid(let m): return "Config invalid: \(m)"
        case .isoMissing(let m):    return "ISO missing: \(m)"
        }
    }
}
