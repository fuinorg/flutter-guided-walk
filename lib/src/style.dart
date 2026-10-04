/// The few measures the walk's panel is drawn with, so it needs nothing of the app it walks through.
abstract final class WalkSpace {
  /// Between lines that belong together.
  static const tight = 4.0;

  /// Around a box.
  static const small = 8.0;

  /// Beside words in a box.
  static const normal = 12.0;
}

/// How round the panel's boxes are.
abstract final class WalkRadii {
  /// A box's corners.
  static const small = 8.0;
}
