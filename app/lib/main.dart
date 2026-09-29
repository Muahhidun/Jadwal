import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/app_state.dart';
import 'notifications/notifications.dart';
import 'prayer/schedule_service.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';
import 'theme/tokens.dart';
import 'theme/system_bars.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Онбординг показывается только при первой установке. Раньше здесь был
  // ручной сброс по метке сборки для проверки — перед релизом убран, чтобы
  // обновление из магазина не показывало онбординг заново.
  final state = await AppState.load();
  final schedule = ScheduleService(prefs);
  final notifier = NotificationService(schedule);
  gNotifier = notifier;
  await notifier.init(lang: state.lang);
  runApp(JadwalApp(state: state, schedule: schedule));
}

class JadwalApp extends StatelessWidget {
  const JadwalApp({super.key, required this.state, required this.schedule});
  final AppState state;
  final ScheduleService schedule;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ScheduleScope(
        service: schedule,
        child: ListenableBuilder(
          listenable: Listenable.merge([state, schedule]),
          builder: (context, _) => MaterialApp(
            title: 'Dauam',
            debugShowCheckedModeBanner: false,
            themeMode: state.themeMode,
            theme: _theme(JColors.light, Brightness.light),
            darkTheme: _theme(JColors.dark, Brightness.dark),
            builder: (context, child) => JSystemBars(
              darkIcons: Theme.of(context).brightness == Brightness.light,
              child: child ?? const SizedBox.shrink(),
            ),
            home: state.onboardingDone
                ? const HomeScreen()
                : const OnboardingScreen(),
          ),
        ),
      ),
    );
  }

  ThemeData _theme(JColors c, Brightness b) => ThemeData(
    brightness: b,
    scaffoldBackgroundColor: c.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: c.gold, brightness: b),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}
