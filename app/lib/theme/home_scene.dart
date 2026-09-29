/// Художественная тема главного экрана. Она намеренно не зависит от города,
/// выбранного для расчёта времён молитв.
enum HomeScene {
  mecca,
  nature,
  minimal;

  static HomeScene fromStorage(String? value) => switch (value) {
    'nature' => HomeScene.nature,
    'minimal' => HomeScene.minimal,
    _ => HomeScene.mecca,
  };

  String get storageValue => name;
}
