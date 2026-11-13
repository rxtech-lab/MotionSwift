import MotionCore
import MotionSwiftUI
import SwiftUI

/// The 3D fixtures (`tests/three`): @remotion/three + React Three Fiber scenes with keyframed
/// cameras, moving and rotating meshes, animated lights and a USDZ model, drawn by the native Metal
/// renderer. The same scenes gate visual parity and performance against Remotion in CI.
enum Showcase3D {
  struct Scene: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let icon: String
    let features: [String]
  }

  static var project: URL { ShowcaseDefaults.repository.appendingPathComponent("tests/three") }

  static var source: MotionSource {
    .project(repository: ShowcaseDefaults.repository, project: project, entry: ShowcaseDefaults.entry)
  }

  static let scenes = [
    Scene(id: "CrystalOrbit", title: "Crystal Orbit", summary: "Torus knot, 192 crystals and glass shards in fog",
          icon: "atom", features: [
            "Keyframed camera: position, look-at target, field of view and roll",
            "Two counter-rotating rings of 96 crystals with standard, physical, Phong and Lambert materials",
            "24 transparent double-sided glass panes sorted back to front",
            "Directional, hemisphere, ambient, two point lights and an animated spotlight",
            "Linear fog, flat and smooth shading",
          ]),
    Scene(id: "NeonCity", title: "Neon City", summary: "1,156 procedural towers and a dusk flythrough",
          icon: "building.2", features: [
            "Camera flythrough with banking and a widening lens",
            "A 34×34 city whose towers pulse from the center outward",
            "Sky and fog color shift from sunset to night (exponential fog)",
            "Six moving point lights as traffic, emissive windows",
            "40 rotating translucent billboards",
          ]),
    Scene(id: "ProbeFleet", title: "Probe Fleet", summary: "A USDZ model instanced 13 times",
          icon: "cube.transparent", features: [
            "Binary USDZ (USDC) loaded with useLoader(USDLoader, staticFile(…))",
            "UsdPreviewSurface materials: metallic gold, brushed hull, emissive beacon",
            "Orbiting, tumbling copies around a hero probe",
            "Three-point lighting that changes intensity and color over time",
          ]),
    Scene(id: "GeometryLab", title: "Geometry Lab", summary: "Every geometry × material pair",
          icon: "square.grid.3x3", features: [
            "12 three.js geometries generated natively, bit-identical to three.js buffers",
            "Basic, Lambert, Phong, Standard, Physical (IOR, double-sided) and Normal materials",
            "Spotlight with penumbra and distance falloff",
          ]),
  ]

  static func scene(_ id: String) -> Scene? { scenes.first { $0.id == id } }
}

/// Live tiles for each 3D scene; selecting one navigates to its player.
struct Scenes3DView: View {
  @State private var player = MotionPlayer(configuration: .init(scale: 1, backend: .gpu))
  @State private var path: [String] = []
  @State private var error: String?

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Remotion three.js scenes rendered by MotionSwift's native Metal 3D renderer.")
            .foregroundStyle(.secondary)
          if let bundle = player.bundle {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
              ForEach(Showcase3D.scenes) { scene in
                NavigationLink(value: scene.id) {
                  VStack(alignment: .leading, spacing: 8) {
                    MotionCompositionView(source: .bundle(bundle), compositionID: scene.id,
                                          configuration: .init(scale: 1, backend: .gpu))
                      .clipShape(RoundedRectangle(cornerRadius: 10))
                    Label(scene.title, systemImage: scene.icon).font(.headline)
                    Text(scene.summary).font(.caption).foregroundStyle(.secondary)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(scene.title)")
              }
            }
          } else if let error {
            Label(error, systemImage: "exclamationmark.triangle")
              .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
          } else {
            ProgressView("Compiling 3D scenes…").frame(maxWidth: .infinity, minHeight: 240)
          }
        }
        .padding(20)
      }
      .navigationTitle("3D Scenes")
      .navigationSubtitle("ThreeCanvas · React Three Fiber · USDZ")
      .navigationDestination(for: String.self) { id in
        Scene3DPlayerView(player: player, sceneID: id)
      }
    }
    .task {
      await player.load(Showcase3D.source)
      if case .failed(let message) = player.status { error = message }
    }
    .onDisappear { player.pause() }
  }
}

/// One scene with transport controls, a details sheet and video export.
struct Scene3DPlayerView: View {
  let player: MotionPlayer
  let sceneID: String
  @State private var showsDetails = false
  @State private var showsExport = false

  var body: some View {
    MotionPlayerView(player: player)
      .padding(20)
      .navigationTitle(Showcase3D.scene(sceneID)?.title ?? sceneID)
      .navigationSubtitle(player.composition?.summary ?? "")
      .toolbar {
        ToolbarItemGroup {
          Picker("Resolution", selection: Binding(
            get: { player.configuration.scale },
            set: { player.update(configuration: .init(scale: $0, backend: .gpu)) })) {
            Text("1×").tag(1.0)
            Text("2×").tag(2.0)
            Text("3×").tag(3.0)
          }
          .pickerStyle(.segmented)
          .help("Output pixels per composition pixel; ThreeCanvas caps its WebGL-equivalent canvas at 2×, like R3F")
          Button("Scene Details", systemImage: "info.circle") { showsDetails = true }
            .help("What this scene exercises and how fast it renders")
          Button("Export Scene", systemImage: "square.and.arrow.up") {
            player.pause()
            showsExport = true
          }
          .disabled(player.bundle == nil)
        }
      }
      .sheet(isPresented: $showsDetails) {
        Scene3DDetailsSheet(scene: Showcase3D.scene(sceneID), player: player)
      }
      .sheet(isPresented: $showsExport) {
        if let bundle = player.bundle, let composition = player.composition {
          FilmExportSheet(bundle: bundle, composition: composition)
        }
      }
      .onAppear {
        player.select(compositionID: sceneID)
        player.play()
      }
      .onDisappear { player.pause() }
  }
}

private struct Scene3DDetailsSheet: View {
  @Environment(\.dismiss) private var dismiss
  let scene: Showcase3D.Scene?
  let player: MotionPlayer

  var body: some View {
    NavigationStack {
      Form {
        if let scene {
          Section("Scene") {
            ForEach(scene.features, id: \.self) { Label($0, systemImage: "checkmark.circle") }
          }
        }
        Section {
          LabeledContent("Composition", value: player.composition?.summary ?? "—")
          LabeledContent("Preview", value: player.liveFPS.map { String(format: "%.1f fps", $0) } ?? "Play to measure")
          LabeledContent("Renderer", value: "Metal, MSAA 4×, three.js r187 shading")
        } header: {
          Text("Rendering")
        } footer: {
          Text("make three-visual compares these scenes with Remotion's three.js output; make three-benchmark times both.")
        }
      }
      .formStyle(.grouped)
      .navigationTitle(scene?.title ?? "Scene")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    // Full-height content keeps the sheet's navigation title from being clipped on macOS.
    .frame(minWidth: 480, idealWidth: 520, minHeight: 420, idealHeight: 460, maxHeight: .infinity)
  }
}
