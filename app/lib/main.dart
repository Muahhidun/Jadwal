import 'package:flutter/material.dart';
import 'data/app_state.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.load();
  runApp(JadwalApp(state: state));
}

class JadwalApp extends StatelessWidget {
  const JadwalApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'Jadwal',
          debugShowCheckedModeBanner: false,
          themeMode: state.themeMode,
          theme: _theme(JColors.light, Brightness.light),
          darkTheme: _theme(JColors.dark, Brightness.dark),
          home: state.onboardingDone ? const HomeScreen() : const OnboardingScreen(),
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
