import SwiftUI

/// Gradient tile with the module's symbol.
struct ModuleIcon: View {
    let module: Module
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: module.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(module.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

/// The start screen of a module: big icon, description and the main button.
struct ModuleLanding<Footer: View>: View {
    let module: Module
    var buttonTitle = "Scan"
    let action: () -> Void
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ModuleIcon(module: module, size: 120)
                .shadow(color: module.tint.opacity(0.35), radius: 24, y: 10)
            VStack(spacing: 8) {
                Text(module.title).font(.largeTitle.bold())
                Text(module.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            Button(action: action) {
                Text(buttonTitle)
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 140)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(module.tint)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            footer
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ModuleLanding where Footer == EmptyView {
    init(module: Module, buttonTitle: String = "Scan", action: @escaping () -> Void) {
        self.init(module: module, buttonTitle: buttonTitle, action: action) { EmptyView() }
    }
}

/// Shown while a scan or cleanup runs.
struct WorkingView: View {
    let module: Module
    let title: String
    let detail: String
    var onStop: (() -> Void)?

    @State private var spin = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(module.tint.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(module.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
                Image(systemName: module.symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(module.gradient)
            }
            .frame(width: 130, height: 130)
            .onAppear { spin = true }

            Text(title).font(.title2.bold())
            Text(detail)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
            if let onStop {
                Button("Stop", action: onStop)
                    .controlSize(.large)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Header row used above result lists.
struct ResultsHeader<Trailing: View>: View {
    let module: Module
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            ModuleIcon(module: module, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// Bottom bar with the selection summary and the destructive action.
struct ActionBar: View {
    let module: Module
    let summary: String
    let buttonTitle: String
    var isDisabled = false
    var secondaryTitle: String?
    var isSecondaryDisabled = false
    var secondaryAction: (() -> Void)?
    let action: () -> Void

    var body: some View {
        HStack {
            Text(summary).foregroundStyle(.secondary)
            Spacer()
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .controlSize(.large)
                    .disabled(isSecondaryDisabled)
            }
            Button(action: action) {
                Text(buttonTitle).frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .tint(module.tint)
            .controlSize(.large)
            .disabled(isDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

/// Explains why some results may be missing and links to System Settings.
struct FullDiskAccessBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if !app.hasFullDiskAccess {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Disk Access is off").font(.headline)
                    Text("macOS hides the Trash, Mail downloads and other apps' data from Sweep until you allow it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                Button("Check Again") { app.refreshPermissions() }
            }
            .padding(12)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)
        }
    }
}
