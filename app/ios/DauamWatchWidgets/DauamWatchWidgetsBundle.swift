import SwiftUI
import WidgetKit

@main
struct DauamWatchWidgetsBundle: WidgetBundle {
  var body: some Widget {
    DauamWatchPrayerComplication()
    DauamWatchTasksComplication()
  }
}
