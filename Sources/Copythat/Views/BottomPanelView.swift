import AppKit
import SwiftUI

struct BottomPanelView: View {
    private let panelCornerRadius: CGFloat = 24
    private let settings: AppSettings
    @ObservedObject private var store: ClipboardStore
    @FocusState private var searchFocused: Bool
    let onClose: () -> Void
    let onPaste: () -> Void

    init(model: AppModel, onClose: @escaping () -> Void, onPaste: @escaping () -> Void) {
        settings = model.settings
        _store = ObservedObject(wrappedValue: model.store)
        self.onClose = onClose
        self.onPaste = onPaste
    }

    var body: some View {
        panelContainer
            .onAppear {
                searchFocused = true
                store.selectFirstVisibleItem()
            }
            .onChange(of: store.searchText) {
                store.selectFirstVisibleItem()
            }
            .onMoveCommand { direction in
                switch direction {
                case .left:
                    store.moveSelection(-1)
                case .right:
                    store.moveSelection(1)
                default:
                    break
                }
            }
            .onExitCommand(perform: onClose)
    }

    private var panelContainer: some View {
        let panelShape = RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)

        return ZStack {
            VisualEffectView(
                material: .hudWindow,
                blendingMode: .behindWindow,
                cornerRadius: panelCornerRadius
            )

            VStack(spacing: 8) {
                header
                timeline
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 18)
            .frame(maxHeight: .infinity)
        }
        .background(Color.clear)
        .clipShape(panelShape)
        .contentShape(panelShape)
        .overlay {
            panelShape
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .compositingGroup()
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                searchField
                pinboardPicker
                closeButton
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    searchField
                    closeButton
                }
                pinboardPicker
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(CopythatFont.font(size: 17, weight: .medium))
                .focused($searchFocused)
                .onSubmit(onPaste)
        }
        .padding(.horizontal, 13)
        .frame(height: 40)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var pinboardPicker: some View {
        Picker("Pinboard", selection: $store.selectedBoardID) {
            Text(Pinboard.all.title).tag(Pinboard.all.id)
            Text(Pinboard.pinned.title).tag(Pinboard.pinned.id)
            ForEach(settings.customPinboards, id: \.self) { name in
                Text(name).tag(Pinboard.custom(name).id)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: max(210, CGFloat(210 + settings.customPinboards.count * 72)))
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.borderless)
        .help("Close")
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 30) {
                    if store.filteredItems.isEmpty {
                        EmptyTimelineView()
                    } else {
                        ForEach(store.filteredItems) { item in
                            ClipboardCardView(
                                item: item,
                                pinboards: settings.customPinboards,
                                isSelected: item.id == store.selectedItem?.id,
                                sourceLogoIcon: store.sourceIconByApp[item.sourceApp],
                                onSelect: { store.select(item) },
                                onPaste: onPaste,
                                onTogglePin: { store.togglePin(item) },
                                onMoveToPinboard: { name in store.move(item, toPinboard: name) },
                                onDelete: { store.remove(item) }
                            )
                            .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .frame(height: 294)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .onChange(of: store.selectedItem?.id) { _, id in
                guard let id else { return }
                withAnimation(.snappy(duration: 0.18)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let message = store.permissionMessage {
                HStack(spacing: 8) {
                    Label(message, systemImage: "accessibility")
                        .foregroundStyle(.orange)
                    Button("Open Settings") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.link)
                }
            } else {
                Label("Return paste  •  Esc close  •  \(settings.shortcut) show", systemImage: "keyboard")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(store.filteredItems.count) items")
                .foregroundStyle(.secondary)
        }
        .font(CopythatFont.font(size: 11, weight: .medium))
        .lineLimit(1)
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}
