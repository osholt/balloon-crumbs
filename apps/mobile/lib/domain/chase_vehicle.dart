/// The physical chase vehicle, as the crew described it.
///
/// There is no fixed chase vehicle to model and no list to choose from: it
/// varies by crew and could be anything from a hatchback to a Land Rover towing
/// a trailer with a basket on it. So every dimension here is *entered*, never
/// inferred from a vehicle type.
///
/// Every field is nullable and empty by default, and that is load-bearing. A
/// blank height means "nobody told us", not "assume it fits". The two must not
/// be confused, because the second one is the sentence that drives a trailer
/// into a bridge. Nothing is claimed on the crew's behalf: with nothing entered,
/// routing behaves exactly as it did before this existed.
///
/// The vehicle belongs to the crew rather than to a flight. The same Land Rover
/// tows the same trailer next weekend, so this is entered once and kept, not
/// asked again at the start of every flight — the person who would answer is
/// about to start driving.
class ChaseVehicle {
  const ChaseVehicle({
    this.heightMetres,
    this.widthMetres,
    this.lengthMetres,
    this.grossWeightTonnes,
    this.towing = false,
  });

  /// Nothing entered. Routes as a car, which is what the app did before the
  /// crew could describe their vehicle at all.
  static const ChaseVehicle unspecified = ChaseVehicle();

  /// Overall height including anything on the roof, in metres. The dimension
  /// that low bridges care about.
  final double? heightMetres;

  /// Overall width excluding mirrors, in metres.
  final double? widthMetres;

  /// Overall length, in metres. Including the trailer when [towing], which is
  /// usually the dimension towing changes most: a car and trailer is often
  /// twice as long and no wider.
  final double? lengthMetres;

  /// The heaviest the vehicle and anything it is towing can legally be
  /// *together*, in tonnes.
  ///
  /// Deliberately the combined figure and deliberately the maximum, because
  /// this is checked against weight-restricted bridges and structures. A towbar
  /// capacity or an unladen weight would be the wrong number in the dangerous
  /// direction: it would route a loaded trailer over a bridge that cannot take
  /// it. Overstating costs a detour, understating costs a bridge.
  final double? grossWeightTonnes;

  /// Whether a trailer is attached. On its own this changes no numbers — it
  /// cannot, because a trailer has no default size — but it is what makes the
  /// weight field mean the combined weight, and it asks the router to prefer
  /// straighter roads.
  final bool towing;

  /// Whether the crew has entered any dimension at all.
  ///
  /// The switch that decides whether routing can say anything about physical
  /// restrictions. False means it cannot, and must not pretend to.
  bool get hasDimensions =>
      heightMetres != null ||
      widthMetres != null ||
      lengthMetres != null ||
      grossWeightTonnes != null;

  /// Whether anything at all has been said about the vehicle.
  bool get isSpecified => hasDimensions || towing;

  /// Whether the route must be planned with Valhalla's `truck` costing rather
  /// than `auto`.
  ///
  /// This is the whole reason the fields exist. Valhalla's `auto` costing
  /// ignores `maxheight`, `maxweight` and `maxwidth` entirely, so a chase
  /// vehicle routed as a car is routed under low bridges without a word.
  /// `truck` costing reads those OpenStreetMap restrictions and applies
  /// manoeuvre costs that suit something long.
  ///
  /// Requires a dimension, not merely [towing]: `truck` costing without
  /// dimensions falls back to Valhalla's own defaults, which describe an
  /// articulated lorry — 4.11 m tall and 21.77 t. Applying those to a crew who
  /// ticked "towing" and typed nothing else would refuse half the roads to the
  /// county, and refuse them for reasons the crew never stated.
  bool get requiresTruckCosting => hasDimensions;

  /// The dimensions to send under `costing_options.truck`.
  ///
  /// Unentered dimensions are sent as ordinary car figures rather than left out.
  /// Omitting them would inherit Valhalla's lorry defaults, and a blank field
  /// means "not told", which must restrict nothing. So the fallbacks are
  /// deliberately small: understating a dimension the crew never gave applies no
  /// restriction on that axis, which is the same answer they got before.
  ///
  /// This is not a claim that the vehicle is car-sized. It is a refusal to
  /// invent a restriction from a field nobody filled in.
  Map<String, Object?> valhallaTruckDimensions() => {
    'height': heightMetres ?? 2,
    'width': widthMetres ?? 2,
    'length': lengthMetres ?? 5,
    'weight': grossWeightTonnes ?? 2,
    // Never hazmat. A chase vehicle carries cylinders, and propane is a
    // dangerous good, but hazmat routing is a legal regime about placarded
    // loads that a crew has not entered and this app must not assert.
    'hazmat': false,
  };

  /// What the crew will read back, so the numbers being routed against can be
  /// checked. Empty when nothing was entered, which is itself the honest
  /// summary.
  List<String> get appliedNotes => [
    if (towing) 'towing',
    if (heightMetres case final height?) '${_number(height)} m high',
    if (widthMetres case final width?) '${_number(width)} m wide',
    if (lengthMetres case final length?) '${_number(length)} m long',
    if (grossWeightTonnes case final weight?) '${_number(weight)} t',
  ];

  ChaseVehicle copyWith({
    double? heightMetres,
    double? widthMetres,
    double? lengthMetres,
    double? grossWeightTonnes,
    bool? towing,
    bool clearHeight = false,
    bool clearWidth = false,
    bool clearLength = false,
    bool clearWeight = false,
  }) => ChaseVehicle(
    heightMetres: clearHeight ? null : heightMetres ?? this.heightMetres,
    widthMetres: clearWidth ? null : widthMetres ?? this.widthMetres,
    lengthMetres: clearLength ? null : lengthMetres ?? this.lengthMetres,
    grossWeightTonnes: clearWeight
        ? null
        : grossWeightTonnes ?? this.grossWeightTonnes,
    towing: towing ?? this.towing,
  );

  Map<String, Object?> toJson() => {
    'heightMetres': ?heightMetres,
    'widthMetres': ?widthMetres,
    'lengthMetres': ?lengthMetres,
    'grossWeightTonnes': ?grossWeightTonnes,
    if (towing) 'towing': true,
  };

  /// Reads a vehicle a route was planned with.
  ///
  /// A value that is not a plausible dimension degrades to null — not told —
  /// rather than throwing or being clamped into range. A stored route from
  /// another build must still open, and a nonsense height must not quietly
  /// become a real restriction the crew never entered.
  factory ChaseVehicle.fromJson(Map<String, Object?> json) => ChaseVehicle(
    heightMetres: _dimension(json['heightMetres'], maximum: 7),
    widthMetres: _dimension(json['widthMetres'], maximum: 4),
    lengthMetres: _dimension(json['lengthMetres'], maximum: 30),
    grossWeightTonnes: _dimension(json['grossWeightTonnes'], maximum: 44),
    towing: json['towing'] == true,
  );

  /// Accepts a number a person could have typed, and nothing else. Zero and
  /// negatives are not small vehicles, they are empty or broken fields.
  static double? _dimension(Object? value, {required double maximum}) {
    final number = value is num
        ? value.toDouble()
        : value is String
        ? double.tryParse(value.trim())
        : null;
    if (number == null || !number.isFinite) return null;
    return number > 0 && number <= maximum ? number : null;
  }

  static String _number(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  @override
  bool operator ==(Object other) =>
      other is ChaseVehicle &&
      other.heightMetres == heightMetres &&
      other.widthMetres == widthMetres &&
      other.lengthMetres == lengthMetres &&
      other.grossWeightTonnes == grossWeightTonnes &&
      other.towing == towing;

  @override
  int get hashCode => Object.hash(
    heightMetres,
    widthMetres,
    lengthMetres,
    grossWeightTonnes,
    towing,
  );

  @override
  String toString() => 'ChaseVehicle(${toJson()})';
}
