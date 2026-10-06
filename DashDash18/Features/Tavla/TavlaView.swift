import SwiftUI

struct TavlaView: View {
    var body: some View {
        ContentUnavailableView(
            "Ingen runder spilt",
            systemImage: "trophy",
            description: Text("Tabellen fylles når sesongens første kveld er spilt.")
        )
    }
}

#Preview {
    NavigationStack {
        TavlaView()
    }
}
