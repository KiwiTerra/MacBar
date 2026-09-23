import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: BarModel
    let dismiss: () -> Void
    @State private var query = ""
    @State private var selection: String?
    @State private var hovered: String?
    private var results: [ApplicationEntry] { ApplicationCatalog.filter(model.applications, query: query) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Applications").font(.system(size: 23, weight: .semibold))
                    Text("Open an app or pin it to the bar.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 30, height: 30) }
                    .buttonStyle(.plain).help("Close").accessibilityLabel("Close launcher")
            }.padding(22)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                SearchField(text: $query, move: moveSelection, submit: openSelected, cancel: dismiss)
                    .frame(height: 20)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                }
            }.padding(13).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                .padding(.horizontal, 22).padding(.bottom, 14)
            if !model.trusted {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Enable Window Control", systemImage: "hand.raised")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Allow MacBar in Accessibility to select, show, and minimize individual windows. You can already launch your applications.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Open Accessibility Settings") { model.requestAccessibility() }
                        .buttonStyle(.bordered)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                    .padding(.horizontal, 22).padding(.bottom, 12)
            }
            if let error = model.error {
                HStack {
                    Text(error).font(.system(size: 12)).foregroundStyle(Color(red: 1, green: 0.75, blue: 0.42))
                    Spacer()
                    Button("Close") { model.error = nil }.buttonStyle(.plain)
                }.padding(.horizontal, 22).padding(.bottom, 10)
            }
            if model.loadingApplications {
                Spacer()
                HStack { Spacer(); ProgressView("Searching for applications…"); Spacer() }
                Spacer()
            } else if results.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("No applications found").font(.system(size: 15, weight: .medium))
                    Text("Try another name.").font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(results) { app in
                                HStack(spacing: 0) {
                                    Button { launch(app) } label: {
                                        HStack(spacing: 12) {
                                            Image(nsImage: IconCache.shared.icon(app.url)).resizable().frame(width: 30, height: 30)
                                            Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                            Spacer()
                                        }.padding(.leading, 12).padding(.vertical, 9).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                        .onDrag { model.beginDrag(app.url, pin: true); return AppDrag.provider(app.url, pin: true) }
                                    Button { model.togglePin(app.url) } label: {
                                        Image(systemName: model.isPinned(app.url) ? "pin.fill" : "pin")
                                            .font(.system(size: 12)).frame(width: 40, height: 42)
                                            .foregroundStyle(model.isPinned(app.url) ? Color(red: 0.45, green: 0.73, blue: 1) : .secondary)
                                    }.buttonStyle(.plain)
                                        .help(model.isPinned(app.url) ? "Unpin" : "Pin to Taskbar")
                                        .accessibilityLabel((model.isPinned(app.url) ? "Unpin " : "Pin ") + app.name)
                                }
                                .background(selection == app.id ? Color.white.opacity(0.10) : hovered == app.id ? Color.white.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .onHover { hovered = $0 ? app.id : nil }
                                .id(app.id)
                            }
                        }.padding(.horizontal, 14)
                    }
                    .onChange(of: selection) { id in if let id { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            HStack {
                Text("\(results.count) applications")
                Spacer()
                Text("↑ ↓ select   ↵ open   esc close")
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(18)
        }
        .frame(width: 440)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.105, green: 0.112, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
        .onAppear { selection = results.first?.id }
        .onChange(of: query) { _ in selection = results.first?.id }
        .onChange(of: model.applications) { _ in selection = results.first?.id }
        .onExitCommand { dismiss() }
    }
    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selection } ?? 0
        selection = results[max(0, min(results.count - 1, index + delta))].id
    }
    private func launch(_ app: ApplicationEntry) { dismiss(); model.open(app.url) }
    private func openSelected() {
        if let app = results.first(where: { $0.id == selection }) ?? results.first { launch(app) }
    }
}
