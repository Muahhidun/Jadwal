import 'package:flutter/widgets.dart';

enum GuideStep {
  idle,
  welcome,
  day,
  times,
  deeds,
  add,
  remindersAdd,
  editorPaused,
  prayer,
  clock,
  formDone,
  calendarSwipe,
  calendar,
  appearance,
  appearanceSettings,
  appearancePicker,
  returnDay,
  returnHome,
  qibla,
  finish,
  qiblaMap,
}

/// Only tutorial progress. Never changes a task, city, layout or permission.
class NavigationGuide extends ChangeNotifier {
  GuideStep step = GuideStep.idle;
  bool pages = false;
  bool moving = false;
  GuideStep? _afterEditor;
  final Map<String, GlobalKey> _targets = {};
  GlobalKey target(String id) => _targets.putIfAbsent(id, () => GlobalKey());
  bool get active => step != GuideStep.idle;
  bool get inModal =>
      inForm ||
      const {
        GuideStep.editorPaused,
        GuideStep.appearanceSettings,
        GuideStep.appearancePicker,
      }.contains(step);
  bool get inForm => const {
    GuideStep.prayer,
    GuideStep.clock,
    GuideStep.formDone,
  }.contains(step);
  int? get expectedPage => switch (step) {
    GuideStep.day || GuideStep.qibla => 0,
    GuideStep.times ||
    GuideStep.deeds ||
    GuideStep.add ||
    GuideStep.calendarSwipe ||
    GuideStep.returnHome => 1,
    GuideStep.calendar || GuideStep.appearance || GuideStep.returnDay => 2,
    GuideStep.finish || GuideStep.qiblaMap => -1,
    _ => null,
  };

  void go(GuideStep next) {
    if (next == GuideStep.idle || next == GuideStep.welcome) moving = false;
    if (step == next) return;
    step = next;
    notifyListeners();
  }

  void offer() => go(GuideStep.welcome);
  void navigationStarted() {
    if (!active || moving) return;
    moving = true;
    notifyListeners();
  }

  void begin({required bool usePages}) {
    moving = false;
    _afterEditor = null;
    pages = true;
    go(GuideStep.day);
  }

  void beginReminder() {
    moving = false;
    go(GuideStep.prayer);
  }

  /// A real editor is a detour, not completion of the main lesson. The
  /// continuation survives skipping/finishing its separate optional tutorial.
  void pauseForEditor() {
    if (!active || inModal) return;
    _afterEditor = step == GuideStep.add ? GuideStep.calendarSwipe : step;
    go(GuideStep.editorPaused);
  }

  void settled(int page) {
    final wasMoving = moving;
    moving = false;
    final previous = step;
    if (step == GuideStep.day && page == 1) go(GuideStep.times);
    if (step == GuideStep.calendarSwipe && page == 2) go(GuideStep.calendar);
    if (step == GuideStep.returnDay && page == 1) go(GuideStep.returnHome);
    if (step == GuideStep.returnHome && page == 0) go(GuideStep.qibla);
    if (step == GuideStep.qibla && page == -1) go(GuideStep.finish);
    // An optional lesson must not remain invisibly active after the user
    // deliberately leaves its route in the other direction.
    if (expectedPage != null && expectedPage != page) go(GuideStep.idle);
    if (wasMoving && step == previous) notifyListeners();
  }

  void editorClosed() {
    final resume = _afterEditor;
    _afterEditor = null;
    if (resume != null) {
      go(resume);
    } else if (inForm || step == GuideStep.editorPaused) {
      go(GuideStep.idle);
    }
  }

  void showCalendar() => go(GuideStep.calendarSwipe);
}
