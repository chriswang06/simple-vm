import SwiftUI
import AppKit
import Virtualization

struct VirtualMachineViewRepresentable: NSViewRepresentable {
    let virtualMachine: VZVirtualMachine

    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        view.virtualMachine = virtualMachine
        view.capturesSystemKeys = true
        if #available(macOS 14.0, *) {
            view.automaticallyReconfiguresDisplay = true
        }
        return view
    }

    func updateNSView(_ nsView: VZVirtualMachineView, context: Context) {
        nsView.virtualMachine = virtualMachine
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var runner = Runner()
    @Published var vm: VZVirtualMachine?
    @Published var error: String?

    func boot(bundle: VMBundle, isoURL: URL? = nil) {
        do {
            self.vm = try runner.makeVM(bundle: bundle, isoURL: isoURL)
            Task {
                do {
                    try await runner.start()
                } catch {
                    self.error = "Start failed: \(error)"
                    self.vm = nil
                }
            }
        } catch {
            self.error = "\(error)"
        }
    }
}

struct ContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Group {
            if let vm = state.vm {
                VirtualMachineViewRepresentable(virtualMachine: vm)
                    .frame(minWidth: 1280, minHeight: 800)
            } else if let err = state.error {
                Text(err).padding()
            } else {
                ProgressView("Booting…").padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Stop") { state.runner.requestStop() }
            }
        }
    }
}

@MainActor
func runApp(bundle: VMBundle, isoURL: URL? = nil) {
    let state = AppState()
    state.boot(bundle: bundle, isoURL: isoURL)

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let hosting = NSHostingController(rootView: ContentView(state: state))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "SimpleVM"
    window.contentViewController = hosting
    window.center()
    window.makeKeyAndOrderFront(nil)

    app.activate(ignoringOtherApps: true)
    app.run()
}
