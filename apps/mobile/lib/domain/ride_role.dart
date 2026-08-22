enum RideRole { lead, rider }

extension RideRoleLabel on RideRole {
  String get label => switch (this) {
    RideRole.lead => 'Pilot',
    RideRole.rider => 'Chaser',
  };
}

/// Reads a role name that may have been written by another build.
///
/// `RideRole.values.byName` throws on a name this build does not know, which is
/// the wrong answer for a value that arrives from a peer's relayed state or
/// from this phone's own stored session. The sweep-rider role `tailEndCharlie`
/// and the junction-marker role `marker` were both removed with the motorcycle
/// domain, so a peer on an older build still publishes them and an install that
/// predates the removal still has one saved — all must degrade to an ordinary
/// rider rather than fail to parse.
///
/// The journal reducers already guard `byName` and drop an unknown role to
/// null; this is for the callers that need a role rather than an absence.
RideRole rideRoleFromName(Object? value, {RideRole fallback = RideRole.rider}) {
  if (value is! String) return fallback;
  for (final role in RideRole.values) {
    if (role.name == value) return role;
  }
  return fallback;
}
