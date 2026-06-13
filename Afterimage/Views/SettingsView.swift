import SwiftUI

struct SettingsView: View {
    @AppStorage("afterimage.shareAttributionEnabled") private var shareAttributionEnabled = true
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: AfterimageLayout.rowSpacing) {
                    HStack {
                        AfterimageBackButton(action: onDismiss)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Settings")
                            .font(AfterimageType.screenTitle)
                            .tracking(0.2)
                        Text("Quiet preferences for exported rolls.")
                            .font(AfterimageType.body)
                            .foregroundStyle(.white.opacity(0.46))
                    }

                    Toggle(isOn: $shareAttributionEnabled) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Nine mark")
                                .font(AfterimageType.archiveTitle)
                            Text("Adds a small lab-style mark to shared exports.")
                                .font(AfterimageType.body)
                                .foregroundStyle(.white.opacity(0.46))
                        }
                    }
                    .tint(.white)
                    .padding(16)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: AfterimageLayout.controlCornerRadius, style: .continuous))
                    .animation(AfterimageMotion.quick, value: shareAttributionEnabled)

                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, AfterimageLayout.margin)
                .padding(.top, AfterimageLayout.headerTopSpacing)
                .padding(.bottom, AfterimageLayout.margin)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
