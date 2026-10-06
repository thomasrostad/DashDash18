import SwiftUI
import WidgetKit

/// Alt widget-targetet viser: Live Activity under runden, neste kveld og topp 3 på Tavla.
@main
struct DashDash18WidgetBundle: WidgetBundle {
    var body: some Widget {
        RoundLiveActivityWidget()
        NextEveningWidget()
        TopThreeWidget()
    }
}
