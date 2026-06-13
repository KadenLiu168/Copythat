import AppKit
import SwiftUI

private enum CommandBarMetrics {
    static let hitSize: CGFloat = 32
    static let visibleHeight: CGFloat = 26
    static let cornerRadius: CGFloat = 10
    static let compactSearchWidth: CGFloat = 32
    static let expandedSearchWidth: CGFloat = 188
    static let searchMotion = Animation.smooth(duration: 0.22)
}

struct BottomPanelView: View {
    private let panelCornerRadius: CGFloat = 26
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var store: ClipboardStore
    @State private var searchExpanded = false
    @State private var searchContentVisible = false
    @State private var searchHovered = false
    @State private var hidesPreviews = false
    @State private var isCreatingPinboard = false
    @State private var pinboardDeletionRequest: PinboardDeletionRequest?
    @FocusState private var searchFocused: Bool
    let onClose: () -> Void
    let onPaste: () -> Void

    init(model: AppModel, onClose: @escaping () -> Void, onPaste: @escaping () -> Void) {
        _settings = ObservedObject(wrappedValue: model.settings)
        _store = ObservedObject(wrappedValue: model.store)
        self.onClose = onClose
        self.onPaste = onPaste
    }

    var body: some View {
        panelContainer
            .onAppear {
                searchExpanded = !store.searchText.isEmpty
                searchContentVisible = !store.searchText.isEmpty
                searchFocused = !store.searchText.isEmpty
                store.selectFirstVisibleItem()
            }
            .onChange(of: store.searchText) {
                if !store.searchText.isEmpty {
                    searchContentVisible = true
                } else if !searchExpanded {
                    searchContentVisible = false
                }
                store.selectFirstVisibleItem()
            }
            .onChange(of: searchFocused) { _, isFocused in
                guard !isFocused, store.searchText.isEmpty else { return }
                collapseEmptySearch()
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
            .onExitCommand {
                if isCreatingPinboard {
                    isCreatingPinboard = false
                } else {
                    onClose()
                }
            }
            .alert(
                "Delete \"\(pinboardDeletionRequest?.name ?? "")\"?",
                isPresented: Binding(
                    get: { pinboardDeletionRequest != nil },
                    set: { isPresented in
                        if !isPresented {
                            pinboardDeletionRequest = nil
                        }
                    }
                ),
                presenting: pinboardDeletionRequest
            ) { request in
                Button("Delete", role: .destructive) {
                    confirmPinboardDeletion(request)
                }
                Button("Cancel", role: .cancel) {}
            } message: { request in
                Text(pinboardDeletionMessage(for: request))
            }
    }

    private var panelContainer: some View {
        let panelShape = RoundedRectangle(cornerRadius: CopythatTokens.Panel.cornerRadius, style: .continuous)

        return ZStack {
            VisualEffectView(
                material: .popover,
                blendingMode: .behindWindow,
                cornerRadius: CopythatTokens.Panel.cornerRadius
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
        .clipShape(panelShape)
        .contentShape(panelShape)
        .overlay {
            panelShape
                .inset(by: CopythatTokens.Panel.strokeInset)
                .stroke(.white.opacity(CopythatTokens.Panel.strokeOpacity), lineWidth: CopythatTokens.Panel.strokeWidth)
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
            let groupSpacing: CGFloat = 16
            let searchExpansionReserve = CommandBarMetrics.expandedSearchWidth - CommandBarMetrics.compactSearchWidth
            let maxPinboardWidth = max(
                80,
                proxy.size.width - CommandBarMetrics.compactSearchWidth - CommandBarMetrics.hitSize * 2 - groupSpacing * 3 - searchExpansionReserve * 2
            )

            ViewThatFits(in: .horizontal) {
                commandBarGroup(spacing: groupSpacing) {
                    pinboardContent(for: headerPinboards, spacing: 8)
                }

                commandBarGroup(spacing: groupSpacing) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        pinboardContent(for: headerPinboards, spacing: 8)
                    }
                    .frame(width: maxPinboardWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: 36)
    }

    private var searchControl: some View {
        let isExpanded = isSearchPresented
        let contentVisible = searchContentVisible || !store.searchText.isEmpty
        let searchWidth = isExpanded ? CommandBarMetrics.expandedSearchWidth : CommandBarMetrics.compactSearchWidth

        return HStack(spacing: isExpanded ? 8 : 0) {
            Image(systemName: "magnifyingglass")
                .font(CopythatFont.font(size: isExpanded ? 13 : 15, weight: .medium))
                .foregroundStyle(Color(red: 0.20, green: 0.18, blue: 0.15).opacity(0.76))
                .frame(width: CommandBarMetrics.compactSearchWidth, height: CommandBarMetrics.visibleHeight)

            if isExpanded {
                searchFieldContent(contentVisible: contentVisible)
            }
        }
        .padding(.trailing, isExpanded ? 11 : 0)
        .frame(width: searchWidth, height: CommandBarMetrics.visibleHeight)
        .background(
            Color.white.opacity(searchBackgroundOpacity),
            in: RoundedRectangle(cornerRadius: CommandBarMetrics.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CommandBarMetrics.cornerRadius, style: .continuous)
                .stroke(searchBorderColor, lineWidth: 1)
        }
        .shadow(
            color: Color(red: 0.44, green: 0.25, blue: 0.12).opacity(searchFocused ? 0.12 : 0.06),
            radius: searchFocused ? 8 : 4,
            y: 2
        )
        .frame(height: CommandBarMetrics.hitSize)
        .contentShape(Rectangle())
        .onTapGesture(perform: expandSearch)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.14)) {
                searchHovered = hovering
            }
        }
        .help("Search")
        .animation(CommandBarMetrics.searchMotion, value: isExpanded)
        .animation(.smooth(duration: 0.12).delay(contentVisible ? 0.06 : 0), value: contentVisible)
    }

    private func searchFieldContent(contentVisible: Bool) -> some View {
        HStack(spacing: 8) {
            TextField("Search", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(CopythatFont.font(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.12))
                .focused($searchFocused)
                .onSubmit(onPaste)
                .opacity(contentVisible ? 1 : 0)

            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(CopythatFont.font(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.20, green: 0.18, blue: 0.15).opacity(0.42))
                }
                .buttonStyle(.plain)
                .opacity(contentVisible ? 1 : 0)
            }
        }
    }

    private var searchBackgroundOpacity: Double {
        if searchFocused {
            return 0.52
        }
        if searchHovered {
            return 0.38
        }
        return isSearchPresented ? 0.36 : 0.22
    }

    private var searchBorderColor: Color {
        if searchFocused {
            return Color(red: 0.22, green: 0.19, blue: 0.15).opacity(0.24)
        }
        return .white.opacity(searchHovered ? 0.48 : 0.28)
    }

    private var isSearchPresented: Bool {
        searchExpanded || !store.searchText.isEmpty
    }

    private func expandSearch() {
        guard !isSearchPresented else { return }
        withAnimation(CommandBarMetrics.searchMotion) {
            searchExpanded = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.055) {
            guard isSearchPresented else { return }
            withAnimation(.smooth(duration: 0.12)) {
                searchContentVisible = true
            }
        }
        DispatchQueue.main.async {
            searchFocused = true
        }
    }

    private func collapseEmptySearch() {
        guard store.searchText.isEmpty else { return }
        withAnimation(.smooth(duration: 0.10)) {
            searchContentVisible = false
        }
        withAnimation(CommandBarMetrics.searchMotion) {
            searchExpanded = false
        }
    }

    private func commandBarGroup<PinboardStrip: View>(
        spacing: CGFloat,
        @ViewBuilder pinboardStrip: () -> PinboardStrip
    ) -> some View {
        HStack(spacing: spacing) {
            searchControl
                .frame(width: CommandBarMetrics.compactSearchWidth, height: CommandBarMetrics.hitSize, alignment: .trailing)
                .zIndex(1)
            pinboardStrip()
            privacyButton
                .frame(width: CommandBarMetrics.hitSize, height: CommandBarMetrics.hitSize)
            addButton
                .frame(width: CommandBarMetrics.hitSize, height: CommandBarMetrics.hitSize)
        }
    }

    private func pinboardContent(for boards: [Pinboard], spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(boards, id: \.id) { board in
                pinboardButton(for: board)
            }
        }
        .frame(height: CommandBarMetrics.hitSize)
    }

    private func pinboardButton(for board: Pinboard) -> some View {
        let isSelected = store.selectedBoardID == board.id

        return PinboardFilterButton(
            board: board,
            title: displayTitle(for: board),
            dotColor: pinboardDotColor(for: board),
            isSelected: isSelected,
            onDelete: board.kind == .custom ? { requestPinboardDeletion(for: board) } : nil
        ) {
            dismissEmptySearch()
            store.selectedBoardID = board.id
        }
    }

    private var addButton: some View {
        CommandBarIconButton(systemName: "plus", fontSize: 16, helpText: "New Pinboard") {
            dismissEmptySearch()
            isCreatingPinboard = true
        }
        .popover(isPresented: $isCreatingPinboard, arrowEdge: .top) {
            NewPinboardPopover(
                settings: settings,
                onCancel: { isCreatingPinboard = false },
                onCreate: { pinboard in
                    isCreatingPinboard = false
                    store.selectedBoardID = Pinboard.custom(pinboard.name).id
                }
            )
        }
    }

    private var privacyButton: some View {
        CommandBarIconButton(
            systemName: hidesPreviews ? "eye.slash" : "eye",
            fontSize: 15,
            helpText: hidesPreviews ? "Show Previews" : "Hide Previews"
        ) {
            dismissEmptySearch()
            hidesPreviews.toggle()
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
                proxy.scrollTo(id, anchor: .center)
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
            hidesPreview: hidesPreviews,
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

    private var headerPinboards: [Pinboard] {
        [Pinboard.all, Pinboard.pinned] + settings.customPinboards.map { Pinboard.custom($0.name) }
    }

    private func displayTitle(for board: Pinboard) -> String {
        board.kind == .all ? "Clipboard" : board.title
    }

    private func pinboardDotColor(for board: Pinboard) -> Color {
        switch board.kind {
        case .all:
            return Color(red: 0.32, green: 0.29, blue: 0.24)
        case .pinned:
            return Color(nsColor: .systemRed)
        case .custom:
            let pinboard = settings.customPinboards.first { $0.name == board.customName }
            return Color(nsColor: pinboard?.color.color ?? PinboardColorToken.amber.color)
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

    private func dismissEmptySearch() {
        guard store.searchText.isEmpty else {
            searchFocused = false
            return
        }
        searchFocused = false
        collapseEmptySearch()
    }

    private func requestPinboardDeletion(for board: Pinboard) {
        guard let name = board.customName else { return }
        pinboardDeletionRequest = PinboardDeletionRequest(
            name: name,
            affectedClipCount: store.pinboardAssignmentCount(named: name)
        )
    }

    private func confirmPinboardDeletion(_ request: PinboardDeletionRequest) {
        guard settings.deleteCustomPinboard(named: request.name) else { return }
        store.clearPinboardAssignments(named: request.name)
        store.selectClipboardIfViewingPinboard(named: request.name)
        pinboardDeletionRequest = nil
    }

    private func pinboardDeletionMessage(for request: PinboardDeletionRequest) -> String {
        let clipLabel = request.affectedClipCount == 1 ? "clip" : "clips"
        return "\(request.affectedClipCount) \(clipLabel) will be moved out of this pinboard."
    }
}

private struct PinboardDeletionRequest: Identifiable {
    let name: String
    let affectedClipCount: Int

    var id: String { name }
}

private struct NewPinboardPopover: View {
    @ObservedObject var settings: AppSettings
    let onCancel: () -> Void
    let onCreate: (CustomPinboard) -> Void
    @State private var name = ""
    @State private var selectedColor = PinboardColorToken.amber
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Pinboard")
                .font(CopythatFont.font(size: 15, weight: .semibold))

            TextField("Pinboard name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(create)

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(CopythatFont.font(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(PinboardColorToken.allCases) { color in
                        Button {
                            selectedColor = color
                        } label: {
                            Circle()
                                .fill(Color(nsColor: color.color))
                                .frame(width: 20, height: 20)
                                .padding(3)
                                .overlay {
                                    Circle()
                                        .stroke(.primary.opacity(selectedColor == color ? 0.62 : 0), lineWidth: 1.5)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(color.rawValue.capitalized)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!settings.canCreateCustomPinboard(named: name))
            }
        }
        .padding(16)
        .frame(width: 250)
        .onAppear {
            DispatchQueue.main.async {
                nameFocused = true
            }
        }
        .onExitCommand(perform: onCancel)
    }

    private func create() {
        guard let pinboard = settings.createCustomPinboard(name: name, color: selectedColor) else { return }
        onCreate(pinboard)
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
                .frame(width: CommandBarMetrics.hitSize, height: CommandBarMetrics.hitSize)
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
                RoundedRectangle(cornerRadius: CommandBarMetrics.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(backgroundOpacity(isPressed: configuration.isPressed)))
                    .frame(width: CommandBarMetrics.hitSize, height: CommandBarMetrics.visibleHeight)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CommandBarMetrics.cornerRadius, style: .continuous)
                    .stroke(.white.opacity(isHovered ? 0.48 : 0.28), lineWidth: 1)
                    .frame(width: CommandBarMetrics.hitSize, height: CommandBarMetrics.visibleHeight)
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
    let onDelete: (() -> Void)?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        if let onDelete {
            button
                .contextMenu {
                    Button("Delete Pinboard...", role: .destructive, action: onDelete)
                }
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 6) {
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
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
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
