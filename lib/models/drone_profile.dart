enum DroneProfileType { mini249g, proCine900g, fpvRacer }

/// Ajustes persistíveis da Garagem (aparência 3D, FOV FPV e tuning físico).
class DroneTuning {
  static const List<String> ledPalette = [
    '#00d4ff',
    '#00ff66',
    '#ff7a00',
    '#c04dff',
    '#ff2e4c',
    '#ffd166',
  ];

  static const List<String> armPalette = [
    '#181a1c',
    '#5c6773',
    '#d8e2ec',
    '#3b5239',
    '#8b1e24',
  ];

  static final RegExp _hexPattern = RegExp(r'^#[0-9a-fA-F]{6}$');

  final String ledColorHex;
  final String armColorHex;
  final double cameraFovDeg;
  final double weightMultiplier;
  final double batteryCapacityMultiplier;

  const DroneTuning({
    this.ledColorHex = '#00d4ff',
    this.armColorHex = '#181a1c',
    this.cameraFovDeg = 64.0,
    this.weightMultiplier = 1.0,
    this.batteryCapacityMultiplier = 1.0,
  });

  static String _sanitizeHex(dynamic raw, String fallback) {
    if (raw is String && _hexPattern.hasMatch(raw)) {
      return raw.toLowerCase();
    }
    return fallback;
  }

  DroneTuning copyWith({
    String? ledColorHex,
    String? armColorHex,
    double? cameraFovDeg,
    double? weightMultiplier,
    double? batteryCapacityMultiplier,
  }) {
    return DroneTuning(
      ledColorHex: ledColorHex != null
          ? _sanitizeHex(ledColorHex, this.ledColorHex)
          : this.ledColorHex,
      armColorHex: armColorHex != null
          ? _sanitizeHex(armColorHex, this.armColorHex)
          : this.armColorHex,
      cameraFovDeg:
          (cameraFovDeg ?? this.cameraFovDeg).clamp(55.0, 105.0).toDouble(),
      weightMultiplier: (weightMultiplier ?? this.weightMultiplier)
          .clamp(0.80, 1.30)
          .toDouble(),
      batteryCapacityMultiplier:
          (batteryCapacityMultiplier ?? this.batteryCapacityMultiplier)
              .clamp(0.75, 1.50)
              .toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'ledColorHex': ledColorHex,
        'armColorHex': armColorHex,
        'cameraFovDeg': cameraFovDeg,
        'weightMultiplier': weightMultiplier,
        'batteryCapacityMultiplier': batteryCapacityMultiplier,
      };

  factory DroneTuning.fromJson(Map<String, dynamic> json) {
    return DroneTuning(
      ledColorHex: _sanitizeHex(json['ledColorHex'], '#00d4ff'),
      armColorHex: _sanitizeHex(json['armColorHex'], '#181a1c'),
      cameraFovDeg: (json['cameraFovDeg'] as num?)
              ?.toDouble()
              .clamp(55.0, 105.0) ??
          64.0,
      weightMultiplier: (json['weightMultiplier'] as num?)
              ?.toDouble()
              .clamp(0.80, 1.30) ??
          1.0,
      batteryCapacityMultiplier: (json['batteryCapacityMultiplier'] as num?)
              ?.toDouble()
              .clamp(0.75, 1.50) ??
          1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DroneTuning &&
          runtimeType == other.runtimeType &&
          ledColorHex == other.ledColorHex &&
          armColorHex == other.armColorHex &&
          cameraFovDeg == other.cameraFovDeg &&
          weightMultiplier == other.weightMultiplier &&
          batteryCapacityMultiplier == other.batteryCapacityMultiplier;

  @override
  int get hashCode => Object.hash(
        ledColorHex,
        armColorHex,
        cameraFovDeg,
        weightMultiplier,
        batteryCapacityMultiplier,
      );
}

class DroneProfile {
  final DroneProfileType type;
  final String name;
  final double weightGrams;
  final double maxSpeedKmh;
  final double accelerationMs2;
  final double maxAscentMs;
  final double maxDescentMs;
  final int batteryMinutes;
  final double baseDrainPerSecond;
  final double windSensitivity;

  const DroneProfile({
    required this.type,
    required this.name,
    required this.weightGrams,
    required this.maxSpeedKmh,
    required this.accelerationMs2,
    required this.maxAscentMs,
    required this.maxDescentMs,
    required this.batteryMinutes,
    required this.baseDrainPerSecond,
    required this.windSensitivity,
  });

  static const DroneProfile mini249g = DroneProfile(
    type: DroneProfileType.mini249g,
    name: 'Mini 249g',
    weightGrams: 249,
    maxSpeedKmh: 46,
    accelerationMs2: 3.0,
    maxAscentMs: 5.0,
    maxDescentMs: 3.5,
    batteryMinutes: 25,
    baseDrainPerSecond: 100.0 / (25 * 60),
    windSensitivity: 1.5,
  );

  static const DroneProfile proCine900g = DroneProfile(
    type: DroneProfileType.proCine900g,
    name: 'Pro Cine 900g',
    weightGrams: 900,
    maxSpeedKmh: 54,
    accelerationMs2: 2.0,
    maxAscentMs: 6.0,
    maxDescentMs: 3.0,
    batteryMinutes: 30,
    baseDrainPerSecond: 100.0 / (30 * 60),
    windSensitivity: 0.6,
  );

  static const DroneProfile fpvRacer = DroneProfile(
    type: DroneProfileType.fpvRacer,
    name: 'FPV Racer',
    weightGrams: 580,
    maxSpeedKmh: 110,
    accelerationMs2: 8.0,
    maxAscentMs: 10.0,
    maxDescentMs: 8.0,
    batteryMinutes: 8,
    baseDrainPerSecond: 100.0 / (8 * 60),
    windSensitivity: 1.0,
  );

  static const List<DroneProfile> all = [mini249g, proCine900g, fpvRacer];
}
