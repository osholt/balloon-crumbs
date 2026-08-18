/// How a ride uses Balloon Crumbs' group-coordination features.
enum RideCoordinationMode {
  /// One rider, with route recording and navigation but no join code or group
  /// controls.
  solo,

  /// Riders stay together as one group, without junction drop-off prompts.
  ///
  /// "Keep-together" describes the coordination policy without suggesting
  /// riders should follow at an unsafe close distance.
  keepTogether;

  bool get isGroup => this != RideCoordinationMode.solo;

  String get label => switch (this) {
    RideCoordinationMode.solo => 'Solo ride',
    RideCoordinationMode.keepTogether => 'Keep-together group',
  };

  String get description => switch (this) {
    RideCoordinationMode.solo =>
      'Navigation and ride recording for just you. No join code or group '
          'controls; you can still share a private watcher link.',
    RideCoordinationMode.keepTogether =>
      'Fly as one group with a shared join code.',
  };

  static RideCoordinationMode fromName(String? name) =>
      RideCoordinationMode.values.firstWhere(
        (mode) => mode.name == name,
        // Rides created before this choice existed were stored as
        // `secondBikeDropOff`, which no longer exists. They must degrade to a
        // group, not to solo: solo has no join code and no crew, so falling
        // back to it would silently strip a stored flight of both.
        orElse: () => RideCoordinationMode.keepTogether,
      );
}
