import SwiftUI

struct SettingsView: View {
    @AppStorage("nine.shareAttributionEnabled") private var shareAttributionEnabled = true
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: NineLayout.rowSpacing) {
                    HStack {
                        NineBackButton(action: onDismiss)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Settings")
                            .font(NineType.screenTitle)
                            .tracking(0.2)
                        Text("Quiet preferences for exported rolls.")
                            .font(NineType.body)
                            .foregroundStyle(.white.opacity(0.46))
                    }

                    Toggle(isOn: $shareAttributionEnabled) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Nine mark")
                                .font(NineType.archiveTitle)
                            Text("Adds a small lab-style mark to shared exports.")
                                .font(NineType.body)
                                .foregroundStyle(.white.opacity(0.46))
                        }
                    }
                    .tint(.white)
                    .padding(16)
                    .nineCardSurface()
                    .animation(NineMotion.quick, value: shareAttributionEnabled)

                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, NineLayout.horizontalScreenMargin)
                .padding(.top, NineLayout.headerTopSpacing)
                .padding(.bottom, NineLayout.margin)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
