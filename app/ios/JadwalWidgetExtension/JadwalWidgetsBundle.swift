import WidgetKit
import SwiftUI

@main
struct JadwalWidgetsBundle: WidgetBundle {
  @WidgetBundleBuilder
  var body: some Widget {
    if #available(iOS 17.0, *) {
      DauamPrayerWidget()
      DauamTasksWidget()
    }
    if #available(iOS 16.0, *) {
      DauamAccessoryWidget()
      DauamAccessoryFullTimerWidget()
      DauamAccessoryWorshipWidget()
    }
    if #available(iOS 16.1, *) {
      JadwalLiveActivity()
    }
  }
}
