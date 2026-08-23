/// What a person is doing on a flight.
///
/// A role belongs to a device, and the device is attached to a craft. The two
/// are deliberately separate: "which craft am I on" and "what is my job" are
/// different questions, and the inherited `RideRole` conflated them into a flat
/// list of riders. A crew member in the basket and the pilot beside them share a
/// craft and hold different roles; two drivers in different vehicles share a role
/// and hold different crafts.
enum FlightRole {
  /// Flies the balloon. Exactly one per flight, and the only role that can start
  /// or end it. Not necessarily the device reporting the balloon's position —
  /// a pilot with both hands on the burner is usually not the one holding a
  /// phone, which is the whole reason craft telemetry is elected rather than
  /// assigned.
  pilot,

  /// In the basket, not flying. Often the person actually operating the app.
  balloonCrew,

  /// Driving a chase vehicle. The role that must never be asked to look at a
  /// screen, and the only one that sees road furniture — speed limits, camera and
  /// enforcement alerts belong here and nowhere else.
  chaseDriver,

  /// In a chase vehicle, not driving. Can read, type and plan; this is who the
  /// detailed chase surfaces are for.
  chaseCrew,

  /// Read-only, time-bounded, reduced precision. Family watching from home.
  observer,
}

extension FlightRoleLabel on FlightRole {
  String get label => switch (this) {
    FlightRole.pilot => 'Pilot',
    FlightRole.balloonCrew => 'Balloon crew',
    FlightRole.chaseDriver => 'Driver',
    FlightRole.chaseCrew => 'Chase crew',
    FlightRole.observer => 'Observer',
  };

  /// Whether this role is in the basket rather than on the ground.
  bool get isAboardBalloon =>
      this == FlightRole.pilot || this == FlightRole.balloonCrew;

  /// Whether this role is in a chase vehicle.
  bool get isChasing =>
      this == FlightRole.chaseDriver || this == FlightRole.chaseCrew;

  /// Whether road furniture — speed limits, cameras, enforcement alerts — should
  /// be shown. Only the person driving, and never in the basket: a camera
  /// warning is noise to a pilot and attention taken from flying.
  bool get seesRoadFurniture => this == FlightRole.chaseDriver;

  /// Whether this role holds pilot-only authority over the balloon and shared
  /// forecast. Starting live recovery is deliberately a separate permission:
  /// field testing showed that the ground crew are the people free to do it at
  /// release, while the pilot is occupied with the aircraft.
  bool get hasFlightAuthority => this == FlightRole.pilot;

  /// Whether this role may begin live tracking when the balloon is released.
  ///
  /// The pilot remains a fallback for compatibility and unusual operations,
  /// but both chase roles can take the normal field action. Balloon crew stay
  /// out of this path for the same workload reason as the pilot, and observers
  /// are always read-only.
  bool get mayStartFlight => hasFlightAuthority || isChasing;

  /// Whether this role may publish shared landing/recovery state.
  ///
  /// Field evidence can come from the basket, a witness or radio traffic, so
  /// every operational role is allowed while observers remain read-only.
  bool get mayManageRecovery => this != FlightRole.observer;
}

/// Reads a role name that another build may have written.
///
/// Degrades to [FlightRole.observer] rather than throwing. Observer is the safe
/// default because it is the least privileged: an unrecognised role must not
/// silently acquire flight authority or be trusted to report the balloon.
FlightRole flightRoleFromName(
  Object? value, {
  FlightRole fallback = FlightRole.observer,
}) {
  if (value is! String) return fallback;
  for (final role in FlightRole.values) {
    if (role.name == value) return role;
  }
  return fallback;
}
