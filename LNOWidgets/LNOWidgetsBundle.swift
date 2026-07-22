import WidgetKit
import SwiftUI

@main
struct LNOWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GlobalEquityWidget()
        FundsEquityWidget()
        PositionsWidget()
        ServiceStatusWidget()
        PnlCalendarWidget()
    }
}
