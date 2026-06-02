import AppKit
import SwiftUI

struct BottomPanelView: View {
    private let panelCornerRadius: CGFloat = 26
    private let settings: AppSettings
    @ObservedObject private var store: ClipboardStore
    @State private var searchExpanded = false
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
                searchExpanded = !store.searchText.isEmpty
                searchFocused = !store.searchText.isEmpty
                store.selectFirstVisibleItem()
            }
            .onChange(of: store.searchText) {
                store.selectFirstVisibleItem()
            }
            .onChange(of: searchFocused) { _, isFocused in
                guard !isFocused, store.searchText.isEmpty else { return }
                withAnimation(.snappy(duration: 0.16)) {
                    searchExpanded = false
                }
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
                material: .popover,
                blendingMode: .behindWindow,
                cornerRadius: panelCornerRadius
            )

            panelTint

            VStack(spacing: 9) {
                header
                timeline
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity)
        }
        .background(Color.clear)
        .clipShape(panelShape)
        .contentShape(panelShape)
        .overlay {
            panelShape
                .stroke(.white.opacity(0.66), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            panelShape
                .stroke(.white.opacity(0.22), lineWidth: 1)
                .blur(radius: 0.5)
                .offset(y: 1)
        }
        .shadow(color: Color(red: 0.95, green: 0.47, blue: 0.10).opacity(0.44), radius: 28, y: 16)
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        .compositingGroup()
    }

    private var panelTint: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.96, blue: 0.88).opacity(0.74),
                    Color(red: 1.00, green: 0.79, blue: 0.66).opacity(0.58),
                    Color(red: 1.00, green: 0.90, blue: 0.74).opacity(0.68)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [
                    Color.white.opacity(0.54),
                    Color.white.opacity(0.0)
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.51, blue: 0.12).opacity(0.34),
                    Color.clear
                ],
                center: .bottom,
                startRadius: 8,
                endRadius: 420
            )
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            searchControl
                .layoutPriority(searchExpanded ? 1 : 0)
            pinboardStrip
                .layoutPriority(2)
            addButton
        }
        .frame(height: 34)
    }

    @ViewBuilder
    private var searchControl: some View {
        if searchExpanded || !store.searchText.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(CopythatFont.font(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.20, green: 0.18, blue: 0.15).opacity(0.76))
                TextField("Search", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(CopythatFont.font(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.12))
                    .focused($searchFocused)
                    .onSubmit(onPaste)
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(CopythatFont.font(size: 12, weight: .medium))
                            .foregroundStyle(Color(red: 0.20, green: 0.18, blue: 0.15).opacity(0.42))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .frame(width: 170, height: 30)
            .background(Color.white.opacity(0.44), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.55), lineWidth: 1)
            }
        } else {
            Button {
                withAnimation(.snappy(duration: 0.16)) {
                    searchExpanded = true
                }
                DispatchQueue.main.async {
                    searchFocused = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(CopythatFont.font(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.17, green: 0.15, blue: 0.12))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Search")
        }
    }

    private var pinboardStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(availablePinboards, id: \.id) { board in
                    pinboardButton(for: board)
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }

    private func pinboardButton(for board: Pinboard) -> some View {
        let isSelected = store.selectedBoardID == board.id

        return Button {
            store.selectedBoardID = board.id
        } label: {
            HStack(spacing: 6) {
                if board.kind == .all {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(CopythatFont.font(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.22, green: 0.20, blue: 0.17).opacity(0.72))
                } else {
                    Circle()
                        .fill(pinboardDotColor(for: board))
                        .frame(width: 10, height: 10)
                        .overlay(alignment: .trailing) {
                            if board.kind == .custom, board.title.localizedCaseInsensitiveContains("email") {
                                Circle()
                                    .fill(Color(red: 0.14, green: 0.72, blue: 0.34))
                                    .frame(width: 10, height: 10)
                                    .offset(x: 7)
                            }
                        }
                }

                Text(displayTitle(for: board))
                    .font(CopythatFont.font(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.16, blue: 0.13))
                    .lineLimit(1)
            }
            .padding(.horizontal, board.kind == .all ? 11 : 0)
            .frame(height: 28)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color(red: 0.18, green: 0.16, blue: 0.13).opacity(0.12))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } label: {
            Image(systemName: "plus")
                .font(CopythatFont.font(size: 16, weight: .medium))
                .foregroundStyle(Color(red: 0.17, green: 0.15, blue: 0.12))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .help("Open Settings")
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 28) {
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
                            .zIndex(item.id == store.selectedItem?.id ? 1 : 0)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 8)
                .frame(height: 258)
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
                Label("Return paste  -  Esc close  -  \(settings.shortcut) show", systemImage: "keyboard")
                    .foregroundStyle(Color(red: 0.25, green: 0.20, blue: 0.16).opacity(0.58))
            }
            Spacer()
            Text("\(store.filteredItems.count) items")
                .foregroundStyle(Color(red: 0.25, green: 0.20, blue: 0.16).opacity(0.52))
        }
        .font(CopythatFont.font(size: 10, weight: .medium))
        .lineLimit(1)
    }

    private var availablePinboards: [Pinboard] {
        [Pinboard.all, Pinboard.pinned] + settings.customPinboards.map { Pinboard.custom($0) }
    }

    private func displayTitle(for board: Pinboard) -> String {
        board.kind == .all ? "Clipboard" : board.title
    }

    private func pinboardDotColor(for board: Pinboard) -> Color {
        switch board.kind {
        case .all:
            return Color(red: 0.32, green: 0.29, blue: 0.24)
        case .pinned:
            return Color(red: 1.0, green: 0.24, blue: 0.22)
        case .custom:
            let palette = [
                Color(red: 0.96, green: 0.70, blue: 0.02),
                Color(red: 0.10, green: 0.70, blue: 0.34),
                Color(red: 0.06, green: 0.52, blue: 0.93),
                Color(red: 0.96, green: 0.32, blue: 0.52)
            ]
            let index = settings.customPinboards.firstIndex(of: board.customName ?? "") ?? 0
            return palette[index % palette.count]
        case .unknown:
            return Color(red: 0.32, green: 0.29, blue: 0.24)
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}
