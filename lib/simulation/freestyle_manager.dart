import 'dart:math' as math;

/// Meta de desafio do modo Freestyle por cenário.
class FreestyleChallenge {
  final String mapId;
  final String title;
  final String description;
  final double targetScore;
  final bool requireNoCrash;
  final int minDistinctTricks;

  const FreestyleChallenge({
    required this.mapId,
    required this.title,
    required this.description,
    required this.targetScore,
    this.requireNoCrash = true,
    this.minDistinctTricks = 3,
  });

  static FreestyleChallenge forMapId(String mapId) {
    switch (mapId) {
      case 'parque_florestal':
      case 'aeroclube':
        return const FreestyleChallenge(
          mapId: 'parque_florestal',
          title: 'Desafio do Bosque',
          description: 'Faça 2.500 pts e 3 manobras distintas sem cair.',
          targetScore: 2500.0,
          requireNoCrash: true,
          minDistinctTricks: 3,
        );
      case 'canion_represa':
      case 'fpv_arena':
        return const FreestyleChallenge(
          mapId: 'canion_represa',
          title: 'Desafio da Represa',
          description: 'Faça 3.500 pts e 3 manobras distintas sem cair.',
          targetScore: 3500.0,
          requireNoCrash: true,
          minDistinctTricks: 3,
        );
      case 'distrito_urbano':
      case 'drone_park':
      default:
        return const FreestyleChallenge(
          mapId: 'distrito_urbano',
          title: 'Desafio Urbano',
          description: 'Faça 3.000 pts e 3 manobras distintas sem cair.',
          targetScore: 3000.0,
          requireNoCrash: true,
          minDistinctTricks: 3,
        );
    }
  }
}

/// Gerenciador de pontuação e detecção de manobras para o modo Freestyle Acro.
class FreestyleManager {
  static const double sessionDurationSeconds = 90.0;
  static const double comboWindowSeconds = 8.0;
  static const int maxCombo = 6;

  final FreestyleChallenge? challenge;
  final void Function(String label, double points, int combo)? onTrick;
  final void Function(FreestyleManager manager)? onFinished;
  final void Function(FreestyleChallenge challenge)? onChallengeCompleted;

  bool isActive = false;
  bool isFinished = false;
  bool hadCrash = false;
  bool challengeCompleted = false;
  double remainingSeconds = sessionDurationSeconds;
  double score = 0.0;
  int combo = 1;
  int bestCombo = 1;
  int tricksCount = 0;

  String? lastTrickLabel;
  double lastTrickPoints = 0.0;
  double lastTrickAgeSec = 99.0;
  final Map<String, int> trickBreakdown = {};

  double _accPitch = 0.0;
  double _accRoll = 0.0;
  double _accYaw = 0.0;
  double _timeSinceTrick = 0.0;
  double _proximityHoldSec = 0.0;
  bool _inDive = false;
  double _loopMinAlt = double.infinity;
  double _loopMaxAlt = 0.0;
  double _loopPeakSpeedKmh = 0.0;
  int _splitSStage = 0;
  double _splitSEntryAlt = 0.0;
  double _splitSTimer = 0.0;
  double _splitSPitchAccum = 0.0;
  double _invertedHoldSec = 0.0;
  double _gapHoldSec = 0.0;
  double _gapCooldownSec = 0.0;
  double _underBridgeHoldSec = 0.0;
  double _underBridgeCooldownSec = 0.0;

  FreestyleManager({
    this.challenge,
    this.onTrick,
    this.onFinished,
    this.onChallengeCompleted,
  });

  double get challengeProgress {
    final c = challenge;
    if (c == null || c.targetScore <= 0.0) return 0.0;
    return (score / c.targetScore).clamp(0.0, 1.0);
  }

  void start() {
    isActive = true;
    isFinished = false;
    hadCrash = false;
    challengeCompleted = false;
    remainingSeconds = sessionDurationSeconds;
    score = 0.0;
    combo = 1;
    bestCombo = 1;
    tricksCount = 0;
    lastTrickLabel = null;
    lastTrickPoints = 0.0;
    lastTrickAgeSec = 99.0;
    trickBreakdown.clear();
    _gapCooldownSec = 0.0;
    _underBridgeCooldownSec = 0.0;
    _resetAccumulators();
  }

  void _resetLoopTrackers() {
    _loopMinAlt = double.infinity;
    _loopMaxAlt = 0.0;
    _loopPeakSpeedKmh = 0.0;
  }

  void _resetSplitS() {
    _splitSStage = 0;
    _splitSEntryAlt = 0.0;
    _splitSTimer = 0.0;
    _splitSPitchAccum = 0.0;
  }

  void _resetAccumulators() {
    _accPitch = 0.0;
    _accRoll = 0.0;
    _accYaw = 0.0;
    _timeSinceTrick = 0.0;
    _proximityHoldSec = 0.0;
    _inDive = false;
    _invertedHoldSec = 0.0;
    _gapHoldSec = 0.0;
    _underBridgeHoldSec = 0.0;
    _resetLoopTrackers();
    _resetSplitS();
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
    double upWorldZ = 1.0,
    double horizontalSpeedMs = 0.0,
    bool inTightGap = false,
    bool underBridge = false,
  }) {
    if (!isActive || isFinished) return;

    remainingSeconds = math.max(0.0, remainingSeconds - dt);
    lastTrickAgeSec += dt;
    _timeSinceTrick += dt;
    if (_gapCooldownSec > 0.0) {
      _gapCooldownSec = math.max(0.0, _gapCooldownSec - dt);
    }
    if (_underBridgeCooldownSec > 0.0) {
      _underBridgeCooldownSec = math.max(0.0, _underBridgeCooldownSec - dt);
    }

    if (_timeSinceTrick > comboWindowSeconds && combo > 1) {
      combo = 1;
    }

    if (crashed) {
      hadCrash = true;
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
      _invertedHoldSec = 0.0;
      _resetLoopTrackers();
      _resetSplitS();
      return;
    }

    // 1. Acumulação de flips / power loops / barrel rolls / spins 360°
    if (omegaPitchRadS.abs() > 0.35) {
      _accPitch += omegaPitchRadS * dt;
    } else {
      _accPitch *= math.max(0.0, 1.0 - dt * 2.5);
    }

    if (_accPitch.abs() >= 0.25) {
      _loopMinAlt = math.min(_loopMinAlt, altitude);
      _loopMaxAlt = math.max(_loopMaxAlt, altitude);
      _loopPeakSpeedKmh = math.max(_loopPeakSpeedKmh, speedKmh);
    } else {
      _resetLoopTrackers();
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

    // 2. Split-S: rolar invertido em altura, puxar pitch no mergulho e nivelar abaixo.
    var awardedSplitS = false;
    if (_splitSStage == 0) {
      if (altitude >= 8.0 && upWorldZ < -0.25 && _accRoll.abs() >= 1.8) {
        _splitSStage = 1;
        _splitSEntryAlt = altitude;
        _splitSTimer = 0.0;
        _splitSPitchAccum = 0.0;
      }
    } else if (_splitSStage == 1) {
      _splitSTimer += dt;
      if (_splitSTimer > 3.5) {
        _resetSplitS();
      } else if (omegaPitchRadS.abs() > 0.6 &&
          (verticalSpeedMs <= -3.0 || _splitSEntryAlt - altitude >= 3.0)) {
        _splitSStage = 2;
      }
    } else if (_splitSStage == 2) {
      _splitSTimer += dt;
      _splitSPitchAccum += omegaPitchRadS.abs() * dt;
      if (_splitSTimer > 4.5) {
        _resetSplitS();
      } else if (upWorldZ > 0.60 &&
          verticalSpeedMs > -2.5 &&
          (_splitSEntryAlt - altitude) >= 4.0 &&
          _splitSPitchAccum >= 1.8) {
        _awardTrick('SPLIT-S', 380.0);
        _resetSplitS();
        _accRoll = 0.0;
        _accPitch = 0.0;
        _resetLoopTrackers();
        _inDive = false;
        awardedSplitS = true;
      }
    }

    if (!awardedSplitS && _accPitch.abs() >= fullFlipThreshold) {
      final altSwing =
          _loopMinAlt.isFinite ? (_loopMaxAlt - _loopMinAlt) : 0.0;
      if (altSwing >= 4.5 && _loopPeakSpeedKmh >= 25.0) {
        _awardTrick('POWER LOOP', 400.0);
      } else {
        _awardTrick('FLIP 360°', 250.0);
      }
      _accPitch = 0.0;
      _resetLoopTrackers();
    }
    if (!awardedSplitS && _accRoll.abs() >= fullFlipThreshold) {
      _awardTrick('BARREL ROLL 360°', 250.0);
      _accRoll = 0.0;
    }
    if (_accYaw.abs() >= fullYawThreshold && speedKmh >= 10.0) {
      _awardTrick('YAW SPIN 360°', 120.0);
      _accYaw = 0.0;
    }

    // 3. Inverted Hangtime: voo sustentado de cabeça para baixo.
    if (upWorldZ < -0.35 && altitude > 3.0) {
      _invertedHoldSec += dt;
      if (_invertedHoldSec >= 0.90) {
        _awardTrick('INVERTED HANGTIME', 220.0);
        _invertedHoldSec = 0.0;
      }
    } else {
      _invertedHoldSec = math.max(0.0, _invertedHoldSec - dt * 2.5);
    }

    // 4. Mergulho vertical + recuperação limpa
    if (verticalSpeedMs <= -7.5 && altitude > 8.0) {
      _inDive = true;
    } else if (_inDive && verticalSpeedMs > -1.0 && altitude > 1.2) {
      _inDive = false;
      _awardTrick('DIVE RECOVERY', 300.0);
    }

    // 5. Voo rasante próximo ao solo ou obstáculos
    if (speedKmh >= 24.0 && (altitude < 2.8 || minObstacleClearance < 4.5)) {
      _proximityHoldSec += dt;
      if (_proximityHoldSec >= 0.70) {
        _awardTrick('VOO RASANTE', 90.0);
        _proximityHoldSec = 0.0;
      }
    } else {
      _proximityHoldSec = math.max(0.0, _proximityHoldSec - dt * 2.0);
    }

    // 6. Freestyle 2.0: passagem sob ponte e gap estreito entre obstáculos
    if (underBridge && speedKmh >= 20.0 && _underBridgeCooldownSec <= 0.0) {
      _underBridgeHoldSec += dt;
      if (_underBridgeHoldSec >= 0.25) {
        _awardTrick('UNDER BRIDGE', 360.0);
        _underBridgeHoldSec = 0.0;
        _underBridgeCooldownSec = 3.5;
      }
    } else {
      _underBridgeHoldSec = math.max(0.0, _underBridgeHoldSec - dt * 2.0);
      if (inTightGap && speedKmh >= 22.0 && _gapCooldownSec <= 0.0) {
        _gapHoldSec += dt;
        if (_gapHoldSec >= 0.30) {
          _awardTrick('GAP THREAD', 320.0);
          _gapHoldSec = 0.0;
          _gapCooldownSec = 3.0;
        }
      } else {
        _gapHoldSec = math.max(0.0, _gapHoldSec - dt * 2.0);
      }
    }
  }

  void _awardTrick(String label, double basePoints) {
    final earned = (basePoints * combo).roundToDouble();
    score += earned;
    tricksCount++;
    trickBreakdown[label] = (trickBreakdown[label] ?? 0) + 1;
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

    final activeChallenge = challenge;
    if (activeChallenge != null &&
        !challengeCompleted &&
        score >= activeChallenge.targetScore &&
        trickBreakdown.length >= activeChallenge.minDistinctTricks &&
        (!activeChallenge.requireNoCrash || !hadCrash)) {
      challengeCompleted = true;
      onChallengeCompleted?.call(activeChallenge);
    }
  }
}
