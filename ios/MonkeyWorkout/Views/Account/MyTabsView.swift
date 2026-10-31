import SwiftUI
import WorkoutEngine

// MARK: - My tabs (#1004, design A + C from `hide-tabs/proposals.png`)

extension MainTab {
    /// Same colours as the app tour stops.
    var category: WorkoutEngine.Category {
        switch self {
        case .train: .strength
        case .explore: .cardio
        case .progress: .power
        case .fuel: .warmup
        case .community: .mobility
        }
    }
}

/// Settings › My tabs (A): one gradient card per tab with a switch; Train locked on.
struct MyTabsView: View {
    @State private var pref = TabsPref.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AccountHeader(symbol: "dock.rectangle", title: "My tabs",
                              subtitle: "Hide tabs you don't use. Their cards, widgets and Coach links go too; nothing is deleted.",
                              gradient: SettingsChapter.look.gradient)
                ForEach(MainTab.allCases, id: \.self) { tab in row(tab) }
            }
            .padding(16)
            .readableWidth()
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("My tabs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ tab: MainTab) -> some View {
        let on = pref.shows(tab)
        let locked = tab == .train
        return HStack(spacing: 12) {
            Image(systemName: tab.symbol)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title).font(Theme.display(19))
                Text(on ? tab.blurb : "Hidden · data kept").font(.footnote.weight(.semibold)).opacity(0.85)
            }
            Spacer(minLength: 6)
            if locked {
                Image(systemName: "lock.fill").font(.subheadline.weight(.bold))
            } else {
                Toggle(tab.title, isOn: Binding(get: { on }, set: { v in
                    withAnimation(.snappy) { pref.set(tab, shown: v) }
                }))
                .labelsHidden()
                .tint(.white.opacity(0.9))
                .accessibilityIdentifier("tabs.\(tab.rawValue)")
            }
        }
        .foregroundStyle(on ? tab.category.ink : Theme.muted)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(on ? AnyShapeStyle(tab.category.gradient) : AnyShapeStyle(Color.white.opacity(0.08))))
    }
}

/// Hide from the tab itself (C): the tab's title opens a menu (no extra header tile, the headers are full); hiding
/// lands on Train with an Undo bar.
struct TabTitleMenu: View {
    let tab: MainTab
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button(role: .destructive) { hide() } label: {
                Label("Hide \(tab.title) tab", systemImage: "eye.slash")
            }
            Button { model.settingsOpen = true } label: {
                Label("My tabs in Settings", systemImage: "dock.rectangle")
            }
        } label: {
            HStack(alignment: .center, spacing: 6) {
                Text(tab.title).font(Theme.display(34)).lineLimit(1).minimumScaleFactor(0.7)
                Image(systemName: "chevron.down").font(.system(size: 14, weight: .heavy)).opacity(0.55)
            }
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(tab.title)
        .accessibilityHint("Options for this tab, like hiding it")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("tab.menu.\(tab.rawValue)")
    }

    private func hide() {
        let tab = tab
        let model = model
        TabsPref.shared.set(tab, shown: false)
        model.tab = .train
        UndoCloseCenter.shared.show(UndoOffer(
            title: "\(tab.title) hidden", detail: "Show it again in Settings › My tabs", symbol: "eye.slash.fill",
            reopen: { AnyView(EmptyView()) },
            revert: {
                TabsPref.shared.set(tab, shown: true)
                model.tab = tab
            }))
    }
}
