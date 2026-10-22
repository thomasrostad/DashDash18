import SwiftUI

/// «Utseende» under Deg: System, Lys eller Mørk. Valget gjelder bare på denne telefonen.
struct DegAppearanceSection: View {
    @AppStorage(AppearanceMode.storageKey) private var stored = AppearanceMode.system.rawValue

    var body: some View {
        Section {
            Picker("Utseende", selection: $stored) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            DDHeader("Utseende")
        } footer: {
            DDFooter("System følger telefonen. Tavla på TV er alltid mørk.")
        }
    }
}
