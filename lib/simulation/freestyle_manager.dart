import 'dart:math' as math;

/// Gerenciador de pontuação e detecção de manobras para o modo Freestyle Acro.
class FreestyleManager {
  static const double sessionDurationSeconds = 90.0;
  static const double comboWindowSeconds = 8.0;
  static const int maxCombo = 6;

  final void Function(String label, double points, int combo)? onTrick;
  final void Function(FreestyleManager manager)? onFinished;

  bool isActive = false;
  bool isFinished = false;
  double remainingSeconds = sessionDurationSeconds;
  double score = 0.0;
  int combo = 1;
  int bestCombo = 1;
  int tricksCount = 0;

  String? lastTrickLabel;
  double lastTrickPoints = 0.0;
  double lastTrickAgeSec = 99.0;

  double _accPitch = 0.0;
  double _accRoll = 0.0;
  double _accYaw = 0.0;
  double _timeSinceTrick = 0.0;
  double _proximityHoldSec = 0.0;
  bool _inDive = false;

  FreestyleManager({this.onTrick, this.onFinished});

  void start() {
    isActive = true;
    isFinished = false;
    remainingSeconds = sessionDurationSeconds;
    score = 0.0;
    combo = 1;
    bestCombo = 1;
    tricksCount = 0;
    lastTrickLabel = null;
    lastTrickPoints = 0.0;
    lastTrickAgeSec = 99.0;
    _resetAccumulators();
  }

  void _resetAccumulators() {
    _accPitch = 0.0;
    _accRoll = 0.0;
    _accYaw = 0.0;
    _timeSinceTrick = 0.0;
    _proximityHoldSec = 0.0;
    _inDive = false;
  }

  void update({
    required double dt,
    required double altitude,
    required double speedKmh,
    required double verticalSpeedMs,
    required double omegaPitchRadS,
    required double omegaRollRadS,
    required double omegaYawRadS,
    required double minObstacleClearance,
    required bool crashed,
  }) {
    if (!isActive || isFinished) return;

    remainingSeconds = math.max(0.0, remainingSeconds - dt);
    lastTrickAgeSec += dt;
    _timeSinceTrick += dt;

    if (_timeSinceTrick > comboWindowSeconds && combo > 1) {
      combo = 1;
    }

    if (crashed) {
      combo = 1;
      _resetAccumulators();
      return;
    }

    if (remainingSeconds <= 0.0) {
      isActive = false;
      isFinished = true;
      onFinished?.call(this);
      return;
    }

    if (altitude <= 1.2) {
      _accPitch *= 0.85;
      _accRoll *= 0.85;
      _accYaw *= 0.85;
      _proximityHoldSec = 0.0;
      _inDive = false;
      return;
    }

    // 1. Acumulação de flips / rolls / spins 360°
    if (omegaPitchRadS.abs() > 0.35) {
      _accPitch += omegaPitchRadS * dt;
    } else {
      _accPitch *= math.max(0.0, 1.0 - dt * 2.5);
    }

    if (omegaRollRadS.abs() > 0.35) {
      _accRoll += omegaRollRadS * dt;
    } else {
      _accRoll *= math.max(0.0, 1.0 - dt * 2.5);
    }

    if (omegaYawRadS.abs() > 0.45) {
      _accYaw += omegaYawRadS * dt;
    } else {
      _accYaw *= math.max(0.0, 1.0 - dt * 2.5);
    }

    const fullFlipThreshold = 2.0 * math.pi * 0.90;
    const fullYawThreshold = 2.0 * math.pi * 0.95;

    if (_accPitch.abs() >= fullFlipThreshold) {
      _awardTrick('FLIP 360°', 250.0);
      _accPitch = 0.0;
    }
    if (_accRoll.abs() >= fullFlipThreshold) {
      _awardTrick('BARREL ROLL 360°', 250.0);
      _accRoll = 0.0;
    }
    if (_accYaw.abs() >= fullYawThreshold && speedKmh >= 10.0) {
      _awardTrick('YAW SPIN 360°', 120.0);
      _accYaw = 0.0;
    }

    // 2. Mergulho vertical + recuperação limpa
    if (verticalSpeedMs <= -7.5 && altitude > 8.0) {
      _inDive = true;
    } else if (_inDive && verticalSpeedMs > -1.0 && altitude > 1.2) {
      _inDive = false;
      _awardTrick('DIVE RECOVERY', 300.0);
    }

    // 3. Voo rasante próximo ao solo ou obstáculos
    if (speedKmh >= 24.0 && (altitude < 2.8 || minObstacleClearance < 4.5)) {
      _proximityHoldSec += dt;
      if (_proximityHoldSec >= 0.70) {
        _awardTrick('VOO RASANTE', 90.0);
        _proximityHoldSec = 0.0;
      }
    } else {
      _proximityHoldSec = math.max(0.0, _proximityHoldSec - dt * 2.0);
    }
  }

  void _awardTrick(String label, double basePoints) {
    final earned = (basePoints * combo).roundToDouble();
    score += earned;
    tricksCount++;
    lastTrickLabel = label;
    lastTrickPoints = earned;
    lastTrickAgeSec = 0.0;

    if (_timeSinceTrick <= comboWindowSeconds) {
      combo = math.min(maxCombo, combo + 1);
    } else {
      combo = 1;
    }
    bestCombo = math.max(bestCombo, combo);
    _timeSinceTrick = 0.0;

    onTrick?.call(label, earned, combo);
  }
}
