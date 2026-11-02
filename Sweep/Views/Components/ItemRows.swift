import AppKit
import SwiftUI

/// Finder icon for a file or folder.
struct FileIcon: View {
    let url: URL
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.plainPath))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// A checkbox row for one file or folder.
struct CleanupItemRow: View {
    @Binding var item: CleanupItem

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $item.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            FileIcon(url: item.url)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    if item.requiresAdmin {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("Needs your administrator password")
                    }
                }
                Text(item.note ?? item.url.deletingLastPathComponent().abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(item.size.formattedBytes)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path, forType: .string)
            }
        }
        .help(item.path)
    }
}

/// Summary shown after a cleanup, with a way to retry protected items as admin.
struct CleanupReportView: View {
    let module: Module
    let report: CleanupReport
    var removalMode: RemovalMode = .permanent
    var onRetryAsAdmin: (() -> Void)?
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)
            Image(systemName: report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(report.failures.isEmpty ? AnyShapeStyle(module.gradient) : AnyShapeStyle(.orange))
            Text(headline).font(.largeTitle.bold())
            Text(detail)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !report.failures.isEmpty {
                List(report.failures) { failure in
                    HStack {
                        FileIcon(url: failure.url, size: 22)
                        VStack(alignment: .leading) {
                            Text(failure.url.lastPathComponent).lineLimit(1)
                            Text(failure.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: 560, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if let onRetryAsAdmin, !report.adminRetryCandidates.isEmpty {
                    Button("Remove \(report.adminRetryCandidates.count) Protected Items as Administrator…", action: onRetryAsAdmin)
                    Text("These items are deleted permanently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(module.tint)
                .controlSize(.large)
            Spacer(minLength: 20)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headline: String {
        if report.removed.isEmpty && !report.failures.isEmpty { return "Nothing was removed" }
        return report.freedBytes > 0 ? "\(report.freedBytes.formattedBytes) cleaned" : "All done"
    }

    private var detail: String {
        var parts = ["Removed \(report.removed.count) item\(report.removed.count == 1 ? "" : "s")."]
        if removalMode == .trash && report.freedBytes > 0 {
            parts.append("They're in the Trash. Empty it to get the space back.")
        }
        if !report.failures.isEmpty {
            parts.append("\(report.failures.count) couldn't be removed.")
        }
        return parts.joined(separator: " ")
    }
}

/// Selection state of a group of items, for tri-state checkboxes.
enum SelectionState {
    case none, some, all

    init(_ items: [CleanupItem]) {
        let selected = items.selectedCount
        self = selected == 0 ? .none : (selected == items.count ? .all : .some)
    }
}

/// A checkbox that shows a dash for mixed selections and toggles all items.
struct GroupCheckbox: View {
    let state: SelectionState
    let setAll: (Bool) -> Void

    var body: some View {
        Button {
            setAll(state != .all)
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(state == .none ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .all ? "Deselect all" : "Select all")
    }

    private var symbol: String {
        switch state {
        case .none: "square"
        case .some: "minus.square.fill"
        case .all: "checkmark.square.fill"
        }
    }
}
