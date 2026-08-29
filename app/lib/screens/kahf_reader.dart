import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/app_state.dart';
import '../theme/system_bars.dart';
import '../theme/tokens.dart';
import 'reader_palette.dart';

/// Постраничная читалка суры аль-Кахф в раскладке мединского мусхафа.
///
/// Коранический текст и построчная разметка загружаются напрямую с
/// Quran Foundation во время чтения. Мы намеренно не копируем и не правим
/// текст внутри приложения: локально хранятся только оболочка и настройки.
class KahfReaderScreen extends StatefulWidget {
  const KahfReaderScreen({super.key});

  @override
  State<KahfReaderScreen> createState() => _KahfReaderScreenState();
}

class _KahfReaderScreenState extends State<KahfReaderScreen> {
  late final WebViewController _controller;
  bool _pageReady = false;
  bool _chromeVisible = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'DauamReader',
        onMessageReceived: (message) {
          if (!mounted || message.message != 'toggleChrome') return;
          setState(() => _chromeVisible = !_chromeVisible);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _pageReady = true);
            _syncAppearance();
          },
        ),
      )
      ..loadFlutterAsset('assets/quran/kahf_reader.html');
  }

  Future<void> _syncAppearance() async {
    if (!_pageReady || !mounted) return;
    final app = AppScope.of(context);
    await _controller.runJavaScript(
      'window.setReaderAppearance('
      '${jsonEncode(app.readerPalette)});',
    );
  }

  void _selectPalette(AppState app, ReaderPalette selected) {
    app.readerPalette = selected.id;
    _syncAppearance();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final palette = ReaderPalette.fromId(app.readerPalette);
    final kz = app.lang == 'kz';
    _syncAppearance();

    return JSystemBars(
      darkIcons: !palette.isDark,
      child: Scaffold(
        backgroundColor: palette.bg,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              WebViewWidget(controller: _controller),
              if (!_pageReady)
                ColoredBox(
                  color: palette.bg,
                  child: Center(
                    child: CircularProgressIndicator(color: palette.accent),
                  ),
                ),
              AnimatedSlide(
                offset: _chromeVisible ? Offset.zero : const Offset(0, -1.08),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Material(
                    color: palette.bg,
                    elevation: 10,
                    shadowColor: Colors.black.withValues(alpha: .2),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: kz ? 'Жабу' : 'Закрыть',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: Icon(Icons.close, color: palette.source),
                              ),
                              Expanded(
                                child: Text(
                                  kz ? '«әл-Кәһф» сүресі' : 'Сура аль-Кахф',
                                  textAlign: TextAlign.center,
                                  style: JType.ui(
                                    17,
                                    w: FontWeight.w700,
                                    color: palette.ink,
                                  ),
                                ),
                              ),
                              IconButton(
                                key: const ValueKey('kahf-complete-action'),
                                tooltip: app.isDone('kahf')
                                    ? (kz ? 'Оқылды' : 'Прочитано')
                                    : (kz
                                          ? 'Оқылды деп белгілеу'
                                          : 'Отметить прочитанной'),
                                onPressed: app.isDone('kahf')
                                    ? null
                                    : () => app.markDone('kahf'),
                                icon: Icon(
                                  app.isDone('kahf')
                                      ? Icons.check_circle
                                      : Icons.check_circle_outline,
                                  color: app.isDone('kahf')
                                      ? palette.accent
                                      : palette.source,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final option in ReaderPalette.values)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                  ),
                                  child: Tooltip(
                                    message: option.title(app.lang),
                                    child: Semantics(
                                      button: true,
                                      selected: option.id == palette.id,
                                      label: option.title(app.lang),
                                      child: InkResponse(
                                        key: ValueKey(
                                          'kahf-palette-${option.id}',
                                        ),
                                        radius: 24,
                                        onTap: () =>
                                            _selectPalette(app, option),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 160,
                                          ),
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: option.bg,
                                            border: Border.all(
                                              color: option.id == palette.id
                                                  ? palette.accent
                                                  : option.divider,
                                              width: option.id == palette.id
                                                  ? 3
                                                  : 1,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            'ا',
                                            style: TextStyle(
                                              color: option.arabic,
                                              fontFamily: 'Amiri',
                                              fontSize: 20,
                                              height: 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
