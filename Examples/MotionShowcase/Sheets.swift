import MotionRender
import SwiftUI

/// Edits render settings as a draft; nothing changes until Apply.
struct RenderSettingsSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: ShowcaseSettings
  let apply: (ShowcaseSettings) -> Void

  init(settings: ShowcaseSettings, apply: @escaping (ShowcaseSettings) -> Void) {
    _draft = State(initialValue: settings)
    self.apply = apply
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Backend", selection: $draft.render.backend) {
            Text("Skia CPU").tag(RenderBackend.cpu)
            Text("Skia Metal (GPU)").tag(RenderBackend.gpu)
          }
          Picker("Scale", selection: $draft.render.scale) {
            ForEach([1.0, 2.0, 3.0, 4.0], id: \.self) { Text("\(Int($0))×").tag($0) }
          }
        } header: {
          Text("Renderer")
        } footer: {
          Text("Scale multiplies output pixels per composition pixel, like Remotion's scale option.")
        }
        Section("Playback") {
          Toggle("Loop playback", isOn: $draft.loops)
          Toggle("Show layout bounds", isOn: $draft.showsLayoutBounds)
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Render Settings")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            apply(draft)
            dismiss()
          }
        }
      }
    }
    // Full-height content keeps the sheet's navigation title from being clipped on macOS.
    .frame(minWidth: 440, idealWidth: 460, minHeight: 360, idealHeight: 380, maxHeight: .infinity)
  }
}

/// Chooses a Remotion-style TSX project folder and its entry file.
struct OpenProjectSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: ProjectLocation
  @State private var importing = false
  let open: (ProjectLocation) -> Void

  init(location: ProjectLocation, open: @escaping (ProjectLocation) -> Void) {
    _draft = State(initialValue: location)
    self.open = open
  }

  private var entryExists: Bool {
    FileManager.default.fileExists(atPath: draft.project.appendingPathComponent(draft.entry).path)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          LabeledContent("Folder") {
            HStack {
              Text(draft.project.path)
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(.secondary)
              Button("Choose…") { importing = true }
            }
          }
          TextField("Entry file", text: $draft.entry, prompt: Text("src/index.ts"))
        } header: {
          Text("Project")
        } footer: {
          if entryExists {
            Text("The entry must call registerRoot. Only the supported Remotion subset renders.")
          } else {
            Label("Entry file not found in this folder", systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Open Project")
      .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
        if case .success(let url) = result { draft.project = url }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Open") {
            open(draft)
            dismiss()
          }
          .disabled(!entryExists)
        }
      }
    }
    .frame(minWidth: 520, idealWidth: 540, minHeight: 300, idealHeight: 320, maxHeight: .infinity)
  }
}
