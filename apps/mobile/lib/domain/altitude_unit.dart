enum AltitudeUnit { metres, feet }

extension AltitudeUnitLabel on AltitudeUnit {
  String get label => switch (this) {
    AltitudeUnit.metres => 'Metres',
    AltitudeUnit.feet => 'Feet',
  };

  String get symbol => switch (this) {
    AltitudeUnit.metres => 'm',
    AltitudeUnit.feet => 'ft',
  };

  double fromMetres(double metres) => switch (this) {
    AltitudeUnit.metres => metres,
    AltitudeUnit.feet => metres * 3.280839895,
  };

  String altitude(double metres) => '${fromMetres(metres).round()} $symbol';

  String accuracy(double metres) => '±${fromMetres(metres).round()} $symbol';

  String verticalRate(double metresPerSecond) => switch (this) {
    AltitudeUnit.metres => '${metresPerSecond.toStringAsFixed(1)} m/s',
    AltitudeUnit.feet => '${(metresPerSecond * 196.8503937).round()} ft/min',
  };
}
