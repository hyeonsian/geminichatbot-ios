import SwiftUI

struct LaunchSplashView: View {
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.96, blue: 1.0),
                    Color(red: 0.85, green: 0.92, blue: 1.0),
                    Color(red: 0.90, green: 0.97, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 108, height: 108)
                        .blur(radius: 0.3)
                        .scaleEffect(pulse ? 1.05 : 0.94)

                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color.blue,
                                    Color.cyan,
                                    Color.green,
                                    Color.blue
                                ],
                                center: .center
                            ),
                            lineWidth: 8
                        )
                        .frame(width: 84, height: 84)
                        .rotationEffect(.degrees(spin ? 360 : 0))

                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 6) {
                    Text("Language Coach")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Chat. Learn. Sound Natural.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .tracking(0.2)
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                spin = true
            }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

#Preview {
    LaunchSplashView()
}
