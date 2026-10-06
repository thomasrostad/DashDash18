import SwiftUI

struct RootView: View {
    @State private var selectedTab: AppTab = .kveld

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    NavigationStack {
                        content(for: tab)
                            .navigationTitle(tab.title)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .kveld: KveldView()
        case .tavla: TavlaView()
        case .deg: DegView()
        }
    }
}

#Preview {
    RootView()
}
