import MotionCore
import MotionSwiftUI
import SwiftUI

/// The visual editor: canvas, transport and an inspector. Status (compiling, saving, refusals,
/// write-back conflicts) appears as overlays; edits use dedicated sheets and confirmations.
public struct MotionEditorView: View {
  @Bindable private var model: EditorModel
  @State private var zoom = 1.0
  @State private var showsInspector: Bool

  public init(model: EditorModel) {
    self.model = model
    #if os(iOS)
    _showsInspector = State(initialValue: UIDevice.current.userInterfaceIdiom == .pad)
    #else
    _showsInspector = State(initialValue: true)
    #endif
  }

  public var body: some View {
    editorPanes
    .overlay(alignment: .top) { StatusBadge(model: model).padding(.top, 10) }
    .overlay(alignment: .bottom) { NoticeOverlay(notice: model.notice).padding(.bottom, 14) }
    .overlay { FailureOverlay(model: model) }
    .inspector(isPresented: $showsInspector) {
      EditorInspector(model: model)
        .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
    .toolbar { toolbar }
    .task {
      if model.player.composition == nil, model.status == .idle { await model.open() }
    }
    .onChange(of: model.player.composition?.id) { model.resetTimelineSelection() }
    .onChange(of: model.player.currentFrame) { model.observeKeyframePlayhead() }
    .onChange(of: model.player.displayedFrame?.frame) { model.observeTimelineFrame() }
    .animation(.snappy, value: model.notice)
    .sensoryFeedback(.selection, trigger: model.selectionFeedback)
    .sensoryFeedback(.alignment, trigger: model.snapFeedback)
    .sensoryFeedback(.impact(weight: .medium), trigger: model.commitFeedback)
    .sensoryFeedback(.error, trigger: model.refusalFeedback)
  }

  @ViewBuilder private var editorPanes: some View {
    #if os(macOS)
    VSplitView {
      preview.frame(minHeight: 180)
      EditorTimeline(model: model).frame(minHeight: 180, idealHeight: 260, maxHeight: 500)
    }
    #else
    GeometryReader { geometry in
      VStack(spacing: 0) {
        preview.frame(maxHeight: .infinity)
        Divider()
        EditorTimeline(model: model).frame(height: min(280, geometry.size.height * 0.45))
      }
    }
    #endif
  }

  private var preview: some View {
    VStack(spacing: 0) {
      EditorCanvas(model: model, zoom: $zoom)
      MotionTransportBar(player: model.player)
        .padding(.horizontal, 12).padding(.vertical, 8).background(.bar)
    }
  }

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    ToolbarItemGroup {
      if model.player.compositions.count > 1 {
        Menu {
          ForEach(model.player.compositions, id: \.id) { composition in
            Button(composition.id) { model.player.select(compositionID: composition.id) }
          }
        } label: {
          Label(model.player.composition?.id ?? "Composition", systemImage: "rectangle.stack")
        }
        .accessibilityIdentifier("composition-menu")
        .disabled(model.status != .idle)
      }
      Button("Undo", systemImage: "arrow.uturn.backward") { Task { await model.undo() } }
        .keyboardShortcut("z")
        .disabled(!model.canUndo || model.status != .idle)
        .help(model.undoActionName.map { "Undo \($0)" } ?? "Undo")
      Button("Redo", systemImage: "arrow.uturn.forward") { Task { await model.redo() } }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(!model.canRedo || model.status != .idle)
        .help(model.redoActionName.map { "Redo \($0)" } ?? "Redo")
      Toggle(isOn: $model.snapsToGuides) { Label("Snap", systemImage: "square.and.line.vertical.and.square") }
        .help("Snap to canvas and sibling edges and centers")
      Button("Fit", systemImage: "arrow.down.right.and.arrow.up.left") { withAnimation { zoom = 1 } }
        .disabled(zoom == 1)
        .help("Reset zoom")
      Button("Inspector", systemImage: "sidebar.trailing") { showsInspector.toggle() }
        .help("Show or hide the inspector")
    }
  }
}

private struct StatusBadge: View {
  let model: EditorModel

  var body: some View {
    let label: String? = switch model.status {
    case .compiling: "Compiling…"
    case .saving: "Saving…"
    default: model.isCapturingKeyframe ? "Capturing keyframe…" : model.isGesturing ? "Live preview" : nil
    }
    if let label {
      HStack(spacing: 8) {
        if !model.isGesturing { ProgressView().controlSize(.small) }
        Text(label).font(.callout)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(.regularMaterial, in: Capsule())
      .transition(.opacity)
    }
  }
}

private struct NoticeOverlay: View {
  let notice: EditorModel.Notice?

  var body: some View {
    if let notice {
      let (icon, tint): (String, Color) = switch notice.kind {
      case .info: ("checkmark.circle.fill", .green)
      case .refusal: ("hand.raised.fill", .orange)
      case .conflict: ("exclamationmark.arrow.triangle.2.circlepath", .yellow)
      case .failure: ("xmark.octagon.fill", .red)
      }
      Label {
        Text(notice.message).lineLimit(3)
      } icon: {
        Image(systemName: icon).foregroundStyle(tint)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.regularMaterial, in: Capsule())
      .shadow(radius: 6, y: 2)
      .padding(.horizontal)
      .transition(.move(edge: .bottom).combined(with: .opacity))
      .accessibilityIdentifier("editor-notice")
    }
  }
}

private struct FailureOverlay: View {
  let model: EditorModel

  var body: some View {
    let message: String? = if case .failed(let message) = model.status { message } else { model.player.renderError }
    if let message {
      VStack(alignment: .leading, spacing: 8) {
        Label("Cannot preview this project", systemImage: "exclamationmark.triangle.fill")
          .font(.headline)
          .foregroundStyle(.orange)
        ScrollView {
          Text(message).font(.caption.monospaced()).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 160)
        Button("Reload from Disk") { Task { await model.open(compositionID: model.player.composition?.id) } }
      }
      .padding(16)
      .frame(maxWidth: 460)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
      .padding()
    }
  }
}
