//
//  UIList.swift
//
//
//  Created by Alisa Mylnikova on 24.02.2023.
//

import SwiftUI

public extension Notification.Name {
    static let onScrollToBottom = Notification.Name("onScrollToBottom")
    static let onScrollToMessage = Notification.Name("onScrollToMessage")
}

private let scrollBottomTolerance = CGFloat(25)

@MainActor
struct UIList<MessageContent: View, InputView: View>: UIViewRepresentable {

    typealias MessageBuilderClosure = ChatView<MessageContent, InputView, DefaultMessageMenuAction>.MessageBuilderClosure

    @Environment(\.chatTheme) var theme

    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var inputViewModel: InputViewModel

    @Binding var isScrolledToBottom: Bool
    @Binding var shouldScrollToTop: () -> ()
    @Binding var tableContentHeight: CGFloat

    var messageBuilder: MessageBuilderClosure?
    var mainHeaderBuilder: (()->AnyView)?
    var headerBuilder: ((Date)->AnyView)?
    var inputView: InputView

    let type: ChatType
    let showDateHeaders: Bool
    let isScrollEnabled: Bool
    let avatarSize: CGFloat
    let showMessageMenuOnLongPress: Bool
    let tapAvatarClosure: ChatView.TapAvatarClosure?
    let paginationHandler: PaginationHandler?
    let messageStyler: (String) -> AttributedString
    let shouldShowLinkPreview: (URL) -> Bool
    let showMessageTimeView: Bool
    let messageLinkPreviewLimit: Int
    let messageFont: UIFont
    let sections: [MessagesSection]
    let ids: [String]
    let listSwipeActions: ListSwipeActions
    let keyboardDismissMode: UIScrollView.KeyboardDismissMode


    @State var isScrolledToTop = false
    @State var updateQueue = UpdateQueue()

    func makeUIView(context: Context) -> UITableView {
        let tableView = WidthTrackingTableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.transform = CGAffineTransform(rotationAngle: (type == .conversation ? .pi : 0))

        tableView.showsVerticalScrollIndicator = false
        tableView.estimatedRowHeight = 60
        tableView.estimatedSectionHeaderHeight = 1
        tableView.estimatedSectionFooterHeight = 40
        tableView.backgroundColor = UIColor(theme.colors.mainBG)
        tableView.scrollsToTop = false
        tableView.isScrollEnabled = isScrollEnabled
        tableView.keyboardDismissMode = keyboardDismissMode

        // Store observer token in coordinator for proper cleanup
        context.coordinator.scrollToBottomObserver = MainActorNotificationObserver(
            name: .onScrollToBottom
        ) { [weak tableView, weak coordinator = context.coordinator] in
            guard let tableView = tableView, let coordinator = coordinator else { return }
            if !coordinator.sections.isEmpty {
                guard tableView.numberOfSections > 0, tableView.numberOfRows(inSection: 0) > 0 else { return }
                // The table is inverted (rotated π): the newest message (row 0) sits at
                // logical y = 0. Use `.top` so the cell's logical top — which is the visual
                // bottom / end of the list — aligns with the viewport. Using `.bottom` here
                // would align the cell's logical bottom (the visual TOP of a tall message)
                // with the viewport bottom, scrolling to the top of messages taller than
                // the screen instead of the actual end of the list.
                tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
            }
        }

        // Scroll-to-message observer for search navigation
        context.coordinator.scrollToMessageObserver = MainActorNotificationObserver(
            name: .onScrollToMessage,
            value: { $0.userInfo?["messageId"] as? String }
        ) { [weak tableView, weak coordinator = context.coordinator] messageId in
            guard let tableView = tableView, let coordinator = coordinator else { return }
            guard let messageId else { return }

            // Find the IndexPath for this message ID
            for (sectionIndex, section) in coordinator.sections.enumerated() {
                for (rowIndex, _) in section.rows.enumerated() {
                    if section.rows[rowIndex].id == messageId {
                        let indexPath = IndexPath(row: rowIndex, section: sectionIndex)

                        // Validate the index path is within table bounds
                        guard sectionIndex < tableView.numberOfSections,
                              rowIndex < tableView.numberOfRows(inSection: sectionIndex) else { return }

                        tableView.scrollToRow(at: indexPath, at: .middle, animated: true)

                        // Pick the highlight color to match the bubble background
                        // Brief highlight animation after scroll completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            guard let cell = tableView.cellForRow(at: indexPath) else { return }
                            // The table has a π rotation so local +y is visually upward.
                            // Move origin 1px in local -y (visually down) and trim 3px from height
                            // so the overlay sits at the visual bottom of the bubble.
                            var highlightFrame = cell.bounds
                            highlightFrame.origin.y -= 2
                            highlightFrame.size.height -= 1
                            let highlightView = UIView(frame: highlightFrame)
                            highlightView.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.0)
                            highlightView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                            highlightView.isUserInteractionEnabled = false
                            cell.addSubview(highlightView)

                            UIView.animate(withDuration: 0.3, animations: {
                                highlightView.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.25)
                            }) { _ in
                                UIView.animate(withDuration: 0.5, delay: 0.5, options: [], animations: {
                                    highlightView.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.0)
                                }) { _ in
                                    highlightView.removeFromSuperview()
                                }
                            }
                        }
                        return
                    }
                }
            }
        }

        DispatchQueue.main.async {
            shouldScrollToTop = {
                tableView.contentOffset = CGPoint(x: 0, y: tableView.contentSize.height - tableView.frame.height)
            }
        }

        return tableView
    }

    func updateUIView(_ tableView: UITableView, context: Context) {
        if !isScrollEnabled {
            DispatchQueue.main.async {
                tableContentHeight = tableView.contentSize.height
            }
        }

        if context.coordinator.sections == sections {
            return
        }

        ChatRedrawDebug.log("UIList.updateUIView: sections differ (old=\(context.coordinator.sections.reduce(0) { $0 + $1.rows.count }) new=\(sections.reduce(0) { $0 + $1.rows.count })) -> scheduling table update")

        Task {
            await updateQueue.enqueue() {
                await updateIfNeeded(coordinator: context.coordinator, tableView: tableView)
            }
        }
    }

    @MainActor
    private func updateIfNeeded(coordinator: Coordinator, tableView: UITableView) async {
        if coordinator.sections == sections {
            return
        }

        // Initial load - just set data without animation
        if coordinator.sections.isEmpty {
            coordinator.sections = sections
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
            if !isScrollEnabled {
                DispatchQueue.main.async {
                    self.tableContentHeight = tableView.contentSize.height
                }
            }
            // On initial load, we're at the bottom (conversation is flipped)
            // Set isScrolledToBottom to true to prevent scroll button from showing
            DispatchQueue.main.async {
                self.isScrolledToBottom = true
            }
            return
        }

        if let lastSection = sections.last {
            coordinator.paginationTargetIndexPath = IndexPath(row: lastSection.rows.count - 1, section: sections.count - 1)
        }

        let prevSections = coordinator.sections
        let splitInfo = await MessageListDiff.splitInBackground(prevSections, sections)
        ChatRedrawDebug.log("UIList.applyUpdates: deletes=\(splitInfo.deleteOperations.count) swaps=\(splitInfo.swapOperations.count) edits=\(splitInfo.editOperations.count) inserts=\(splitInfo.insertOperations.count) — edits/swaps reconfigure existing cells (flash source)")
        await applyUpdatesToTable(tableView, splitInfo: splitInfo) {
            coordinator.sections = $0
        }
    }

    @MainActor
    private func applyUpdatesToTable(_ tableView: UITableView, splitInfo: SplitInfo, updateContextClosure: ([MessagesSection])->()) async {
        // step 0: preparation
        // prepare intermediate sections and operations
        //print("whole appliedDeletes:\n", formatSections(splitInfo.appliedDeletes), "\n")
        //print("whole appliedDeletesSwapsAndEdits:\n", formatSections(splitInfo.appliedDeletesSwapsAndEdits), "\n")
        //print("whole final sections:\n", formatSections(sections), "\n")

        //print("operations delete:\n", splitInfo.deleteOperations.map { $0.description })
        //print("operations swap:\n", splitInfo.swapOperations.map { $0.description })
        //print("operations edit:\n", splitInfo.editOperations.map { $0.description })
        //print("operations insert:\n", splitInfo.insertOperations.map { $0.description })

        await performBatchTableUpdates(tableView) {
            // step 1: deletes
            // delete sections and rows if necessary
            //print("1 apply deletes", runID)
            updateContextClosure(splitInfo.appliedDeletes)
            //context.coordinator.sections = appliedDeletes
            for operation in splitInfo.deleteOperations {
                applyOperation(operation, tableView: tableView)
            }
        }
        //print("1 finished deletes", runID)

        await performBatchTableUpdates(tableView) {
            // step 2: swaps
            // swap places for rows that moved inside the table
            // (example of how this happens. send two messages: first m1, then m2. if m2 is delivered to server faster, then it should jump above m1 even though it was sent later)
            //print("2 apply swaps", runID)
            updateContextClosure(splitInfo.appliedDeletesSwapsAndEdits) // NOTE: this array already contains necessary edits, but won't be a problem for appplying swaps
            for operation in splitInfo.swapOperations {
                applyOperation(operation, tableView: tableView)
            }
        }
        //print("2 finished swaps", runID)

        UIView.setAnimationsEnabled(false)
        await performBatchTableUpdates(tableView) {
            // step 3: edits
            // check only sections that are already in the table for existing rows that changed and apply only them to table's dataSource without animation
            //print("3 apply edits", runID)
            updateContextClosure(splitInfo.appliedDeletesSwapsAndEdits)

            for operation in splitInfo.editOperations {
                applyOperation(operation, tableView: tableView)
            }
        }
        UIView.setAnimationsEnabled(true)
        //print("3 finished edits", runID)

        // step 4: inserts
        // Always apply insert operations so new messages appear immediately
        // (Previously this was gated by isScrolledToBottom || isScrolledToTop which caused
        // outgoing messages to not appear until the user scrolled)
        if !splitInfo.insertOperations.isEmpty {
            //print("4 apply inserts", runID)

            // Capture scroll position before insert - use a larger tolerance to account for
            // content size changes (e.g., when a message is expanded)
            let wasNearBottom = tableView.contentOffset.y <= scrollBottomTolerance * 4

            updateContextClosure(sections)

            if wasNearBottom {
                // New messages near the bottom - insert with animation and auto-scroll
                tableView.beginUpdates()
                for operation in splitInfo.insertOperations {
                    applyOperation(operation, tableView: tableView)
                }
                tableView.endUpdates()

                if !isScrollEnabled {
                    tableContentHeight = tableView.contentSize.height
                }

                // After insert, scroll to bottom to show the new message.
                // The table is inverted (rotated π), so the newest message (row 0) is at
                // logical y = 0; `.top` pins its logical top — the visual bottom / end of
                // the list. `.bottom` would instead align the cell's logical bottom (the
                // visual top of a tall message) with the viewport, scrolling to the top of
                // messages that are taller than the screen.
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                    if tableView.numberOfSections > 0, tableView.numberOfRows(inSection: 0) > 0 {
                        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
                    }
                    self.isScrolledToBottom = true
                }
            } else {
                // Pagination (user scrolled up) - insert without animation.
                // Don't adjust contentOffset; just let UITableView handle it
                // naturally so the visible content stays in place.
                UIView.performWithoutAnimation {
                    tableView.beginUpdates()
                    for operation in splitInfo.insertOperations {
                        applyOperation(operation, tableView: tableView)
                    }
                    tableView.endUpdates()
                    tableView.layoutIfNeeded()
                }

                if !isScrollEnabled {
                    tableContentHeight = tableView.contentSize.height
                }
            }
        }
    }

    // MARK: - Operations

    typealias Operation = MessageListDiff.Operation
    typealias SplitInfo = MessageListDiff.SplitInfo

    func applyOperation(_ operation: Operation, tableView: UITableView) {
        switch operation {
        case .deleteSection(let section):
            tableView.deleteSections([section], with: .fade)
        case .insertSection(let section):
            tableView.insertSections([section], with: .none)

        case .delete(let section, let row):
            tableView.deleteRows(at: [IndexPath(row: row, section: section)], with: .fade)
        case .insert(let section, let row):
            tableView.insertRows(at: [IndexPath(row: row, section: section)], with: .none)
        case .edit(let section, let row):
            tableView.reconfigureRows(at: [IndexPath(row: row, section: section)])
        case .swap(let section, let rowFrom, let rowTo):
            tableView.deleteRows(at: [IndexPath(row: rowFrom, section: section)], with: .none)
            tableView.insertRows(at: [IndexPath(row: rowTo, section: section)], with: .none)
        }
    }

    // MARK: - Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(
            viewModel: viewModel, inputViewModel: inputViewModel,
            isScrolledToBottom: $isScrolledToBottom, isScrolledToTop: $isScrolledToTop,
            messageBuilder: messageBuilder, mainHeaderBuilder: mainHeaderBuilder,
            headerBuilder: headerBuilder, type: type, showDateHeaders: showDateHeaders,
            avatarSize: avatarSize, showMessageMenuOnLongPress: showMessageMenuOnLongPress,
            tapAvatarClosure: tapAvatarClosure, paginationHandler: paginationHandler,
            messageStyler: messageStyler, shouldShowLinkPreview: shouldShowLinkPreview,
            showMessageTimeView: showMessageTimeView,
            messageLinkPreviewLimit: messageLinkPreviewLimit, messageFont: messageFont,
            sections: sections, ids: ids, mainBackgroundColor: theme.colors.mainBG,
            listSwipeActions: listSwipeActions,
            keyboardDismissMode: keyboardDismissMode)
    }

    class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {

        @ObservedObject var viewModel: ChatViewModel
        @ObservedObject var inputViewModel: InputViewModel

        @Binding var isScrolledToBottom: Bool
        @Binding var isScrolledToTop: Bool

        let messageBuilder: MessageBuilderClosure?
        let mainHeaderBuilder: (()->AnyView)?
        let headerBuilder: ((Date)->AnyView)?

        let type: ChatType
        let showDateHeaders: Bool
        let avatarSize: CGFloat
        let showMessageMenuOnLongPress: Bool
        let tapAvatarClosure: ChatView.TapAvatarClosure?
        let paginationHandler: PaginationHandler?
        let messageStyler: (String) -> AttributedString
        let shouldShowLinkPreview: (URL) -> Bool
        let showMessageTimeView: Bool
        let messageLinkPreviewLimit: Int
        let messageFont: UIFont
        var sections: [MessagesSection] {
            didSet {
                if let lastSection = sections.last {
                    paginationTargetIndexPath = IndexPath(row: lastSection.rows.count - 1, section: sections.count - 1)
                }
            }
        }
        let ids: [String]
        let mainBackgroundColor: Color
        let listSwipeActions: ListSwipeActions
        let keyboardDismissMode: UIScrollView.KeyboardDismissMode

        private let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)

        init(
            viewModel: ChatViewModel, inputViewModel: InputViewModel,
            isScrolledToBottom: Binding<Bool>, isScrolledToTop: Binding<Bool>,
            messageBuilder: MessageBuilderClosure?, mainHeaderBuilder: (() -> AnyView)?,
            headerBuilder: ((Date) -> AnyView)?, type: ChatType, showDateHeaders: Bool,
            avatarSize: CGFloat, showMessageMenuOnLongPress: Bool,
            tapAvatarClosure: ChatView.TapAvatarClosure?, paginationHandler: PaginationHandler?,
            messageStyler: @escaping (String) -> AttributedString,
            shouldShowLinkPreview: @escaping (URL) -> Bool, showMessageTimeView: Bool,
            messageLinkPreviewLimit: Int, messageFont: UIFont, sections: [MessagesSection],
            ids: [String], mainBackgroundColor: Color, paginationTargetIndexPath: IndexPath? = nil,
            listSwipeActions: ListSwipeActions, keyboardDismissMode: UIScrollView.KeyboardDismissMode
        ) {
            self.viewModel = viewModel
            self.inputViewModel = inputViewModel
            self._isScrolledToBottom = isScrolledToBottom
            self._isScrolledToTop = isScrolledToTop
            self.messageBuilder = messageBuilder
            self.mainHeaderBuilder = mainHeaderBuilder
            self.headerBuilder = headerBuilder
            self.type = type
            self.showDateHeaders = showDateHeaders
            self.avatarSize = avatarSize
            self.showMessageMenuOnLongPress = showMessageMenuOnLongPress
            self.tapAvatarClosure = tapAvatarClosure
            self.paginationHandler = paginationHandler
            self.messageStyler = messageStyler
            self.shouldShowLinkPreview = shouldShowLinkPreview
            self.showMessageTimeView = showMessageTimeView
            self.messageLinkPreviewLimit = messageLinkPreviewLimit
            self.messageFont = messageFont
            self.sections = sections
            self.ids = ids
            self.mainBackgroundColor = mainBackgroundColor
            self.listSwipeActions = listSwipeActions
            self.keyboardDismissMode = keyboardDismissMode

            // didSet does not fire during init, so compute the pagination target
            // manually when sections are already populated at creation time.
            if let lastSection = sections.last {
                self.paginationTargetIndexPath = IndexPath(row: lastSection.rows.count - 1, section: sections.count - 1)
            } else {
                self.paginationTargetIndexPath = paginationTargetIndexPath
            }
        }

        // Releasing these owners unregisters the observers without accessing
        // non-Sendable Objective-C tokens from the coordinator's deinit.
        var scrollToBottomObserver: MainActorNotificationObserver?
        var scrollToMessageObserver: MainActorNotificationObserver?

        /// call pagination handler when this row is reached
        /// without this there is a bug: during new cells insertion willDisplay is called one extra time for the cell which used to be the last one while it is being updated (its position in group is changed from first to middle)
        var paginationTargetIndexPath: IndexPath?

        func numberOfSections(in tableView: UITableView) -> Int {
            sections.count
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            sections[section].rows.count
        }

        func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            if type == .comments {
                return sectionHeaderView(section)
            }
            return nil
        }

        func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
            if type == .conversation {
                return sectionHeaderView(section)
            }
            return nil
        }

        func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            if !showDateHeaders && (section != 0 || mainHeaderBuilder == nil) {
                return 0.1
            }
            return type == .conversation ? 0.1 : UITableView.automaticDimension
        }

        func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
            if !showDateHeaders && (section != 0 || mainHeaderBuilder == nil) {
                return 0.1
            }
            return type == .conversation ? UITableView.automaticDimension : 0.1
        }

        func sectionHeaderView(_ section: Int) -> UIView? {
            if !showDateHeaders && (section != 0 || mainHeaderBuilder == nil) {
                return nil
            }

            let header = UIHostingController(rootView:
                sectionHeaderViewBuilder(section)
                    .rotationEffect(Angle(degrees: (type == .conversation ? 180 : 0)))
            ).view
            header?.backgroundColor = UIColor(mainBackgroundColor)
            return header
        }

        func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard let items = type == .conversation ? listSwipeActions.trailing : listSwipeActions.leading else { return nil }
            guard !items.actions.isEmpty else { return nil }
            let message = sections[indexPath.section].rows[indexPath.row].message
            let conf = UISwipeActionsConfiguration(actions: items.actions.filter({ $0.activeFor(message) }).map { toContextualAction($0, message: message) })
            conf.performsFirstActionWithFullSwipe = items.performsFirstActionWithFullSwipe
            return conf
        }

        func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard let items = type == .conversation ? listSwipeActions.leading : listSwipeActions.trailing else { return nil }
            guard !items.actions.isEmpty else { return nil }
            let message = sections[indexPath.section].rows[indexPath.row].message
            let conf = UISwipeActionsConfiguration(actions: items.actions.filter({ $0.activeFor(message) }).map { toContextualAction($0, message: message) })
            conf.performsFirstActionWithFullSwipe = items.performsFirstActionWithFullSwipe
            return conf
        }

        private func toContextualAction(_ item: SwipeActionable, message:Message) -> UIContextualAction {
            let ca = UIContextualAction(style: .normal, title: nil) { (action, sourceView, completionHandler) in
                item.action(message, self.viewModel.messageMenuAction())
                completionHandler(true)
            }
            ca.image = item.render(type: type)

            let bgColor = item.background ?? mainBackgroundColor
            ca.backgroundColor = UIColor(bgColor)

            return ca
        }

        @ViewBuilder
        func sectionHeaderViewBuilder(_ section: Int) -> some View {
            if let mainHeaderBuilder, section == 0 {
                VStack(spacing: 0) {
                    mainHeaderBuilder()
                    dateViewBuilder(section)
                }
            } else {
                dateViewBuilder(section)
            }
        }

        @ViewBuilder
        func dateViewBuilder(_ section: Int) -> some View {
            if showDateHeaders {
                if let headerBuilder {
                    headerBuilder(sections[section].date)
                } else {
                    Text(sections[section].formattedDate)
                        .font(.system(size: 11))
                        .padding(.top, 30)
                        .padding(.bottom, 8)
                        .foregroundColor(.gray)
                }
            }
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

            let tableViewCell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            tableViewCell.selectionStyle = .none
            tableViewCell.backgroundColor = UIColor(mainBackgroundColor)

            let row = sections[indexPath.section].rows[indexPath.row]
            tableViewCell.contentConfiguration = UIHostingConfiguration {
                ChatMessageView(
                    viewModel: viewModel, messageBuilder: messageBuilder, row: row, chatType: type,
                    avatarSize: avatarSize, tapAvatarClosure: tapAvatarClosure,
                    messageStyler: messageStyler, shouldShowLinkPreview: shouldShowLinkPreview,
                    isDisplayingMessageMenu: false, showMessageTimeView: showMessageTimeView,
                    messageLinkPreviewLimit: messageLinkPreviewLimit, messageFont: messageFont
                )
                .transition(.scale)
                .background(MessageMenuPreferenceViewSetter(id: row.id))
                .rotationEffect(Angle(degrees: (type == .conversation ? 180 : 0)))
                .applyIf(showMessageMenuOnLongPress) {
                    $0.simultaneousGesture(
                        TapGesture().onEnded { } // add empty tap to prevent iOS17 scroll breaking bug (drag on cells stops working)
                    )
                    .onLongPressGesture {
                        // Trigger haptic feedback
                        self.impactGenerator.impactOccurred()
                        // Launch the message menu
                        self.viewModel.messageMenuRow = row
                    }
                }
            }
            .minSize(width: 0, height: 0)
            .margins(.all, 0)

            return tableViewCell
        }

        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            guard let paginationHandler = self.paginationHandler, let paginationTargetIndexPath, indexPath == paginationTargetIndexPath else {
                return
            }

            let row = self.sections[indexPath.section].rows[indexPath.row]
            Task.detached {
                await paginationHandler.handleClosure(row.message)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            isScrolledToBottom = scrollView.contentOffset.y <= scrollBottomTolerance
            isScrolledToTop = scrollView.contentOffset.y >= scrollView.contentSize.height - scrollView.frame.height - 1
        }
    }

    func formatRow(_ row: MessageRow) -> String {
        String(
            "id: \(row.id) text: \(row.message.text) status: \(row.message.status ?? .none) date: \(row.message.createdAt) position in user group: \(row.positionInUserGroup) position in messages section: \(row.positionInMessagesSection) trigger: \(row.message.triggerRedraw)"
        )
    }

    func formatSections(_ sections: [MessagesSection]) -> String {
        var res = "{\n"
        for section in sections.reversed() {
            res += String("\t{\n")
            for row in section.rows {
                res += String("\t\t\(formatRow(row))\n")
            }
            res += String("\t}\n")
        }
        res += String("}")
        return res
    }
}

@MainActor
final class UpdateQueue {
    private var isProcessing = false

    func enqueue(_ work: @escaping @MainActor () async -> Void) async {
        while isProcessing {
            await Task.yield() // Wait for previous task to finish
        }

        isProcessing = true
        await work()
        isProcessing = false
    }
}

/// Reloads its rows whenever its width changes.
///
/// UIHostingConfiguration cells keep the layout they were measured at when the
/// table's width changes without a SwiftUI environment change (e.g. rotating an
/// iPhone Pro, resizing an iPad window, showing or hiding the split view sidebar,
/// folding or unfolding a device). Keying the reload off the width itself covers
/// all of these; a device-orientation notification only covers rotation.
private final class WidthTrackingTableView: UITableView {
    private var lastLaidOutWidth: CGFloat = 0
    private var isReloadScheduled = false

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = bounds.width
        guard width != lastLaidOutWidth else { return }
        let previousWidth = lastLaidOutWidth
        lastLaidOutWidth = width

        // The first real layout creates cells at the right width; nothing is stale yet.
        guard previousWidth > 0, !isReloadScheduled else { return }

        // Reload outside the layout pass. A live window resize changes the width
        // on every frame, so this also coalesces to one reload per run-loop turn.
        isReloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isReloadScheduled = false
            UIView.performWithoutAnimation {
                self.reloadData()
            }
        }
    }
}
