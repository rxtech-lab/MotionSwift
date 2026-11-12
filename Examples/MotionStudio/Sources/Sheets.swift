import MotionCore
import MotionPortable
import MotionRender
import MotionRuntime
import SwiftUI

/// Fetches a module graph from `motionswift serve-graph` on a Mac or from the cloud graph service.
/// The server defaults to localhost in Debug builds and the production domain in Release builds.
struct SyncSheet: View {
  let store: ProjectStore
  let onSynced: (ProjectStore.SyncedGraph) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var server = ProjectStore.defaultServer
  @State private var name = "Synced Project"
  @State private var syncing = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Server", text: $server)
            .autocorrectionDisabled()
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif
          TextField("Name", text: $name)
        } footer: {
          Text(
            "On your Mac: motionswift serve-graph --project <dir> --entry src/index.ts. Use --host=0.0.0.0 and "
              + "your Mac's address for a device. Graphs bundle npm packages that the on-device vendor graph "
              + "(\(Vendor.identity)) does not include.")
        }
        if let error {
          Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Sync Module Graph")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Sync") { Task { await sync() } }.disabled(syncing || URL(string: server)?.scheme == nil)
        }
      }
      .overlay {
        if syncing {
          ProgressView("Fetching graph…")
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
      }
      .disabled(syncing)
    }
    #if os(macOS)
    .frame(minWidth: 480, idealWidth: 520, maxWidth: .infinity, minHeight: 320, idealHeight: 360, maxHeight: .infinity)
    #endif
  }

  private func sync() async {
    guard let url = URL(string: server) else { return }
    syncing = true
    error = nil
    defer { syncing = false }
    do {
      let graph = try await GraphSyncClient(baseURL: url).fetchGraph()
      let saved = try store.save(graph, named: name)
      onSynced(saved)
      dismiss()
    } catch {
      self.error = String(describing: error)
    }
  }
}

/// Measures the no-JIT preview budget on this device for every composition of a project.
struct BudgetSheet: View {
  let project: ProjectStore.Project
  @Environment(\.dismiss) private var dismiss
  @State private var scale = 1.0
  @State private var reports: [PreviewBudgetReport] = []
  @State private var running = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Preview scale", selection: $scale) {
            Text("0.5×").tag(0.5)
            Text("1×").tag(1.0)
            Text("2×").tag(2.0)
          }
          .pickerStyle(.segmented)
          LabeledContent("JavaScriptCore JIT", value: PreviewBudget.jitMode)
          LabeledContent("Platform", value: PreviewBudget.platform)
          if !reports.isEmpty {
            Text("Measured \(reports.count) compositions").accessibilityIdentifier("budget-status")
          }
        } footer: {
          Text(
            "Each frame evaluates the bundle in a fresh JavaScriptCore VM, then lays out, paints (Skia, Metal) "
              + "and reads back pixels. Budget = 1000 ms / fps.")
        }
        if let error {
          Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
        }
        ForEach(reports, id: \.composition) { report in
          Section(report.composition) {
            LabeledContent("JavaScript p50", value: ms(report.javascript.p50))
            LabeledContent("Layout + paint p50", value: ms(report.paint.p50))
            LabeledContent("Readback p50", value: ms(report.readback.p50))
            LabeledContent("Total p50 / p95", value: "\(ms(report.total.p50)) / \(ms(report.total.p95))")
            LabeledContent("Cold first frame", value: ms(report.coldMs))
            LabeledContent(
              "Within \(ms(report.budgetMs)) budget",
              value: report.withinBudget.formatted(.percent.precision(.fractionLength(0))))
            LabeledContent("Sustainable preview", value: String(format: "%.1f fps", report.sustainableFPS))
          }
          .accessibilityIdentifier("budget-\(report.composition)")
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Preview Budget")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Measure") { Task { await measure() } }.disabled(running)
        }
        if !reports.isEmpty, let json = try? json() {
          ToolbarItem { ShareLink(item: json, preview: SharePreview("Preview budget report")) }
        }
      }
      .overlay {
        if running {
          ProgressView("Rendering frames…")
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 520, idealWidth: 560, maxWidth: .infinity, minHeight: 520, idealHeight: 640, maxHeight: .infinity)
    #endif
    .sensoryFeedback(.success, trigger: reports.count) { _, new in new > 0 }
  }

  private func ms(_ value: Double) -> String { String(format: "%.1f ms", value) }

  private func json() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return String(bytes: try encoder.encode(reports), encoding: .utf8) ?? "[]"
  }

  private func measure() async {
    running = true
    error = nil
    defer { running = false }
    let directory = project.directory
    let scale = scale
    do {
      reports = try await withCheckedThrowingContinuation { continuation in
        // Babel, React and the reconciler recurse deeply: use the render workers' 8 MiB stack.
        let thread = Thread {
          continuation.resume(with: Result {
            let bundle = try GraphLinker.link(PortableCompiler().compile(project: directory, entry: ProjectStore.entry))
            return try Runtime(bundle: bundle).compositions().map { composition in
              try PreviewBudget.measure(bundle: bundle, composition: composition, scale: scale, backend: .gpu)
            }
          })
        }
        thread.stackSize = 8 << 20
        thread.qualityOfService = .userInitiated
        thread.start()
      }
      // UI tests collect the measurements from the app's Documents (or Application Support) folder.
      if ProcessInfo.processInfo.arguments.contains("-uiTesting"), let json = try? json() {
        try? json.write(to: ProjectStore.defaultRoot.appendingPathComponent("preview-budget.json"), atomically: true, encoding: .utf8)
      }
    } catch {
      self.error = String(describing: error)
    }
  }
}
