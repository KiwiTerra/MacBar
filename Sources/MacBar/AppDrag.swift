import SwiftUI
import UniformTypeIdentifiers

/// Internal drags use a private type, so stale drag state cannot interpret external text as an app.
enum AppDrag {
    static let type = UTType(exportedAs: "dev.local.MacBar.application")
    static let accepted = [type, .fileURL]
    struct Payload: Codable { let path: String; let pin: Bool }
    static func provider(_ url: URL, pin: Bool = false) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
            completion(try? JSONEncoder().encode(Payload(path: url.path, pin: pin)), nil)
            return nil
        }
        return provider
    }
}
struct AppDropDelegate: DropDelegate {
    let model: BarModel
    // One destination covers the row: nested SwiftUI destinations can swallow drops.
    private func destination(_ info: DropInfo) -> (URL?, Bool) {
        let width: CGFloat = model.grouped ? 46 : 164
        let (index, after) = AppOrdering.destination(x: info.location.x, itemWidth: width, count: model.tasks.count)
        guard model.tasks.indices.contains(index) else { return (nil, true) }
        return (model.tasks[index].url, after)
    }
    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL]) || info.hasItemsConforming(to: [AppDrag.type])
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let (target, after) = destination(info)
        model.dropTarget = target?.path ?? "end"
        model.dropAfter = after
        return DropProposal(operation: info.hasItemsConforming(to: [AppDrag.type]) ? .move : .copy)
    }
    func dropExited(info: DropInfo) { model.dropTarget = nil }
    func performDrop(info: DropInfo) -> Bool {
        let (target, after) = destination(info)
        if let provider = info.itemProviders(for: [AppDrag.type]).first {
            provider.loadDataRepresentation(forTypeIdentifier: AppDrag.type.identifier) { data, _ in
                DispatchQueue.main.async {
                    guard let data, let payload = try? JSONDecoder().decode(AppDrag.Payload.self, from: data) else { model.endDrag(); return }
                    model.drop(URL(fileURLWithPath: payload.path), relativeTo: target, after: after, external: payload.pin)
                }
            }
            return true
        }
        guard let provider = info.itemProviders(for: [.fileURL]).first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            DispatchQueue.main.async {
                if let url { model.drop(url, relativeTo: target, after: after, external: true) }
                else { model.endDrag() }
            }
        }
        return true
    }
}
