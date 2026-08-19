/// Route preferences: what kind of road, and what size of vehicle.
///
/// This file used to open by declaring itself the Dart half of a contract with
/// `apps/website/planner-core.mjs`, pinned to it by tests on both sides and
/// documented in `docs/route-twistiness.md`. None of those files exist, and none
/// ever have in this repository — they belong to Tail End Charlie, which was
/// never brought across. The claim cost real time to disprove, so it is written
/// down here plainly: this is the only implementation, and it is free to change
/// without renegotiating anything.
///
/// Preferences belong to the route, not to the device: they travel with the
/// route record and through its GPX, so a route shared into a flight still says
/// what it was planned for, and for what vehicle.
library;

import 'chase_vehicle.dart';

export 'chase_vehicle.dart';

/// What kind of road the route should favour.
///
/// This replaces a ladder of detour tolerance bought with bends — quickest,
/// flowing (+25%), twisty (+50%), very twisty (+75%) — inherited from an app
/// where finding corners was the entire point. A chase crew is trying to be
/// underneath a balloon when it lands. Spending 75% more time on the road for
/// entertainment is not a preference they have, and biasing a vehicle that is
/// towing off main roads and onto lanes does not merely slow it down, it can
/// stop it getting there at all.
///
/// Two options, because there is a real choice underneath: the fastest line, or
/// main roads even when they are slightly longer. The second is what a driver
/// towing a trailer usually wants, and it is a preference rather than a
/// consequence of the trailer, which is why it lives here and not on
/// [ChaseVehicle].
enum RouteStyle {
  /// The default. Fastest way there, no opinion about road class.
  direct('direct', 'Direct — fastest way there'),

  /// Favour trunk and primary roads, and accept a modest detour to stay on
  /// them. Wide lanes, gentle bends, predictable junctions: easier with a
  /// trailer, and far easier when the driver is watching a balloon rather than
  /// the map.
  majorRoads('major-roads', 'Prefer major roads');

  const RouteStyle(this.apiValue, this.label);

  /// The value written to JSON, GPX and provider requests.
  ///
  /// The four inherited values (`quickest`, `balanced`, `twisty`,
  /// `very-twisty`) are gone from this enum but may still be sitting in stored
  /// routes, so [fromApiValue] has to keep answering for them. See there.
  final String apiValue;
  final String label;

  /// Valhalla `use_highways` for this style.
  double get highwayPreference => switch (this) {
    RouteStyle.direct => 1,
    RouteStyle.majorRoads => 1,
  };

  /// Valhalla `use_living_streets`. Residential streets and home zones are
  /// where a long vehicle gets stuck and where children play; a route that
  /// prefers major roads should not thread through them.
  double get livingStreetPreference => switch (this) {
    RouteStyle.direct => 0.5,
    RouteStyle.majorRoads => 0,
  };

  /// Reads a stored style, degrading anything unrecognised to [direct].
  ///
  /// The four motorcycle styles resolve here, and they all resolve to [direct]
  /// rather than to the nearest-looking survivor. A route stored as `twisty`
  /// asked for a 50% detour in exchange for corners; there is no honest
  /// translation of that into a chase preference, and inventing one would apply
  /// a bias to somebody's route that they never chose for this vehicle. The
  /// route itself is unchanged — only what a re-plan would ask for.
  static RouteStyle? fromApiValue(Object? value) =>
      RouteStyle.values.where((style) => style.apiValue == value).firstOrNull ??
      (value is String && _retiredStyles.contains(value)
          ? RouteStyle.direct
          : null);

  static const _retiredStyles = {
    'quickest',
    'balanced',
    'twisty',
    'very-twisty',
  };
}

/// What to do about byways open to all traffic and other unsurfaced roads.
///
/// A byway open to all traffic is a *legal* designation - OpenStreetMap records
/// it as `designation=byway_open_to_all_traffic` - and it says nothing at all
/// about what the surface is made of. Many BOATs are rutted, and some are
/// asphalt. So the preference is expressed against the surface tagging that
/// OpenStreetMap actually carries (`surface=*`, and `highway=track` for a way
/// mapped as a track), never inferred from the road's classification. That is
/// also why the option is named for the surface rather than for the legal
/// designation.
enum BywaySurfacePreference {
  /// The default. See `docs/route-twistiness.md` for the reasoning.
  avoidUnsurfaced('avoid-unsurfaced', 'Avoid unsurfaced byways'),

  /// For a trail rider who wants them: the road route may use ways
  /// OpenStreetMap tags as unsurfaced or as a track.
  allowUnsurfaced('allow-unsurfaced', 'Allow unsurfaced byways and tracks');

  const BywaySurfacePreference(this.apiValue, this.label);

  final String apiValue;
  final String label;

  bool get avoidsUnsurfaced => this == BywaySurfacePreference.avoidUnsurfaced;

  static BywaySurfacePreference? fromApiValue(Object? value) =>
      BywaySurfacePreference.values
          .where((preference) => preference.apiValue == value)
          .firstOrNull;
}

/// The route character a rider asked for.
class RoutePreferences {
  const RoutePreferences({
    this.style = RouteStyle.direct,
    this.avoidMotorways = false,
    this.avoidMajorRoads = false,
    this.avoidTolls = false,
    this.avoidFerries = false,
    this.bywaySurface = BywaySurfacePreference.avoidUnsurfaced,
    this.vehicle = ChaseVehicle.unspecified,
  });

  static const RoutePreferences defaults = RoutePreferences();

  final RouteStyle style;

  /// Excludes motorways outright, rather than merely making them expensive.
  final bool avoidMotorways;

  /// The quieter-road option: trunk and primary roads are heavily penalised but
  /// not excluded, because excluding them strands most UK routes.
  final bool avoidMajorRoads;
  final bool avoidTolls;
  final bool avoidFerries;
  final BywaySurfacePreference bywaySurface;

  /// The vehicle these roads have to fit. Unspecified by default, in which case
  /// nothing physical is asserted and the route is planned as a car.
  final ChaseVehicle vehicle;

  bool get isDefault => this == defaults;

  /// Whether these preferences need Valhalla's costing rather than the plain
  /// OSRM driving profile.
  ///
  /// This is the web planner's `requestRoadRoute` rule, extended for byways.
  /// The four avoidances are hard exclusions OSRM's driving profile cannot
  /// express. [BywaySurfacePreference.allowUnsurfaced] is on the list for the
  /// opposite reason: OSRM's standard car profile does not route
  /// `highway=track` at all, so *seeking* byways is the case OSRM cannot serve.
  /// Avoiding them is the case it already serves, which is why the default
  /// preference does not force every route onto the Valhalla service.
  bool get requiresValhallaCosting =>
      avoidMotorways ||
      avoidMajorRoads ||
      avoidTolls ||
      avoidFerries ||
      !bywaySurface.avoidsUnsurfaced ||
      style == RouteStyle.majorRoads ||
      vehicle.requiresTruckCosting;

  /// Whether tight bends are a problem for this vehicle, so the router should
  /// be asked for alternatives and given the straightest one it can afford.
  ///
  /// Driven by [ChaseVehicle.towing] alone, not by the dimensions. A trailer is
  /// the thing that makes a sharp bend into a manoeuvre, and it is stated
  /// explicitly rather than guessed from a length — "5 m long" describes an
  /// ordinary estate car, and inferring a bend aversion from it would apply one
  /// to most of the fleet.
  ///
  /// The bend score doing the work here is the one the motorcycle build used to
  /// *seek* corners, read the other way round. That inversion is the whole of
  /// the change: the measurement was always sound, it was the sign that belonged
  /// to a different app.
  bool get prefersStraighterRoads => vehicle.towing;

  /// How much longer a straighter route may take before it stops being worth
  /// having: 15%, and not a fraction more.
  ///
  /// A property of the trailer rather than of the road style, which is what the
  /// inherited model got wrong. Detour tolerance used to hang off the style, so
  /// the default style allowed 0% — and a crew who ticked "towing" got a
  /// preference that could never once change the route they were given. It went
  /// unnoticed because the field was still there and still being read.
  ///
  /// 15% because the deadline is physical. A balloon comes down when it comes
  /// down, and a crew cannot spend twenty minutes avoiding corners to arrive
  /// after it has landed in somebody's wheat.
  static const towingDetourLimit = 1.15;

  /// Which Valhalla costing model plans this route.
  ///
  /// `truck` only once the crew has entered a dimension, because that is the
  /// only thing `truck` can do that `auto` cannot: read `maxheight`,
  /// `maxweight` and `maxwidth`. Switching on the strength of a ticked "towing"
  /// box would apply Valhalla's articulated-lorry defaults to a vehicle nobody
  /// described. See [ChaseVehicle.requiresTruckCosting].
  String get valhallaCosting => vehicle.requiresTruckCosting ? 'truck' : 'auto';

  /// `costing_options` for [valhallaCosting], keyed as Valhalla expects.
  Map<String, Object?> valhallaCostingOptions() => {
    valhallaCosting: {
      ...valhallaRoadCostingOptions(),
      if (vehicle.requiresTruckCosting) ...vehicle.valhallaTruckDimensions(),
    },
  };

  /// Valhalla `costing_options.auto`.
  ///
  /// The numbers came from `motorcycleCostingOptions` in the web planner's
  /// `planner-core.mjs` and the two were deliberately identical. They are not any
  /// more: a chase vehicle is a Land Rover or a van, often towing, so it is
  /// routed with `auto` costing rather than `motorcycle`. Until the web planner
  /// follows, the two surfaces ask the same engine slightly different questions.
  ///
  /// `use_tracks` rather than `use_trails`: they are the same idea under
  /// different names, and Valhalla only accepts the former under `auto`. It is
  /// the option that matters most here — a landing field is usually reached down
  /// a farm track, and `auto` defaults to avoiding them, so a crew that has not
  /// asked to avoid unsurfaced ways must have tracks opened back up explicitly.
  ///
  /// `exclude_unpaved` and `use_tracks` both derive from OpenStreetMap surface
  /// and track tagging, which is what makes the byway preference honour the tags
  /// instead of guessing from road class.
  Map<String, Object?> valhallaRoadCostingOptions() => {
    // An explicit "avoid major roads" beats the style: it is a hard instruction
    // the crew typed, where the style is a leaning.
    'use_highways': avoidMajorRoads ? 0.08 : style.highwayPreference,
    'use_living_streets': style.livingStreetPreference,
    'use_tolls': avoidTolls ? 0 : 0.5,
    'use_ferry': avoidFerries ? 0 : 0.5,
    'use_tracks': bywaySurface.avoidsUnsurfaced ? 0 : 0.5,
    'exclude_highways': avoidMotorways,
    'exclude_tolls': avoidTolls,
    'exclude_ferries': avoidFerries,
    'exclude_unpaved': bywaySurface.avoidsUnsurfaced,
  };

  /// One sentence a rider can check the route against, in the same order and
  /// wording as the web planner's status line.
  List<String> get appliedNotes => [
    if (style == RouteStyle.majorRoads) 'Major roads preferred',
    if (avoidMotorways) 'motorways excluded',
    if (avoidMajorRoads) 'major roads avoided',
    if (avoidTolls) 'tolls excluded',
    if (avoidFerries) 'ferries excluded',
    if (bywaySurface.avoidsUnsurfaced)
      'unsurfaced byways avoided'
    else
      'unsurfaced byways allowed',
    // Last, and only when entered. A crew reading the summary back needs to see
    // the numbers being routed against, because a wrong height here is not a
    // preference that produces a duller route, it is one that produces a route
    // through a bridge.
    ...vehicle.appliedNotes,
  ];

  /// The rider-facing summary. Never empty: the byway preference always says
  /// which way round it is, because "we did not avoid them" and "we avoided
  /// them" are the difference between a Fireblade and a rutted BOAT.
  String get summary {
    final notes = appliedNotes;
    if (notes.isEmpty) return 'Direct route.';
    final joined = notes.join(', ');
    return '${joined[0].toUpperCase()}${joined.substring(1)}.';
  }

  RoutePreferences copyWith({
    RouteStyle? style,
    bool? avoidMotorways,
    bool? avoidMajorRoads,
    bool? avoidTolls,
    bool? avoidFerries,
    BywaySurfacePreference? bywaySurface,
    ChaseVehicle? vehicle,
  }) => RoutePreferences(
    style: style ?? this.style,
    avoidMotorways: avoidMotorways ?? this.avoidMotorways,
    avoidMajorRoads: avoidMajorRoads ?? this.avoidMajorRoads,
    avoidTolls: avoidTolls ?? this.avoidTolls,
    avoidFerries: avoidFerries ?? this.avoidFerries,
    bywaySurface: bywaySurface ?? this.bywaySurface,
    vehicle: vehicle ?? this.vehicle,
  );

  Map<String, Object?> toJson() => {
    'style': style.apiValue,
    'avoidMotorways': avoidMotorways,
    'avoidMajorRoads': avoidMajorRoads,
    'avoidTolls': avoidTolls,
    'avoidFerries': avoidFerries,
    'bywaySurface': bywaySurface.apiValue,
    if (vehicle.isSpecified) 'vehicle': vehicle.toJson(),
  };

  /// Reads preferences a route was planned with.
  ///
  /// An unrecognised or missing value falls back to the documented default
  /// rather than throwing: a route from an older build, or from another tool,
  /// still has to open. The byway default is the road-biased one, so a route
  /// that never recorded a preference is not silently sent down a green lane.
  factory RoutePreferences.fromJson(Map<String, Object?> json) =>
      RoutePreferences(
        style: RouteStyle.fromApiValue(json['style']) ?? RouteStyle.direct,
        avoidMotorways: json['avoidMotorways'] == true,
        avoidMajorRoads: json['avoidMajorRoads'] == true,
        avoidTolls: json['avoidTolls'] == true,
        avoidFerries: json['avoidFerries'] == true,
        bywaySurface:
            BywaySurfacePreference.fromApiValue(json['bywaySurface']) ??
            BywaySurfacePreference.avoidUnsurfaced,
        vehicle: switch (json['vehicle']) {
          final Map<String, Object?> vehicle => ChaseVehicle.fromJson(vehicle),
          final Map<Object?, Object?> vehicle => ChaseVehicle.fromJson(
            vehicle.map((key, value) => MapEntry(key.toString(), value)),
          ),
          _ => ChaseVehicle.unspecified,
        },
      );

  @override
  bool operator ==(Object other) =>
      other is RoutePreferences &&
      other.style == style &&
      other.avoidMotorways == avoidMotorways &&
      other.avoidMajorRoads == avoidMajorRoads &&
      other.avoidTolls == avoidTolls &&
      other.avoidFerries == avoidFerries &&
      other.bywaySurface == bywaySurface &&
      other.vehicle == vehicle;

  @override
  int get hashCode => Object.hash(
    style,
    avoidMotorways,
    avoidMajorRoads,
    avoidTolls,
    avoidFerries,
    bywaySurface,
    vehicle,
  );

  @override
  String toString() => 'RoutePreferences(${toJson()})';
}
