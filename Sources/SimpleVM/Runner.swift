import Foundation
import Virtualization

@MainActor
final class Runner: NSObject, VZVirtualMachineDelegate {
    private(set) var virtualMachine: VZVirtualMachine?
    private var stopContinuation: CheckedContinuation<Void, Never>?

    func makeVM(bundle: VMBundle, isoURL: URL? = nil) throws -> VZVirtualMachine {
        let settings = VMSettings.load(from: bundle.settingsFile)
        let config = try VMConfiguration.build(bundle: bundle, settings: settings, isoURL: isoURL)
        let vm = VZVirtualMachine(configuration: config)
        vm.delegate = self
        self.virtualMachine = vm
        return vm
    }

    func start() async throws {
        guard let vm = virtualMachine else { return }
        try await vm.start()
    }

    func requestStop() {
        guard let vm = virtualMachine else { return }
        do {
            try vm.requestStop()
        } catch {
            print("requestStop failed: \(error). Forcing stop.")
            Task { @MainActor in try? await vm.stop() }
        }
    }

    func waitUntilStopped() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            guard let vm = virtualMachine, vm.state != .stopped else {
                cont.resume()
                return
            }
            self.stopContinuation = cont
        }
    }

    nonisolated func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        Task { @MainActor in
            print("Guest stopped.")
            self.stopContinuation?.resume()
            self.stopContinuation = nil
        }
    }

    nonisolated func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        Task { @MainActor in
            print("Guest stopped with error: \(error)")
            self.stopContinuation?.resume()
            self.stopContinuation = nil
        }
    }
}
