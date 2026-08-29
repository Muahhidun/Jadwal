/// Состояние последовательного чтения зикров.
///
/// Порядок намеренно не определяется здесь: экран получает уже проверенный
/// список из контентного файла и движется по нему без перестановок. Это даёт
/// устойчивую основу для будущего UX по референсу, не придумывая религиозную
/// или продуктовую последовательность заранее.
class ZikrReaderSession {
  ZikrReaderSession({required this.itemCount})
    : assert(itemCount > 0, 'A reader session needs at least one zikr');

  final int itemCount;

  int currentIndex = 0;
  int? speakingIndex;
  bool repeatConfirmed = false;
  final Set<int> skippedIndices = <int>{};

  bool get canGoBack => currentIndex > 0;
  bool get isLast => currentIndex == itemCount - 1;
  bool get isCurrentSpeaking => speakingIndex == currentIndex;
  bool get isCurrentSkipped => skippedIndices.contains(currentIndex);

  bool select(int index) {
    if (index < 0 || index >= itemCount || index == currentIndex) return false;
    currentIndex = index;
    speakingIndex = null;
    repeatConfirmed = false;
    return true;
  }

  /// Для зикров с несколькими повторениями переход делается в два шага:
  /// сначала напоминаем нужное количество, затем принимаем подтверждение.
  /// Это не счётчик-тасбих и не попытка считать повторения за пользователя.
  void confirmRepeat() => repeatConfirmed = true;

  /// «Пропустить» относится только к текущей карточке. Общая отметка практики
  /// остаётся доступной: она означает, что человек уделил время зикрам, а не
  /// утверждает, что выполнил каждое указанное количество повторений.
  void skipCurrent() => skippedIndices.add(currentIndex);

  /// Если пользователь вернулся к пропущенной карточке и продолжил чтение,
  /// снимаем локальный признак пропуска.
  void markCurrentRead() => skippedIndices.remove(currentIndex);

  void markCurrentSpeaking() => speakingIndex = currentIndex;

  void markPlaybackStopped() => speakingIndex = null;
}
