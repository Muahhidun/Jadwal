/// Художественная тема главного экрана. Она намеренно не зависит от города,
/// выбранного для расчёта времён молитв.
enum HomeScene {
  mecca,
  nature,
  minimal,
  ornament;

  static HomeScene fromStorage(String? value) => switch (value) {
    'nature' => HomeScene.nature,
    'minimal' => HomeScene.minimal,
    'ornament' => HomeScene.ornament,
    _ => HomeScene.mecca,
  };

  String get storageValue => name;
}
