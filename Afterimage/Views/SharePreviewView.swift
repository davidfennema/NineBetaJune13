import SwiftUI
import UIKit

struct SharePreviewView: View {
    let item: SharePreviewItem
    let onDismiss: () -> Void

    @State private var showsShareSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 22) {
                    HStack {
                        AfterimageBackButton(action: onDismiss)
                        Spacer()
                    }

                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 440)
                        .background(.white.opacity(0.035))
                        .overlay {
                            Rectangle().stroke(.white.opacity(0.08), lineWidth: 1)
                        }

                    Text(item.title)
                        .font(AfterimageType.rollTitle)
                        .tracking(0.2)
                        .foregroundStyle(.white.opacity(0.94))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.74)

                    AfterimagePrimaryButton(title: "Share") {
                        withAnimation(AfterimageMotion.quick) {
                            showsShareSheet = true
                        }
                    }
                }
                .transition(AfterimageMotion.screenTransition)
                .padding(.horizontal, AfterimageLayout.margin)
                .padding(.top, AfterimageLayout.headerTopSpacing)
                .padding(.bottom, AfterimageLayout.margin)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showsShareSheet) {
            ActivityView(activityItems: [item.image])
                .ignoresSafeArea()
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
