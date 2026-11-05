import SwiftUI
import WorkoutEngine

// MARK: - My app (#1052, design A + B from `usage-levels/a.png` + `b.png`)

extension AppModule {
    /// Card colours, same family as the tabs.
    var category: WorkoutEngine.Category {
        switch self {
        case .plan: .cardio
        case .coach: .warmup
        case .insights: .power
        case .game: .stretch
        case .sports: .mobility
        case .mind: .power
        case .fuel: .warmup
        case .social: .mobility
        case .camera: .cardio
        }
    }
}

extension AppLevel {
    var category: WorkoutEngine.Category {
        switch self {
        case .workouts: .strength
        case .plan: .cardio
        case .everything: .power
        }
    }
}

/// Three big level cards (A): sign up and the top of My app.
struct AppLevelPicker: View {
    let selected: AppLevel?
    let pick: (AppLevel) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(AppLevel.allCases.enumerated()), id: \.element) { i, level in
                Button { pick(level) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: level.symbol)
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(level.title).font(Theme.display(19))
                            Text(level.detail).font(.footnote.weight(.semibold)).opacity(0.85)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        Text("\(i + 1)").font(Theme.display(28))
                    }
                    .foregroundStyle(level.category.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(level.category.gradient))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white, lineWidth: selected == level ? 3 : 0))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == level ? .isSelected : [])
                .accessibilityIdentifier("level.\(level.rawValue)")
            }
        }
    }
}

/// Settings › My app: the level (A) and a grid of modules (B). Workouts always on.
struct MyAppView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let modules = model.appModules
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AccountHeader(symbol: "slider.horizontal.3", title: "My app",
                              subtitle: "Keep only what you use. Off hides its tab, cards, buttons and prompts; nothing is deleted.",
                              gradient: SettingsChapter.look.gradient)
                Text("Level").eyebrow().padding(.leading, 4)
                AppLevelPicker(selected: modules.level) { level in
                    withAnimation(.snappy) { model.setAppLevel(level) }
                }
                Text("Modules").eyebrow().padding(.leading, 4).padding(.top, 6)
                LazyVGrid(columns: columns, spacing: 10) {
                    workoutsTile
                    ForEach(AppModule.allCases) { module in tile(module, on: modules.shows(module)) }
                }
            }
            .padding(16)
            .readableWidth()
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("My app")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var workoutsTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "dumbbell.fill").font(.system(size: 17, weight: .bold))
            Text("Workouts").font(Theme.display(16))
            Text("Always on").font(.caption.weight(.semibold)).opacity(0.85)
            Spacer(minLength: 0)
            HStack { Spacer(); Image(systemName: "lock.fill").font(.subheadline.weight(.bold)) }
        }
        .foregroundStyle(WorkoutEngine.Category.strength.ink)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
        .accessibilityElement(children: .combine)
    }

    private func tile(_ module: AppModule, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: module.symbol).font(.system(size: 17, weight: .bold))
            Text(module.title).font(Theme.display(16)).lineLimit(2).minimumScaleFactor(0.8)
            Text(on ? module.detail : "Off · data kept").font(.caption.weight(.semibold)).opacity(0.85).lineLimit(2)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Toggle(module.title, isOn: Binding(get: { on }, set: { v in
                    withAnimation(.snappy) { model.setModule(module, on: v) }
                }))
                .labelsHidden()
                .tint(.white.opacity(0.9))
                .accessibilityIdentifier("module.\(module.rawValue)")
            }
        }
        .foregroundStyle(on ? module.category.ink : Theme.muted)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(on ? AnyShapeStyle(module.category.gradient) : AnyShapeStyle(Color.white.opacity(0.08))))
    }
}
