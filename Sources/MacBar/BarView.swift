import SwiftUI
import AppKit

struct BarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.16) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct UtilityButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                .frame(width: 42, height: 56)
                .background(hovered ? Color.white.opacity(0.09) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(BarButtonStyle()).onHover { hovered = $0 }
        .help(label).accessibilityLabel(label)
    }
}

struct TaskButton: View {
    let task: TaskEntry
    @ObservedObject var model: BarModel
    @State private var hovered = false
    var body: some View {
        Button { model.click(task) } label: {
            HStack(spacing: 8) {
                Image(nsImage: IconCache.shared.icon(task.url)).resizable().interpolation(.high)
                    .frame(width: 28, height: 28)
                if !model.grouped {
                    Text(task.name).font(.system(size: 12, weight: task.active ? .semibold : .regular))
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: model.grouped ? 46 : 164, height: 56)
            .background(task.active ? Color.white.opacity(0.12) : hovered ? Color.white.opacity(0.07) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .bottom) {
                if task.running {
                    Capsule().fill(task.active ? Color(red: 0.45, green: 0.73, blue: 1) : Color.white.opacity(0.5))
                        .frame(width: task.active ? 17 : 5, height: 3).offset(y: -1)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let badge = model.badge(for: task.url) {
                    Text(DockBadge.display(badge)).font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                        .background(Color(red: 0.88, green: 0.16, blue: 0.21), in: Capsule())
                        .overlay(Capsule().stroke(Color(red: 0.105, green: 0.112, blue: 0.13), lineWidth: 1.5))
                        .offset(x: -1, y: 4).allowsHitTesting(false)
                } else if model.grouped && task.windows.count > 1 {
                    Text("\(task.windows.count)").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white).padding(.horizontal, 3)
                        .background(Color(white: 0.25), in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: -1, y: 1)
                }
            }
        }
        .buttonStyle(BarButtonStyle()).onHover {
            hovered = $0
            model.hoverTask?(task, $0)
        }
        .opacity(model.draggedURL == task.url ? 0.5 : 1)
        .overlay(alignment: model.dropAfter ? .trailing : .leading) {
            if model.dropTarget == task.url.path {
                Rectangle().fill(Color.accentColor).frame(width: 2, height: 40).allowsHitTesting(false)
            }
        }
        .help(task.subtitle + (task.window != nil ? " — " + task.name : ""))
        .accessibilityLabel(task.name)
        .accessibilityValue((task.active ? "Active application" : task.running ? "Running application" : "Pinned application") + (model.badge(for: task.url).map { ", badge: " + $0 } ?? ""))
        .contextMenu {
            if !task.windows.isEmpty {
                ForEach(task.windows) { window in
                    Button((window.minimized ? "Minimized · " : "") + window.title) { model.select(window, in: task) }
                }
                Divider()
            }
            Button(model.isPinned(task.url) ? "Unpin from Taskbar" : "Pin to Taskbar") { model.togglePin(task.url) }
            Button("Move Left") { model.move(task, direction: -1) }
            Button("Move Right") { model.move(task, direction: 1) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([task.url]) }
            if let window = task.window {
                Button("Close this window") { model.close(window) }
            }
            if let pid = task.pid {
                Divider()
                Button("Quit Application") { NSRunningApplication(processIdentifier: pid)?.terminate() }
            }
        }
    }
}

struct BarView: View {
    @ObservedObject var model: BarModel
    var body: some View {
        HStack(spacing: 0) {
            UtilityButton(symbol: "square.grid.2x2.fill", label: "Applications") { model.showLauncher?() }
                .foregroundStyle(Color(red: 0.45, green: 0.73, blue: 1))
            Divider().frame(height: 24).overlay(Color.white.opacity(0.10))
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        if model.tasks.isEmpty {
                            Text("Open an application or pin your favorites")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        ForEach(model.tasks) { task in TaskButton(task: task, model: model) }
                    }
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .leading)
                    .background(NativeReordering(model: model))
                    .contentShape(Rectangle())
                    .onDrop(of: AppDrag.accepted, delegate: AppDropDelegate(model: model))
                }
            }
            if model.error != nil {
                UtilityButton(symbol: "exclamationmark.circle", label: "Show the reported issue") { model.showLauncher?() }
                    .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.39))
            }
            if !model.trusted {
                UtilityButton(symbol: "hand.raised", label: "Allow Window Control") { model.showLauncher?() }
                    .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.39))
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(model.clock, format: .dateTime.hour().minute()).font(.system(size: 12, weight: .medium).monospacedDigit())
                Text(model.clock, format: .dateTime.day().month()).font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(width: 58, alignment: .trailing)
            UtilityButton(symbol: "ellipsis", label: "MacBar Options") { model.showSettings?() }
        }
        .frame(height: 56)
        .background(Color(red: 0.105, green: 0.112, blue: 0.13))
        .overlay(alignment: .top) { Color.white.opacity(0.12).frame(height: 1) }
        .environment(\.colorScheme, .dark)
    }
}
