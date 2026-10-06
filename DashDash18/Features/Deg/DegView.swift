import SwiftUI

struct DegView: View {
    var body: some View {
        ContentUnavailableView(
            "Ikke logget inn",
            systemImage: "person.crop.circle",
            description: Text("Innlogging kommer snart.")
        )
    }
}

#Preview {
    NavigationStack {
        DegView()
    }
}
