enum DroneProfileType { mini249g, proCine900g, fpvRacer }

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
