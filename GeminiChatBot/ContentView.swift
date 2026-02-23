import SwiftUI

struct ContentView: View {
    @StateObject private var chatStore = ChatStore()

    var body: some View {
        ConversationListView()
            .environmentObject(chatStore)
    }
}

#Preview {
    ContentView()
}
