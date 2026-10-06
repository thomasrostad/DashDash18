import SwiftUI

struct KveldView: View {
    var body: some View {
        ContentUnavailableView(
            "Ingen kveld satt opp",
            systemImage: "flag",
            description: Text("Arrangøren legger inn neste kveld i terminlisten.")
        )
    }
}

#Preview {
    NavigationStack {
        KveldView()
    }
}
