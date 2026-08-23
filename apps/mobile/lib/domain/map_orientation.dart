enum MapOrientationMode {
  northUp,
  directionUp;

  String get label => switch (this) {
    MapOrientationMode.northUp => 'North up',
    MapOrientationMode.directionUp => 'Direction up',
  };

  MapOrientationMode get toggled => switch (this) {
    MapOrientationMode.northUp => MapOrientationMode.directionUp,
    MapOrientationMode.directionUp => MapOrientationMode.northUp,
  };
}
