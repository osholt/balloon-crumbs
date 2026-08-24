/// What a craft is: one balloon, or one chase vehicle.
///
/// A flight holds a *set* of crafts rather than a balloon plus a list of
/// vehicles. One balloon is a cardinality the UI enforces, not an assumption
/// baked into every read model — see "Designed-for, not built-yet" in
/// `docs/delivery-plan.md`. A club event with several balloons is backlogged,
/// and this shape is what stops it needing the data model re-cut.
enum CraftKind {
  /// The aircraft. Reports altitude and a vertical trend; does not follow roads.
  balloon,

  /// A chase vehicle on the road network.
  vehicle,
}

/// The small set of operationally meaningful silhouettes used for a craft.
///
/// This belongs in the domain because it is a property of the balloon or chase
/// vehicle, not of each phone aboard it. Rendering metadata remains in the map
/// feature.
enum CraftIconStyle { balloon, fourByFour, pickup, van, trailer }

const vehicleCraftIconStyles = <CraftIconStyle>[
  CraftIconStyle.fourByFour,
  CraftIconStyle.pickup,
  CraftIconStyle.van,
  CraftIconStyle.trailer,
];

extension CraftIconStyleKind on CraftIconStyle {
  CraftKind get kind =>
      this == CraftIconStyle.balloon ? CraftKind.balloon : CraftKind.vehicle;

  bool get isBalloon => kind == CraftKind.balloon;
}

const craftIconStyleDefault = CraftIconStyle.fourByFour;

CraftIconStyle craftIconStyleFromName(String? name) =>
    CraftIconStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => craftIconStyleDefault,
    );

CraftIconStyle defaultCraftIconStyleFor(CraftKind kind) =>
    kind == CraftKind.balloon ? CraftIconStyle.balloon : craftIconStyleDefault;

/// One balloon or vehicle in a flight, however many phones are aboard it.
///
/// This is the unit every surface should reason about. The inherited model gave
/// each *device* a position, which fails in both directions for ballooning:
/// three crew in a basket became three participants stacked on each other, and
/// nothing could answer "where is the balloon".
class Craft {
  const Craft({
    required this.id,
    required this.kind,
    required this.label,
    CraftIconStyle? iconStyle,
    this.chasing,
  }) : iconStyle =
           iconStyle ??
           (kind == CraftKind.balloon
               ? CraftIconStyle.balloon
               : craftIconStyleDefault),
       assert(
         kind == CraftKind.vehicle || chasing == null,
         'Only a vehicle chases another craft.',
       ),
       assert(
         iconStyle == null ||
             (kind == CraftKind.balloon
                 ? iconStyle == CraftIconStyle.balloon
                 : iconStyle != CraftIconStyle.balloon),
         'A craft icon must match the craft kind.',
       ),
       assert(chasing != id, 'A craft cannot chase itself.');

  final String id;
  final CraftKind kind;

  /// What the crew calls it: "Balloon", "Land Rover", "Vehicle 2".
  final String label;
  final CraftIconStyle iconStyle;

  /// For a vehicle, the craft it is currently chasing.
  ///
  /// Its own fact, deliberately separate from membership: a vehicle *belongs to
  /// the flight* and *is currently chasing craft X*. With one balloon this is
  /// implicit and invisible. With several it becomes the interesting state, and
  /// reassigning a vehicle mid-flight is then a new event rather than a schema
  /// change. Null means unassigned — which with one balloon a caller may read as
  /// "the balloon", but guidance must always take its target as a parameter
  /// rather than reaching for a global.
  final String? chasing;

  bool get isBalloon => kind == CraftKind.balloon;

  Craft copyWith({
    String? label,
    CraftIconStyle? iconStyle,
    String? chasing,
    bool clearChasing = false,
  }) => Craft(
    id: id,
    kind: kind,
    label: label ?? this.label,
    iconStyle: iconStyle ?? this.iconStyle,
    chasing: clearChasing ? null : (chasing ?? this.chasing),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'label': label,
    'craftStyle': iconStyle.name,
    'chasing': ?chasing,
  };

  factory Craft.fromJson(Map<String, Object?> json) {
    final kind = craftKindFromName(json['kind']);
    return Craft(
      id: json['id']! as String,
      kind: kind,
      label: json['label']! as String,
      iconStyle: _iconStyleForKind(kind, json['craftStyle']),
      // Defensive rather than trusting: a vehicle-only field arriving on a
      // balloon would trip the constructor assertion, and a malformed peer
      // payload should degrade rather than crash a whole flight's read model.
      chasing: kind == CraftKind.vehicle ? json['chasing'] as String? : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Craft &&
      other.id == id &&
      other.kind == kind &&
      other.label == label &&
      other.iconStyle == iconStyle &&
      other.chasing == chasing;

  @override
  int get hashCode => Object.hash(id, kind, label, iconStyle, chasing);
}

CraftIconStyle _iconStyleForKind(CraftKind kind, Object? value) {
  final parsed = craftIconStyleFromName(value is String ? value : null);
  return parsed.kind == kind ? parsed : defaultCraftIconStyleFor(kind);
}

/// Reads a craft kind that another build may have written.
///
/// Unknown names degrade to [CraftKind.vehicle] rather than throwing, on the
/// same reasoning as `rideRoleFromName`: a peer is allowed to know a kind this
/// build does not. Vehicle is the safe default — treating an unknown craft as a
/// balloon would put a second aircraft on the map and could hand guidance a
/// target that is not flying.
CraftKind craftKindFromName(Object? value) {
  if (value is! String) return CraftKind.vehicle;
  for (final kind in CraftKind.values) {
    if (kind.name == value) return kind;
  }
  return CraftKind.vehicle;
}
