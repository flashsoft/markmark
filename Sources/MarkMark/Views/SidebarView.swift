import SwiftUI
import MarkdownReaderKit

/// 左侧 Sidebar 目录树视图
struct SidebarView: View {
    let fileTreeViewModel: FileTreeViewModel
    let appViewModel: AppViewModel
    let documentViewModel: DocumentViewModel
    @Environment(\.language) private var language
    @Environment(\.themeColors) private var themeColors
    @FocusState private var isFileTreeFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 顶部区域：自定义红绿灯 + Sidebar 隐藏按钮 + 打开按钮 + 新建文件按钮（50px）
            HStack(spacing: 0) {
                // 自定义红绿灯按钮
                TrafficLightButtons()
                    .padding(.leading, 12)

                // Sidebar 隐藏按钮
                Button {
                    appViewModel.toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 14))
                        .foregroundStyle(themeColors.fgSecondary)
                }
                .buttonStyle(.plain)
                .help(L10n.tr(.titleBarToggleSidebar, language: language))
                .padding(.leading, 8)

                // 打开按钮（与菜单 Cmd+O 功能一致，直接调用避免 WindowGroup 多实例重复弹窗）
                Button {
                    OpenPanelHelper.show(language: language)
                } label: {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(themeColors.fgSecondary)
                }
                .buttonStyle(.plain)
                .help(L10n.tr(.titleBarOpen, language: language))
                .padding(.leading, 4)

                // 从剪贴板新建标注
                Button {
                    NotificationCenter.default.post(name: .newFromClipboard, object: nil)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14))
                        .foregroundStyle(themeColors.fgSecondary)
                }
                .buttonStyle(.plain)
                .help(L10n.tr(.newFromClipboard, language: language))
                .padding(.leading, 4)

                Spacer()
            }
            .frame(height: 50)
            .background(WindowDragArea())

            if appViewModel.isSingleFileMode {
                singleFileView
            } else if fileTreeViewModel.isLoading {
                ProgressView(L10n.tr(.loading, language: language))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = fileTreeViewModel.errorMessage {
                ErrorView(message: error)
            } else if fileTreeViewModel.nodes.isEmpty {
                emptyDirectoryView
            } else {
                directoryTreeView
            }

            // 底部固定区域：Settings 按钮（参考 Buddy 底部固定设置入口）
            settingsButton
        }
        .background(themeColors.bgSubtle)
    }

    // MARK: - 单文件列表

    private var singleFileView: some View {
        List {
            if let url = appViewModel.singleFileURL {
                let node = FileNode(
                    name: url.lastPathComponent,
                    path: url,
                    isDirectory: false,
                    isMarkdown: FileService.isTreeDisplayExtension(url)
                )

                Button {
                    isFileTreeFocused = true
                    fileTreeViewModel.activateNode(node)
                } label: {
                    FileRowView(
                        node: node,
                        fileTreeViewModel: fileTreeViewModel,
                        documentViewModel: documentViewModel
                    )
                    .background(singleFileSelectionHighlight(for: url))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.automatic)
        .background(OverlayScrollerHelper())
    }

    @ViewBuilder
    private func singleFileSelectionHighlight(for url: URL) -> some View {
        if fileTreeViewModel.activeNodeURL == url
            || (fileTreeViewModel.activeNodeURL == nil && fileTreeViewModel.selectedFileURL == url) {
            RoundedRectangle(cornerRadius: 6)
                .fill(themeColors.accentSoft)
        }
    }

    // MARK: - 目录树（使用递归 DisclosureGroup 渲染嵌套结构）

    private var directoryTreeView: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(fileTreeViewModel.nodes) { node in
                    FileNodeRow(node: node, fileTreeViewModel: fileTreeViewModel, documentViewModel: documentViewModel)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.automatic)
            .background(OverlayScrollerHelper())
            .focusable()
            .focused($isFileTreeFocused)
            .onAppear { isFileTreeFocused = true }
            .onTapGesture { isFileTreeFocused = true }
            .onMoveCommand { direction in
                switch direction {
                case .up:
                    _ = fileTreeViewModel.moveSelection(direction: -1)
                case .down:
                    _ = fileTreeViewModel.moveSelection(direction: 1)
                default:
                    break
                }
            }
            .onKeyPress(.upArrow) {
                _ = fileTreeViewModel.moveSelection(direction: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                _ = fileTreeViewModel.moveSelection(direction: 1)
                return .handled
            }
            .onKeyPress(.leftArrow) {
                fileTreeViewModel.collapseActiveNodeOrMoveToParent()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                fileTreeViewModel.expandActiveNode()
                return .handled
            }
            .onKeyPress(.return) {
                if let url = fileTreeViewModel.activeNodeURL ?? fileTreeViewModel.selectedFileURL,
                   let node = findNode(in: fileTreeViewModel.nodes, url: url) {
                    if node.isDirectory {
                        fileTreeViewModel.toggleExpand(url)
                    } else {
                        fileTreeViewModel.selectFile(node)
                    }
                }
                return .handled
            }
            .onChange(of: fileTreeViewModel.activeNodeURL) { _, newURL in
                guard let newURL else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(newURL, anchor: .center)
                }
            }
        }
    }

    // MARK: - 空目录提示

    private var emptyDirectoryView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 32))
                .foregroundStyle(themeColors.fgMuted)
            Text(L10n.tr(.emptyDirectoryMessage, language: language))
                .font(.subheadline)
                .foregroundStyle(themeColors.fgSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部设置按钮

    private var settingsButton: some View {
        Button {
            appViewModel.showSettings()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(themeColors.fgSecondary)
                Text(L10n.tr(.sidebarSettingsButton, language: language))
                    .font(.system(size: 13))
                    .foregroundStyle(themeColors.fgSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.tr(.sidebarSettings, language: language))
    }

    // MARK: - 辅助方法

    private func findNode(in nodes: [FileNode], url: URL) -> FileNode? {
        for node in nodes {
            if node.path == url { return node }
            if node.isDirectory, let children = node.children {
                if let found = findNode(in: children, url: url) {
                    return found
                }
            }
        }
        return nil
    }
}

// MARK: - 递归目录节点视图

/// 支持展开/折叠绑定的递归目录节点视图
struct FileNodeRow: View {
    let node: FileNode
    let fileTreeViewModel: FileTreeViewModel
    let documentViewModel: DocumentViewModel
    @Environment(\.themeColors) private var themeColors
    @Environment(\.language) private var language

    /// 是否为当前 active 项
    private var isActive: Bool {
        fileTreeViewModel.activeNodeURL == node.path
            || (fileTreeViewModel.activeNodeURL == nil && fileTreeViewModel.selectedFileURL == node.path)
    }

    /// Active 高亮（模仿系统选中样式：圆角、accentSoft）
    ///
    /// 作为行内容（FileRowView）的 `.background` 绘制，而非 `.listRowBackground`。
    /// `.listRowBackground` 会铺满整行单元格（含 List 默认行内边距、且不随层级缩进），
    /// 但可点击区域只覆盖按钮 label（即内容本身），导致高亮比可点击区域大——
    /// 点在高亮边缘却点不中。改为内容背景后，高亮跟随内容（=可点击区域），
    /// FileRowView 自身负责撑满可点击宽度和提供内边距，避免选中背景小于热区。
    @ViewBuilder
    private var selectionHighlight: some View {
        if isActive {
            RoundedRectangle(cornerRadius: 6)
                .fill(themeColors.accentSoft)
        }
    }

    var body: some View {
        if let children = node.children, !children.isEmpty {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { fileTreeViewModel.isExpanded(node.path) },
                    set: { _ in fileTreeViewModel.toggleExpand(node.path) }
                )
            ) {
                ForEach(children) { child in
                    FileNodeRow(node: child, fileTreeViewModel: fileTreeViewModel, documentViewModel: documentViewModel)
                }
            } label: {
                FileRowView(node: node, fileTreeViewModel: fileTreeViewModel, documentViewModel: documentViewModel)
                    .background(selectionHighlight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 点击目录标签区域先 active，再切换展开/折叠
                        fileTreeViewModel.activateNode(node)
                        fileTreeViewModel.toggleExpand(node.path)
                    }
                    .contextMenu { directoryContextMenu }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .id(node.path)
        } else {
            // 文件行使用 Button 确保可靠选中
            Button {
                fileTreeViewModel.activateNode(node)
            } label: {
                FileRowView(node: node, fileTreeViewModel: fileTreeViewModel, documentViewModel: documentViewModel)
                    .background(selectionHighlight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .contextMenu { fileContextMenu }
            .id(node.path)
        }
    }

    // MARK: - 目录右键菜单

    /// 目录的右键菜单：新建文档、新建子目录、复制路径、重命名、移动到、删除
    @ViewBuilder
    private var directoryContextMenu: some View {
        Button {
            fileTreeViewModel.createNewFileInDirectory(node.path)
        } label: {
            Label(L10n.tr(.contextMenuNewFile, language: language), systemImage: "doc.badge.plus")
        }
        Button {
            fileTreeViewModel.createSubdirectory(in: node.path)
        } label: {
            Label(L10n.tr(.contextMenuNewSubdirectory, language: language), systemImage: "folder.badge.plus")
        }
        Divider()
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(node.path.path, forType: .string)
        } label: {
            Label(L10n.tr(.contextMenuCopyPath, language: language), systemImage: "doc.on.doc")
        }
        Divider()
        Button {
            fileTreeViewModel.renameItem(node)
        } label: {
            Label(L10n.tr(.contextMenuRename, language: language), systemImage: "pencil")
        }
        Button {
            fileTreeViewModel.moveItem(node)
        } label: {
            Label(L10n.tr(.contextMenuMoveTo, language: language), systemImage: "folder.and.arrow.down")
        }
        Divider()
        Button {
            fileTreeViewModel.deleteItem(node)
        } label: {
            Label(L10n.tr(.contextMenuDelete, language: language), systemImage: "trash")
        }
    }

    // MARK: - 文件右键菜单

    /// 文件的右键菜单：重新加载、复制路径、新建文档、重命名、移动到、删除
    @ViewBuilder
    private var fileContextMenu: some View {
        // 重新加载：仅对当前打开且被外部修改的文件可用
        Button {
            NotificationCenter.default.post(name: .reloadFile, object: nil)
        } label: {
            Label(L10n.tr(.contextMenuReload, language: language), systemImage: "arrow.clockwise")
        }
        .disabled(
            documentViewModel.currentFileURL != node.path
                || !documentViewModel.isFileModifiedExternally
        )
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(node.path.path, forType: .string)
        } label: {
            Label(L10n.tr(.contextMenuCopyPath, language: language), systemImage: "doc.on.doc")
        }
        Divider()
        Button {
            // 在文件所在目录下新建文档
            fileTreeViewModel.createNewFileInDirectory(node.path.deletingLastPathComponent())
        } label: {
            Label(L10n.tr(.contextMenuNewFile, language: language), systemImage: "doc.badge.plus")
        }
        Divider()
        Button {
            fileTreeViewModel.renameItem(node)
        } label: {
            Label(L10n.tr(.contextMenuRename, language: language), systemImage: "pencil")
        }
        Button {
            fileTreeViewModel.moveItem(node)
        } label: {
            Label(L10n.tr(.contextMenuMoveTo, language: language), systemImage: "folder.and.arrow.down")
        }
        Divider()
        Button {
            fileTreeViewModel.deleteItem(node)
        } label: {
            Label(L10n.tr(.contextMenuDelete, language: language), systemImage: "trash")
        }
    }
}
