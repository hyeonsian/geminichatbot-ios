import SwiftUI

struct ContentView: View {
    @StateObject private var chatStore = ChatStore()
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ConversationListView()
                .environmentObject(chatStore)

            if showSplash {
                LaunchSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            guard showSplash else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.28)) {
                showSplash = false
            }
        }
    }
}

#Preview {
    ContentView()
}
