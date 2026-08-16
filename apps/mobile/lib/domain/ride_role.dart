enum RideRole { lead, rider, marker }

extension RideRoleLabel on RideRole {
  String get label => switch (this) {
    RideRole.lead => 'Lead',
    RideRole.rider => 'Rider',
    RideRole.marker => 'Marker',
  };
}

/// Reads a role name that may have been written by another build.
///
/// `RideRole.values.byName` throws on a name this build does not know, which is
/// the wrong answer for a value that arrives from a peer's relayed state or
/// from this phone's own stored session. The sweep-rider role `tailEndCharlie`
/// was removed with the Tail End Charlie migration, so a peer on an older build
/// still publishes it and an install that predates the removal still has it
/// saved — both must degrade to an ordinary rider rather than fail to parse.
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
