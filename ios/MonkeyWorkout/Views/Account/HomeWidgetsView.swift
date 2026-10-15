import SwiftUI

/// Account → Home Screen widgets (#297, design 3): one-tap presets with live previews, Customise for look and
/// topic per size. Each widget's own Edit Widget can still override it.
struct HomeWidgetsView: View {
    private var sync: HomeWidgetSync { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Home Screen widgets").font(Theme.display(34)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("Pick a set for your Home and Lock Screen widgets. Live numbers from your week.")
                        .font(.body.weight(.medium)).foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 4)

                ForEach(HomeWidgetPreset.allCases) { preset in
                    Button { sync.apply(preset) } label: { PresetCard(preset: preset, selected: sync.settings.preset == preset, snap: sync.snapshot) }
                        .buttonStyle(.plain)
                }

                NavigationLink { HomeWidgetsCustomView() } label: {
                    AccountCard(symbol: "slider.horizontal.3", title: "Customise sizes",
                                subtitle: sync.settings.preset == nil ? "Your own mix · \(sync.settings.look.title)" : "Look and topic for each size",
                                gradient: AccountTint.whatsNew, ink: true)
                }
                .buttonStyle(.plain)

                HowToAdd()
            }
            .padding(16)
            .sensoryFeedback(.selection, trigger: sync.settings)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Widgets")
        .toolbarTitleDisplayMode(.inline)
    }
}

private struct PresetCard: View {
    let preset: HomeWidgetPreset
    let selected: Bool
    let snap: HomeWidgetSnapshot

    var body: some View {
        let s = preset.settings
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.title).font(Theme.display(22))
                    Text(s.look.title + " · " + preset.summary).font(.footnote.weight(.semibold)).opacity(0.9).lineLimit(2)
                }
                Spacer(minLength: 6)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(selected ? Theme.lime : .white.opacity(0.6))
            }
            HStack(alignment: .top, spacing: 8) {
                HomeWidgetPreview(topic: s.small, look: s.look, size: .small, snap: snap, unit: 78)
                HomeWidgetPreview(topic: s.medium, look: s.look, size: .medium, snap: snap, unit: 78)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: s.look.tint.0), Color(hex: s.look.tint.1)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.lime, lineWidth: selected ? 3 : 0))
        .animation(.spring(duration: 0.3), value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct HowToAdd: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Add a widget", systemImage: "plus.square.on.square").font(Theme.label(14)).foregroundStyle(Theme.lime)
            Text("Touch and hold your Home Screen, tap Edit, then Add Widget, and pick MonkeyWorkout. Choose Small, Medium or Large. For the Lock Screen, touch and hold it and tap Customise.")
            Text("To give one widget its own topic or look, touch and hold it and tap Edit Widget.")
        }
        .font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Look plus a topic for Small, Medium, Large and Lock Screen, with a preview of the size being changed.
struct HomeWidgetsCustomView: View {
    private var sync: HomeWidgetSync { .shared }
    @State private var focus: HomeWidgetSize = .medium

    var body: some View {
        let s = sync.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Look").font(Theme.label(13)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.lime)
                HStack(spacing: 8) {
                    ForEach(HomeWidgetLook.allCases) { look in
                        Button { var n = s; n.look = look; sync.set(n) } label: { LookTile(look: look, selected: s.look == look) }
                            .buttonStyle(.plain)
                    }
                }
                Text(s.look.detail).font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)

                Text("What each size shows").font(Theme.label(13)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.lime)
                    .padding(.top, 6)
                ForEach(HomeWidgetSize.allCases) { size in
                    SizeRow(size: size, topic: s.topic(size), focused: focus == size) { topic in
                        var n = s
                        n.set(topic, for: size)
                        sync.set(n)
                        focus = size
                    }
                    .onTapGesture { focus = size }
                }

                Text("Preview · \(focus.title)").font(Theme.label(13)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.lime)
                    .padding(.top, 6)
                HomeWidgetPreview(topic: s.topic(focus), look: s.look, size: focus, snap: sync.snapshot, unit: 150)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x1E2A55), Color(hex: 0x3A1F4D)], startPoint: .top, endPoint: .bottom)))
                    .animation(.snappy, value: s)
                    .animation(.snappy, value: focus)
            }
            .padding(16)
            .sensoryFeedback(.selection, trigger: s)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Customise")
        .toolbarTitleDisplayMode(.inline)
    }
}

private struct LookTile: View {
    let look: HomeWidgetLook
    let selected: Bool

    var body: some View {
        Text(look.title).font(Theme.label(13)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.8)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .bottomLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: look.tint.0), Color(hex: look.tint.1)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.lime).padding(6)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Theme.lime : .white.opacity(0.15), lineWidth: selected ? 3 : 1))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SizeRow: View {
    let size: HomeWidgetSize
    let topic: HomeWidgetTopic
    let focused: Bool
    let pick: (HomeWidgetTopic) -> Void

    var body: some View {
        Menu {
            ForEach(HomeWidgetTopic.offered(for: size)) { t in
                Button { pick(t) } label: { Label(t.title, systemImage: t.symbol) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: size.symbol).font(.system(size: 18, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                Text(size.title).font(Theme.display(17))
                Spacer(minLength: 6)
                Text(topic.title).font(Theme.label(14)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .bold)).opacity(0.8)
            }
            .foregroundStyle(topic.inkOnGradient ? Color(hex: 0x2A1A00) : .white)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: topic.tint.0), Color(hex: topic.tint.1)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.lime, lineWidth: focused ? 2.5 : 0))
        }
        .accessibilityLabel("\(size.title): \(topic.title)")
    }
}

#if DEBUG
/// Demo screens home-widgets-<look> (#297): one look's small, medium, large and Lock Screen faces on a wallpaper.
struct HomeWidgetGallery: View {
    let look: HomeWidgetLook
    private var snap: HomeWidgetSnapshot { HomeWidgetSync.shared.snapshot }

    var body: some View {
        let topics = Self.topics(look)
        ScrollView {
            VStack(spacing: 14) {
                Text(look.title).font(Theme.display(26)).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 14) {
                    ForEach(topics.small, id: \.self) { HomeWidgetPreview(topic: $0, look: look, size: .small, snap: snap, unit: 158) }
                }
                HomeWidgetPreview(topic: topics.medium, look: look, size: .medium, snap: snap, unit: 158)
                HomeWidgetPreview(topic: topics.large, look: look, size: .large, snap: snap, unit: 158)
                HStack(spacing: 10) {
                    HomeWidgetPreview(topic: .nextUp, look: look, size: .lock, snap: snap, unit: 130)
                    HomeWidgetPreview(topic: .week, look: look, size: .lock, snap: snap, unit: 130)
                }
            }
            .padding(16)
        }
        .background(LinearGradient(colors: [Color(hex: 0x1E2A55), Color(hex: 0x3A1F4D), Color(hex: 0x13121C)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .foregroundStyle(.white)
    }

    private static func topics(_ look: HomeWidgetLook) -> (small: [HomeWidgetTopic], medium: HomeWidgetTopic, large: HomeWidgetTopic) {
        switch look {
        case .gradient: ([.streak, .week], .nextUp, .dashboard)
        case .coach: ([.nextUp, .level], .nextUp, .dashboard)
        case .data: ([.readiness, .volume], .week, .dashboard)
        }
    }
}
#endif
