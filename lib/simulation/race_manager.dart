import 'dart:math' as math;

import 'package:drone_simulator/models/race_course.dart';

/// Estado da corrida de portais.
enum RaceStatus { ready, racing, finished, failed }

/// Controla progresso, pontuação, combo, Time Attack e recordes de um circuito.
class RaceManager {
  final RaceCourse course;
  final bool timeAttackMode;
  final void Function(int combo, int gatesCleared)? onGatePassed;
  final void Function(RaceManager manager)? onFinished;

  RaceStatus status = RaceStatus.ready;
  int currentGateIndex = 0;
  int gatesCleared = 0;
  double elapsedSeconds = 0.0;
  double remainingSeconds = 0.0;
  double score = 0.0;
  int combo = 1;
  int bestCombo = 1;
  double timeSinceLastGate = 0.0;

  /// Melhor tempo por mapa (mapId → segundos).
  final Map<String, double> bestTimes = {};

  static const double comboWindowSeconds = 6.0;
  static const int maxCombo = 5;
  static const double initialTimeAttackSeconds = 25.0;
  static const double maxTimeAttackSeconds = 35.0;

  RaceManager({
    required this.course,
    this.timeAttackMode = false,
    this.onGatePassed,
    this.onFinished,
  });

  int get totalGates => course.gates.length;
  bool get isRacing => status == RaceStatus.racing;
  bool get isFinished => status == RaceStatus.finished;
  bool get isFailed => status == RaceStatus.failed;

  RaceGate? get activeGate =>
      currentGateIndex < course.gates.length
          ? course.gates[currentGateIndex]
          : null;

  /// Recorde atual do circuito (segundos) ou null.
  double? get bestTime => bestTimes[course.mapId];

  /// Distância 3D até o centro do próximo portal.
  double distanceToNextGate(double x, double y, double z) {
    final gate = activeGate;
    if (gate == null) return 0.0;
    final dx = gate.x - x;
    final dy = gate.y - y;
    final dz = gate.z - z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  void start() {
    status = RaceStatus.racing;
    currentGateIndex = 0;
    gatesCleared = 0;
    elapsedSeconds = 0.0;
    remainingSeconds = timeAttackMode ? initialTimeAttackSeconds : 0.0;
    score = 0.0;
    combo = 1;
    bestCombo = 1;
    timeSinceLastGate = 0.0;
  }

  /// Reinicia no mesmo circuito (usado após crash ou vitória).
  void restart() => start();

  /// Avança a corrida. Deve ser chamado a cada frame.
  void update({
    required double dt,
    required double x,
    required double y,
    required double z,
    required double speedKmh,
    required bool crashed,
  }) {
    if (status != RaceStatus.racing) return;

    elapsedSeconds += dt;
    timeSinceLastGate += dt;
    if (timeAttackMode) {
      remainingSeconds = math.max(0.0, remainingSeconds - dt);
    }

    if (crashed) {
      status = RaceStatus.failed;
      return;
    }

    if (timeAttackMode && remainingSeconds <= 0.0) {
      status = RaceStatus.finished;
      onFinished?.call(this);
      return;
    }

    final gate = activeGate;
    if (gate == null) return;

    final dx = gate.x - x;
    final dy = gate.y - y;
    final dz = gate.z - z;
    final distance = math.sqrt(dx * dx + dy * dy + dz * dz);

    if (distance > gate.radius) return;

    // Passou pelo portal ativo: pontua e avança.
    final speedBonus = (speedKmh * 2.0).roundToDouble().clamp(0.0, 400.0);
    score += 100.0 * combo + speedBonus;

    combo = timeSinceLastGate <= comboWindowSeconds
        ? math.min(combo + 1, maxCombo)
        : 1;
    bestCombo = math.max(bestCombo, combo);
    timeSinceLastGate = 0.0;
    gatesCleared++;

    onGatePassed?.call(combo, gatesCleared);

    if (timeAttackMode) {
      final bonusSeconds = (4.5 - gatesCleared * 0.05).clamp(2.6, 4.5);
      remainingSeconds =
          math.min(maxTimeAttackSeconds, remainingSeconds + bonusSeconds);
      currentGateIndex = (currentGateIndex + 1) % course.gates.length;
      return;
    }

    currentGateIndex++;

    if (currentGateIndex >= course.gates.length) {
      status = RaceStatus.finished;
      final previousBest = bestTimes[course.mapId];
      if (previousBest == null || elapsedSeconds < previousBest) {
        bestTimes[course.mapId] = elapsedSeconds;
      }
      onFinished?.call(this);
    }
  }
}
