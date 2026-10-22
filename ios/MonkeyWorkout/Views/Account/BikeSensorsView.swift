import LiftSensor
import SwiftUI
import WorkoutEngine

/// Settings → Watches → Bike sensors (#623, designs A + C): FTP and its power zones, the 20′ test, and how sensors
/// pair with the Watch (power meter, cadence sensor, heart-rate strap; battery shows on the Watch).
struct BikeSensorsView: View {
    @Environment(AppModel.self) private var model
    @State private var ftp = 200

    private static let zoneColors: [UInt32] = [0x8E9BB0, 0x1E9BFF, 0x00C6A7, 0xFFD400, 0xFF8A00, 0xFF3D6E, 0x8A2BFF]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Bike sensors").font(Theme.display(34))
                Text("Power · cadence · heart rate").eyebrow()
                ftpCard
                zones
                pairing
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { ftp = model.bikeFTP ?? 200 }
    }

    private var ftpCard: some View {
        let due = BikePower.retestDue(lastTest: model.bikeFTPTestedAt, now: .now)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Your FTP").font(Theme.label(12)).tracking(1.2).textCase(.uppercase).opacity(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(ftp)").font(Theme.display(54)).monospacedDigit()
                Text("W").font(Theme.label(16))
                if let kg = model.fuelWeightKg, kg > 0 {
                    Text(String(format: "· %.1f W/kg", Double(ftp) / kg)).font(Theme.label(16)).opacity(0.85)
                }
                Spacer(minLength: 0)
                Stepper("FTP", value: $ftp, in: 50...2000, step: 5).labelsHidden()
            }
            Text(model.bikeFTPTestedAt.map { "Tested \($0.formatted(.dateTime.day().month(.abbreviated)))" + (due ? " · time to retest" : "") }
                 ?? "Not tested yet: run the 20′ FTP test on your Watch, or set it here.")
                .font(.footnote.weight(.semibold)).opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.power.gradient))
        .onChange(of: ftp) { _, v in model.setBikeFTP(v) }
    }

    private var zones: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Power zones").eyebrow()
            ForEach(BikePower.zones, id: \.index) { z in
                let r = BikePower.range(z, ftp: ftp)
                HStack(spacing: 10) {
                    Text("Z\(z.index)").font(Theme.display(18)).frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.22)))
                    Text(z.name).font(Theme.label(15))
                    Spacer(minLength: 0)
                    Text(z.upTo == nil ? "\(r.lowerBound)+ W" : "\(r.lowerBound)–\(r.upperBound) W").font(Theme.display(16)).monospacedDigit()
                }
                .foregroundStyle(z.index == 4 ? Theme.ink : .white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: Self.zoneColors[z.index - 1])))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On your Apple Watch").eyebrow()
            step("1", "Track a sport → Road bike or MTB → Sensors: pick your power meter, cadence sensor and heart-rate strap. Battery shows next to each.")
            step("2", "Ride: watts big, 3″ average, your zone, cadence and heart rate.")
            step("3", "FTP test: 15′ warm-up, 20′ all out, 10′ easy. 95 % of your 20′ average becomes your FTP and the zones follow. Retest every 6 weeks.")
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(Theme.display(16)).foregroundStyle(Theme.ink).frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.lime))
            Text(text).font(.subheadline).foregroundStyle(.white)
        }
    }
}
