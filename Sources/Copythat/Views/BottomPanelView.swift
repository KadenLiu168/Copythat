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
        GeometryReader { proxy in
            let searchWidth: CGFloat = searchExpanded || !store.searchText.isEmpty ? 188 : 32
            let leftSpacing: CGFloat = 8
            let sideReserve = max(160, searchWidth + 128)
            let maxCenterWidth = max(80, proxy.size.width - sideReserve * 2)

            ZStack {
                HStack(spacing: leftSpacing) {
                    searchControl
                        .frame(width: searchWidth, alignment: .leading)
                    pinboardButton(for: .all)
                        .frame(height: 32)
                    Spacer(minLength: 0)
                    addButton
                        .frame(width: 32, height: 32)
                }

                centerPinboardStrip(maxWidth: maxCenterWidth)
                    .frame(maxWidth: maxCenterWidth)
            }
        }
        .frame(height: 36)
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
            .frame(height: 32)
            .background(Color.white.opacity(searchFocused ? 0.52 : 0.36), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(searchFocused ? Color(red: 0.22, green: 0.19, blue: 0.15).opacity(0.24) : .white.opacity(0.48), lineWidth: 1)
            }
            .shadow(color: Color(red: 0.44, green: 0.25, blue: 0.12).opacity(searchFocused ? 0.12 : 0.06), radius: searchFocused ? 8 : 4, y: 2)
            .animation(.snappy(duration: 0.16), value: searchFocused)
        } else {
            CommandBarIconButton(systemName: "magnifyingglass", fontSize: 15, helpText: "Search") {
                withAnimation(.snappy(duration: 0.16)) {
                    searchExpanded = true
                }
                DispatchQueue.main.async {
                    searchFocused = true
                }
            }
        }
    }

    private func centerPinboardStrip(maxWidth: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            pinboardContent(for: centerPinboards, spacing: 12)

            ScrollView(.horizontal, showsIndicators: false) {
                pinboardContent(for: centerPinboards, spacing: 12)
            }
            .frame(width: maxWidth)
            .scrollClipDisabled()
        }
    }

    private func pinboardContent(for boards: [Pinboard], spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(boards, id: \.id) { board in
                pinboardButton(for: board)
            }
        }
        .frame(height: 32)
    }

    private func pinboardButton(for board: Pinboard) -> some View {
        let isSelected = store.selectedBoardID == board.id

        return PinboardFilterButton(
            board: board,
            title: displayTitle(for: board),
            dotColor: pinboardDotColor(for: board),
            isSelected: isSelected
        ) {
            store.selectedBoardID = board.id
        }
    }

    private var addButton: some View {
        CommandBarIconButton(systemName: "plus", fontSize: 16, helpText: "Open Settings") {
            (NSApp.delegate as? AppDelegate)?.openSettings(nil)
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if store.filteredItems.isEmpty {
            emptyTimeline
        } else {
            cardTimeline
        }
    }

    private var emptyTimeline: some View {
        let copy = emptyTimelineCopy

        return EmptyTimelineView(title: copy.title, description: copy.description)
            .frame(maxWidth: .infinity)
            .frame(height: 258)
            .frame(maxHeight: .infinity, alignment: .center)
    }

    private var cardTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 28) {
                    ForEach(store.filteredItems) { item in
                        timelineCard(for: item, selectedID: store.selectedID)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 16)
                .frame(height: 258)
            }
            .scrollClipDisabled()
            .frame(maxHeight: .infinity, alignment: .center)
            .onChange(of: store.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.snappy(duration: 0.18)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var emptyTimelineCopy: (title: String, description: String) {
        let query = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return ("No matching clips", "Try another search or clear the query.")
        }

        let board = Pinboard(id: store.selectedBoardID)
        switch board.kind {
        case .all, .unknown:
            return ("Copy something to start", "Text, links, images, and file paths will appear here.")
        case .pinned:
            return ("No pinned clips", "Pin copied items to keep them close.")
        case .custom:
            let title = board.title.isEmpty ? "this pinboard" : board.title
            return ("No clips in \(title)", "Move copied items here from a card menu.")
        }
    }

    private func timelineCard(for item: ClipboardItem, selectedID: UUID?) -> some View {
        let isSelected = item.id == selectedID

        return ClipboardCardView(
            item: item,
            pinboards: settings.customPinboards,
            isSelected: isSelected,
            onSelect: { store.select(item) },
            onPaste: onPaste,
            onTogglePin: { store.togglePin(item) },
            onMoveToPinboard: { name in store.move(item, toPinboard: name) },
            onDelete: { store.remove(item) }
        )
        .equatable()
        .id(item.id)
        .zIndex(isSelected ? 1 : 0)
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

    private var centerPinboards: [Pinboard] {
        [Pinboard.pinned] + settings.customPinboards.map { Pinboard.custom($0) }
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

private struct CommandBarIconButton: View {
    let systemName: String
    let fontSize: CGFloat
    let helpText: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(CopythatFont.font(size: fontSize, weight: .medium))
                .foregroundStyle(Color(red: 0.17, green: 0.15, blue: 0.12))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(CommandBarIconButtonStyle(isHovered: isHovered))
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .help(helpText)
    }
}

private struct CommandBarIconButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(backgroundOpacity(isPressed: configuration.isPressed)))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(.white.opacity(isHovered ? 0.48 : 0.28), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .shadow(
                color: Color(red: 0.44, green: 0.25, blue: 0.12).opacity(isHovered ? 0.10 : 0.04),
                radius: isHovered ? 7 : 4,
                y: 2
            )
    }

    private func backgroundOpacity(isPressed: Bool) -> Double {
        if isPressed {
            return 0.50
        }
        return isHovered ? 0.38 : 0.22
    }
}

private struct PinboardFilterButton: View {
    let board: Pinboard
    let title: String
    let dotColor: Color
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                marker

                Text(title)
                    .font(CopythatFont.font(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Color(red: 0.18, green: 0.16, blue: 0.13).opacity(isSelected ? 0.96 : 0.82))
                    .lineLimit(1)
            }
            .padding(.horizontal, board.kind == .all ? 10 : 9)
            .frame(height: 26)
        }
        .buttonStyle(PinboardFilterButtonStyle(isSelected: isSelected, isHovered: isHovered))
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var marker: some View {
        if board.kind == .all {
            Image(systemName: "clock.arrow.circlepath")
                .font(CopythatFont.font(size: 11.5, weight: .semibold))
                .foregroundStyle(Color(red: 0.22, green: 0.20, blue: 0.17).opacity(isSelected ? 0.70 : 0.56))
        } else {
            Capsule(style: .continuous)
                .fill(dotColor.opacity(isSelected ? 0.95 : 0.72))
                .frame(width: 11, height: 4.5)
                .overlay(alignment: .top) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(isSelected ? 0.34 : 0.22))
                        .frame(height: 1)
                }
        }
    }
}

private struct PinboardFilterButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color(red: 0.18, green: 0.16, blue: 0.13).opacity(0.13)
        }
        if isSelected {
            return Color.white.opacity(0.36)
        }
        return Color.white.opacity(isHovered ? 0.20 : 0.0)
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isSelected {
            return Color(red: 0.18, green: 0.16, blue: 0.13).opacity(0.13)
        }
        return .white.opacity(isHovered || isPressed ? 0.28 : 0.0)
    }
}
