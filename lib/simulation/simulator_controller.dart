import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:drone_simulator/models/drone_profile.dart';
import 'package:drone_simulator/models/race_course.dart';
import 'package:drone_simulator/services/feedback_service.dart';
import 'package:drone_simulator/services/records_repository.dart';
import 'package:drone_simulator/simulation/flight_physics.dart';
import 'package:drone_simulator/simulation/freestyle_manager.dart';
import 'package:drone_simulator/simulation/quadrotor_physics_6dof.dart';
import 'package:drone_simulator/simulation/race_manager.dart';

export 'package:drone_simulator/models/drone_profile.dart' show DroneTuning;
export 'package:drone_simulator/models/drone_state.dart' show CameraViewMode;
export 'package:drone_simulator/models/race_course.dart'
    show CourseDifficulty, CourseDirection;
export 'package:drone_simulator/simulation/freestyle_manager.dart'
    show FreestyleChallenge;
export 'package:drone_simulator/simulation/mission_manager.dart'
    show
        AerialMission,
        MissionCheckpoint,
        MissionKind,
        MissionManager,
        MissionStatus;
export 'package:drone_simulator/simulation/quadrotor_physics_6dof.dart'
    show AcroRatePreset, AcroSettings, FlightControlMode, Quat, Vec3, PhysicsSnapshot, PilotStickInput;

/// Modo de jogo do simulador.
enum SimulatorMode { freeFlight, gateRace, timeAttack, freestyle, missions }

/// Preset de horário do dia / iluminação da cena 3D.
enum TimeOfDayPreset { day, sunset, night }

/// Status operacional do simulador de voo.
enum SimulatorStatus {
  disarmed,
  takingOff,
  hovering,
  flying,
  rth,
  landing,
  landed,
  crashed,
}

/// Controlador central de simulação desacoplado da interface gráfica.
///
/// A cinemática vem do [QuadrotorPhysicsEngine] 6-DOF (240 Hz de sub-stepping),
/// inclusive nos modos automáticos, que geram entradas de stick sintéticas via
/// controlador de posição. O [FlightPhysics] legado permanece como fonte de
/// mapa/perfil e validação de geofence.
class SimulatorController extends ChangeNotifier {
  static const double fixedDt = 0.016; // 60 FPS (~16.6ms)
  static const double targetTakeoffAltitude = 10.0;
  static const double climbSpeed = 2.5;
  static const double descentSpeed = 2.0;
  static const double rthSpeed = 8.0;
  static const double rthAltitude = 15.0;

  /// Raio de colisão do corpo do drone (m).
  static const double droneRadiusMeters = 0.6;

  /// Impacto a partir daqui (m/s ≈ 12,6 km/h) derruba o drone.
  static const double crashImpactSpeedMs = 3.5;

  /// Impacto vertical no solo que caracteriza queda violenta (m/s).
  static const double hardGroundImpactMs = 5.5;

  /// Coeficiente de restituição do ricochete em obstáculos.
  static const double collisionRestitution = 0.35;

  /// Tolerância vertical para capturar o topo de um telhado caminhável (m).
  static const double roofSnapMargin = 0.45;

  final FlightPhysics physics;
  final QuadrotorPhysicsEngine sixDof;
  final RecordsRepository records;
  final FeedbackService feedback;

  Timer? _timer;

  SimulatorStatus _status = SimulatorStatus.landed;
  double _x = 0.0;
  double _y = 0.0;
  double _z = 0.0;
  double _yaw = 0.0;
  double _battery = 100.0;
  double _speedKmh = 0.0;
  bool _isArmed = false;
  CameraViewMode _cameraMode = CameraViewMode.fpv;
  bool _isMapPrimaryView = false;
  bool _isSatellite = true;
  FlightControlMode _flightMode = FlightControlMode.stabilized;
  SimulatorMode _simulatorMode = SimulatorMode.freeFlight;
  TimeOfDayPreset _timeOfDay = TimeOfDayPreset.day;
  double _windMultiplier = 1.0;
  bool _ghostEnabled = true;
  bool _lastRunWasNewRecord = false;
  bool _hasExplicitAcroOverride = false;
  double _currentGroundHeightM = 0.0;
  double _takeoffTargetAltitude = targetTakeoffAltitude;
  double _landingTargetX = 0.0;
  double _landingTargetY = 0.0;

  RaceManager? _raceManager;
  FreestyleManager? _freestyleManager;
  MissionManager? _missionManager;
  String? _selectedMissionId;
  CourseDifficulty _courseDifficulty = CourseDifficulty.medium;
  CourseDirection _courseDirection = CourseDirection.standard;
  DroneTuning _droneTuning = const DroneTuning();
  bool _hasExplicitTuningOverride = false;

  final List<GhostFrame> _recordedGhostFrames = [];
  double _ghostSampleAccum = 0.0;
  List<GhostFrame> _lastReplayFrames = const [];
  GhostTrajectory? _replayTrajectory;
  bool _isReplaying = false;
  bool _isReplayPaused = false;
  double _replayTimeSeconds = 0.0;
  double _replaySpeed = 1.0;
  CameraViewMode _preReplayCameraMode = CameraViewMode.fpv;
  double _replayPitchRad = 0.0;
  double _replayRollRad = 0.0;
  double _replayYawRad = 0.0;
  Quat _replayQuat = Quat.identity;

  double _manualThrottle = 0.0;
  double _manualYaw = 0.0;
  double _manualPitch = 0.0;
  double _manualRoll = 0.0;

  double _impactShake = 0.0;
  double _windSpeedMps = 0.0;
  double _windDirectionDeg = 116.5;
  double _stableHeadingDeg = 0.0;
  final List<(double, double)> _trailPoints = [];
  double _crashImpactSpeedKmh = 0.0;
  double _crashTimer = 0.0;
  DateTime? _lastCrashTimestamp;
  double _benchPitchDeg = 0.0;
  double _benchRollDeg = 0.0;
  PhysicsSnapshot? _lastSnapshot;
  bool _inNoFlyZone = false;
  String? _currentNfzName;
  bool _isGeofenceWarning = false;
  bool _isGeofenceBreach = false;
  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  SimulatorController({
    FlightPhysics? physics,
    QuadrotorPhysicsEngine? sixDof,
    RecordsRepository? records,
    FeedbackService? feedback,
  })  : physics = physics ?? FlightPhysics(),
        sixDof = sixDof ?? QuadrotorPhysicsEngine(),
        records = records ?? RecordsRepository(),
        feedback = feedback ?? FeedbackService() {
    _applyMapWind(this.physics.activeMap);
    if (this.records.hasSavedAcroSettings) {
      this.sixDof.acroSettings = this.records.acroSettings;
    }
    if (this.records.hasSavedDroneTuning) {
      _droneTuning = this.records.droneTuning;
    }
    _applyPhysicsParams();
    this.records.loadAll().then((_) {
      if (_disposed) return;
      if (!_hasExplicitAcroOverride && this.records.hasSavedAcroSettings) {
        this.sixDof.acroSettings = this.records.acroSettings;
      }
      if (!_hasExplicitTuningOverride && this.records.hasSavedDroneTuning) {
        _droneTuning = this.records.droneTuning;
        _applyPhysicsParams();
      }
      _syncSavedBestTimeToRaceManager();
      _safeNotify();
    });
  }

  void _applyPhysicsParams() {
    sixDof.updateParams(
      QuadrotorPhysicsEngine.paramsForProfile(
        activeProfile,
        tuning: _droneTuning,
      ),
    );
  }

  // ── Getters de estado ──
  SimulatorStatus get status => _status;
  double get x => _x;
  double get y => _y;
  double get z => _z;
  double get currentGroundHeightM => _currentGroundHeightM;
  double get altitudeAgl => max(0.0, _z - _currentGroundHeightM);
  double get yaw => _yaw;
  double get radarHeadingDeg => _stableHeadingDeg;
  List<(double, double)> get flightTrail => List.unmodifiable(_trailPoints);
  double get battery => _battery;
  double get speedKmh => _speedKmh;
  double get gimbalPitch => physics.gimbalPitch;
  double get visualPitch => _isReplaying
      ? _replayPitchRad * 180.0 / pi
      : (!_isArmed
          ? _benchPitchDeg
          : (_lastSnapshot != null
              ? _lastSnapshot!.pitchRad * 180.0 / pi
              : physics.visualPitch));
  double get visualRoll => _isReplaying
      ? _replayRollRad * 180.0 / pi
      : (!_isArmed
          ? _benchRollDeg
          : (_lastSnapshot != null
              ? _lastSnapshot!.rollRad * 180.0 / pi
              : physics.visualRoll));
  CameraViewMode get cameraMode => _cameraMode;
  bool get isMapPrimaryView => _isMapPrimaryView;
  bool get isSatellite => _isSatellite;
  FlightMap get activeMap => physics.activeMap;
  DroneProfile get activeProfile => physics.state.activeProfile;
  bool get isArmed => _isArmed;
  bool get isLanded => _status == SimulatorStatus.landed;
  bool get isHovering => _status == SimulatorStatus.hovering;
  bool get isTakingOff => _status == SimulatorStatus.takingOff;
  bool get isRTH => _status == SimulatorStatus.rth;
  bool get isLanding => _status == SimulatorStatus.landing;
  bool get isCrashed => _status == SimulatorStatus.crashed;
  bool get isRunning => _timer != null;
  double get impactShake => _impactShake;

  /// Velocidade do último impacto que causou crash (km/h).
  double get crashImpactSpeedKmh => _crashImpactSpeedKmh;

  /// Instante do último crash.
  DateTime? get lastCrashTimestamp => _lastCrashTimestamp;

  SimulatorMode get simulatorMode => _simulatorMode;
  bool get isRaceMode =>
      _simulatorMode == SimulatorMode.gateRace ||
      _simulatorMode == SimulatorMode.timeAttack;
  bool get isGateRace => _simulatorMode == SimulatorMode.gateRace;
  bool get isTimeAttack => _simulatorMode == SimulatorMode.timeAttack;
  bool get isFreestyle => _simulatorMode == SimulatorMode.freestyle;

  RaceManager? get raceManager => _raceManager;
  RaceCourse? get raceCourse => _raceManager?.course;
  FreestyleManager? get freestyleManager => _freestyleManager;
  MissionManager? get missionManager => _missionManager;
  AerialMission? get activeMission => _missionManager?.mission;
  List<AerialMission> get availableMissionsForActiveMap =>
      AerialMission.forMap(activeMap);
  MissionStatus? get missionStatus => _missionManager?.status;
  bool get isMissionMode => _simulatorMode == SimulatorMode.missions;
  bool get isMissionAutopilotActive =>
      isMissionMode && (_missionManager?.autopilotEnabled ?? false);
  CourseDifficulty get courseDifficulty => _courseDifficulty;
  CourseDirection get courseDirection => _courseDirection;
  DroneTuning get droneTuning => _droneTuning;

  RaceStatus? get raceStatus => _raceManager?.status;
  double get raceElapsedSeconds => _raceManager?.elapsedSeconds ?? 0.0;
  double get raceRemainingSeconds => _raceManager?.remainingSeconds ?? 0.0;
  int get raceGatesCleared => _raceManager?.gatesCleared ?? 0;
  double get raceScore => isFreestyle
      ? (_freestyleManager?.score ?? 0.0)
      : (isMissionMode
          ? (_missionManager?.score ?? 0.0)
          : (_raceManager?.score ?? 0.0));
  int get raceGateIndex => _raceManager?.currentGateIndex ?? 0;
  int get raceTotalGates => _raceManager?.totalGates ?? 0;
  int get raceCombo =>
      isFreestyle ? (_freestyleManager?.combo ?? 1) : (_raceManager?.combo ?? 1);
  double? get raceBestTime =>
      _raceManager?.bestTime ??
      records
          .recordFor(activeMap.id)
          .bestTimeForProfile(activeProfile.type.name);
  double get raceDistanceToGate =>
      _raceManager?.distanceToNextGate(_x, _y, _z) ?? 0.0;

  bool get hasReplayAvailable => _lastReplayFrames.length >= 2;
  bool get isReplaying => _isReplaying;
  bool get isReplayPaused => _isReplayPaused;
  double get replayTimeSeconds => _replayTimeSeconds;
  double get replayDurationSeconds => _replayTrajectory?.duration ??
      (_lastReplayFrames.length >= 2 ? _lastReplayFrames.last.t : 0.0);
  double get replayProgress => replayDurationSeconds > 0.0
      ? (_replayTimeSeconds / replayDurationSeconds).clamp(0.0, 1.0)
      : 0.0;
  double get replaySpeed => _replaySpeed;

  TimeOfDayPreset get timeOfDay => _timeOfDay;
  double get windMultiplier => _windMultiplier;
  double get windDirectionDeg => _windDirectionDeg;
  bool get ghostEnabled => _ghostEnabled;
  bool get lastRunWasNewRecord => _lastRunWasNewRecord;
  bool get audioEnabled => feedback.audioEnabled;
  bool get hapticsEnabled => feedback.hapticsEnabled;
  MapRecord get currentMapRecord => records.recordFor(activeMap.id);

  AcroSettings get acroSettings => sixDof.acroSettings;
  double get fpvUptiltDeg => sixDof.acroSettings.fpvUptiltDeg;

  bool get inNoFlyZone => _inNoFlyZone;
  String? get currentNfzName => _currentNfzName;
  bool get isGeofenceWarning => _isGeofenceWarning;
  bool get isGeofenceBreach => _isGeofenceBreach;

  /// Posição do Ghost no instante atual da corrida (quando disponível para o perfil ativo).
  GhostFrame? get currentGhostFrame {
    if (_isReplaying ||
        !_ghostEnabled ||
        _simulatorMode != SimulatorMode.gateRace) {
      return null;
    }
    if (_courseDifficulty != CourseDifficulty.medium ||
        _courseDirection != CourseDirection.standard) {
      return null;
    }
    final race = _raceManager;
    if (race == null || race.status != RaceStatus.racing) return null;
    final trajectory = records
        .recordFor(activeMap.id)
        .ghostTrajectoryForProfile(activeProfile.type.name);
    if (trajectory.isEmpty) return null;
    return trajectory.sampleAt(race.elapsedSeconds);
  }

  /// Diferença (segundos) em relação ao recorde ao concluir a corrida.
  double? get ghostDeltaSeconds {
    if (_simulatorMode != SimulatorMode.gateRace || _raceManager == null) {
      return null;
    }
    final best = raceBestTime;
    if (best == null || _raceManager!.status != RaceStatus.finished) return null;
    return _raceManager!.elapsedSeconds - best;
  }

  FlightControlMode get flightMode => _flightMode;
  String get flightModeLabel {
    switch (_flightMode) {
      case FlightControlMode.stabilized:
        return 'NORMAL';
      case FlightControlMode.sport:
        return 'SPORT';
      case FlightControlMode.acro:
        return 'ACRO';
    }
  }

  /// Inclinação real (radianos) e quatérnio vindos do motor 6-DOF (ou do replay).
  Quat get orientationQuat => _isReplaying
      ? _replayQuat
      : (_lastSnapshot?.orientation ?? Quat.identity);
  double get pitchRad =>
      _isReplaying ? _replayPitchRad : (_lastSnapshot?.pitchRad ?? 0.0);
  double get rollRad =>
      _isReplaying ? _replayRollRad : (_lastSnapshot?.rollRad ?? 0.0);
  double get yawRad =>
      _isReplaying ? _replayYawRad : (_lastSnapshot?.yawRad ?? 0.0);

  /// Rotação normalizada dos 4 motores [FR, RL, FL, RR].
  List<double> get motorNormalizedRpm => _isReplaying
      ? (_isReplayPaused
          ? const [0.0, 0.0, 0.0, 0.0]
          : const [0.68, 0.68, 0.68, 0.68])
      : (_lastSnapshot?.motorNormalizedRpm ?? const [0.0, 0.0, 0.0, 0.0]);

  double get windSpeedMps => _windSpeedMps;
  bool get inVortexRingState => _lastSnapshot?.inVortexRingState ?? false;
  double get groundEffectFactor => _lastSnapshot?.groundEffectFactor ?? 1.0;

  DroneState get state {
    final snapshot = _lastSnapshot;
    return physics.state.copyWith(
      position: physics.state.position,
      altitude: _z,
      speedKmh: _speedKmh,
      verticalSpeedMs: snapshot?.verticalSpeedMps ?? 0.0,
      velocityEastMs: snapshot?.velocity.x ?? 0.0,
      velocityNorthMs: snapshot?.velocity.y ?? 0.0,
      pitch: _lastSnapshot?.pitchRad ?? physics.state.pitch,
      roll: _lastSnapshot?.rollRad ?? physics.state.roll,
      batteryPercent: _battery,
      isCrashed: _status == SimulatorStatus.crashed,
      impactShake: _impactShake,
      motorNormalizedRpm: motorNormalizedRpm,
      rollRad: rollRad,
      pitchRad: pitchRad,
      yawRad: yawRad,
      windSpeedMps: _windSpeedMps,
      windSpeedKmh: _windSpeedMps * 3.6,
      windDirectionDeg: _windDirectionDeg,
      inVortexRingState: inVortexRingState,
      crashImpactSpeedKmh: _crashImpactSpeedKmh,
      lastCrashTimestamp: _lastCrashTimestamp,
      inNoFlyZone: _inNoFlyZone,
      isNoFlyWarning: _inNoFlyZone,
      currentNfzName: _currentNfzName,
      isGeofenceWarning: _isGeofenceWarning,
      isGeofenceBreach: _isGeofenceBreach,
    );
  }

  /// Configura todos os parâmetros de partida a partir da Página Inicial.
  void configureSession({
    required SimulatorMode mode,
    required FlightMap map,
    required DroneProfile profile,
    required FlightControlMode flightMode,
    required TimeOfDayPreset timeOfDay,
    CourseDifficulty courseDifficulty = CourseDifficulty.medium,
    CourseDirection courseDirection = CourseDirection.standard,
    String? missionId,
    bool startMissionAutopilot = false,
    DroneTuning? droneTuning,
  }) {
    physics.selectMap(map);
    physics.selectProfile(profile);
    if (droneTuning != null) {
      _droneTuning = droneTuning;
      _hasExplicitTuningOverride = true;
    }
    _applyPhysicsParams();
    _timeOfDay = timeOfDay;
    _flightMode = flightMode;
    _courseDifficulty = courseDifficulty;
    _courseDirection = courseDirection;
    if (missionId != null && missionId.isNotEmpty) {
      _selectedMissionId = missionId;
    }
    if (flightMode == FlightControlMode.acro &&
        mode == SimulatorMode.freestyle &&
        !_hasExplicitAcroOverride &&
        !records.hasSavedAcroSettings) {
      sixDof.acroSettings =
          AcroSettings.forPreset(AcroRatePreset.freestyle);
    }
    _applyMapWind(map);
    setSimulatorMode(mode);
    if (mode == SimulatorMode.missions && startMissionAutopilot) {
      setMissionAutopilot(true);
    }
  }

  /// Alterna entre Voo Livre e Modo Jogo (corrida de portais).
  void toggleSimulatorMode() {
    if (_simulatorMode == SimulatorMode.freeFlight) {
      setSimulatorMode(SimulatorMode.gateRace);
    } else {
      setSimulatorMode(SimulatorMode.freeFlight);
    }
  }

  /// Define explicitamente qualquer um dos modos de jogo.
  void setSimulatorMode(SimulatorMode mode) {
    _simulatorMode = mode;
    _lastRunWasNewRecord = false;
    _recordedGhostFrames.clear();
    _ghostSampleAccum = 0.0;

    switch (mode) {
      case SimulatorMode.freeFlight:
        _raceManager = null;
        _freestyleManager = null;
        _missionManager = null;
        break;
      case SimulatorMode.gateRace:
        _freestyleManager = null;
        _missionManager = null;
        _raceManager = _createRaceManager(activeMap, timeAttack: false)..start();
        _syncSavedBestTimeToRaceManager();
        break;
      case SimulatorMode.timeAttack:
        _freestyleManager = null;
        _missionManager = null;
        _raceManager = _createRaceManager(activeMap, timeAttack: true)..start();
        break;
      case SimulatorMode.freestyle:
        _raceManager = null;
        _missionManager = null;
        _freestyleManager = _createFreestyleManager()..start();
        break;
      case SimulatorMode.missions:
        _raceManager = null;
        _freestyleManager = null;
        final mission = _resolveSelectedMissionFor(activeMap);
        _missionManager = _createMissionManager(mission)..start();
        break;
    }
    reset(preserveFlightMode: true);
    if (mode == SimulatorMode.missions && _missionManager != null) {
      _applyMissionRecommendedWind(_missionManager!.mission);
    }
  }

  AerialMission _resolveSelectedMissionFor(FlightMap map) {
    final missions = AerialMission.forMap(map);
    if (_selectedMissionId != null) {
      for (final m in missions) {
        if (m.id == _selectedMissionId) return m;
      }
    }
    _selectedMissionId = missions.first.id;
    return missions.first;
  }

  void _applyMissionRecommendedWind(AerialMission mission) {
    if (mission.recommendedWindMultiplier > 1.0 &&
        (_windMultiplier - 1.0).abs() < 0.05) {
      _windMultiplier = mission.recommendedWindMultiplier;
      _applyMapWind(activeMap);
    }
  }

  RaceManager _createRaceManager(FlightMap map, {required bool timeAttack}) {
    return RaceManager(
      course: RaceCourse.forMap(
        map,
        difficulty: _courseDifficulty,
        direction: _courseDirection,
      ),
      timeAttackMode: timeAttack,
      onGatePassed: (combo, _) => feedback.triggerGatePassed(combo),
      onFinished: _handleRaceFinished,
    );
  }

  FreestyleManager _createFreestyleManager() {
    return FreestyleManager(
      challenge: FreestyleChallenge.forMapId(activeMap.id),
      onTrick: (_, points, __) => feedback.triggerTrick(points),
      onFinished: _handleFreestyleFinished,
      onChallengeCompleted: (_) => feedback.triggerFinish(),
    );
  }

  MissionManager _createMissionManager(AerialMission mission) {
    return MissionManager(
      mission: mission,
      onCheckpointReached: (idx, _) => feedback.triggerGatePassed(idx + 1),
      onFinished: _handleMissionFinished,
      onFailed: (_, __) => feedback.triggerWarning(),
    );
  }

  void _handleMissionFinished(MissionManager manager) {
    feedback.triggerFinish();
    records
        .saveMissionCompleted(
      mapId: manager.mission.mapId,
      missionId: manager.mission.id,
    )
        .then((_) {
      if (_disposed) return;
      _safeNotify();
    });
  }

  void _syncSavedBestTimeToRaceManager() {
    final race = _raceManager;
    if (race == null || race.timeAttackMode) return;
    final saved = records
        .recordFor(activeMap.id)
        .bestTimeForProfile(activeProfile.type.name);
    if (saved != null) {
      race.bestTimes[activeMap.id] = saved;
    } else {
      race.bestTimes.remove(activeMap.id);
    }
  }

  void _clearReplayState({bool clearFrames = false}) {
    _isReplaying = false;
    _isReplayPaused = false;
    _replayTimeSeconds = 0.0;
    _replaySpeed = 1.0;
    _replayTrajectory = null;
    _replayPitchRad = 0.0;
    _replayRollRad = 0.0;
    _replayYawRad = 0.0;
    _replayQuat = Quat.identity;
    if (clearFrames) {
      _lastReplayFrames = const [];
    }
  }

  /// Inicia a reprodução em replay da última corrida concluída.
  bool startReplay({CameraViewMode cameraMode = CameraViewMode.thirdPerson}) {
    if (!hasReplayAvailable) return false;
    _preReplayCameraMode = _cameraMode;
    _cameraMode = cameraMode;
    _replayTrajectory = GhostTrajectory(_lastReplayFrames);
    _isReplaying = true;
    _isReplayPaused = false;
    _replayTimeSeconds = 0.0;
    _replaySpeed = 1.0;
    _applyReplaySample(0.0);
    notifyListeners();
    return true;
  }

  /// Alterna entre pausar e retomar o replay (reinicia se estiver no fim).
  void toggleReplayPause() {
    if (!_isReplaying) return;
    final dur = replayDurationSeconds;
    if (_isReplayPaused && dur > 0.0 && _replayTimeSeconds >= dur - 1e-4) {
      _replayTimeSeconds = 0.0;
      _isReplayPaused = false;
      _applyReplaySample(0.0);
    } else {
      _isReplayPaused = !_isReplayPaused;
    }
    notifyListeners();
  }

  /// Salta para o instante [seconds] na linha do tempo do replay.
  void seekReplay(double seconds) {
    if (!_isReplaying) return;
    _replayTimeSeconds = seconds.clamp(0.0, replayDurationSeconds);
    _applyReplaySample(_replayTimeSeconds);
    notifyListeners();
  }

  /// Cicla a velocidade de reprodução do replay: 1.0x → 2.0x → 0.5x → 1.0x.
  void cycleReplaySpeed() {
    if (!_isReplaying) return;
    if (_replaySpeed == 1.0) {
      _replaySpeed = 2.0;
    } else if (_replaySpeed == 2.0) {
      _replaySpeed = 0.5;
    } else {
      _replaySpeed = 1.0;
    }
    notifyListeners();
  }

  /// Reinicia o replay a partir de t = 0.0 s.
  void restartReplay() {
    if (!_isReplaying) return;
    _replayTimeSeconds = 0.0;
    _isReplayPaused = false;
    _applyReplaySample(0.0);
    notifyListeners();
  }

  /// Encerra o replay e retorna ao estado pós-corrida anterior.
  void stopReplay() {
    if (!_isReplaying) return;
    _isReplaying = false;
    _isReplayPaused = false;
    _cameraMode = _preReplayCameraMode;
    notifyListeners();
  }

  void _applyReplaySample(double t) {
    final trajectory = _replayTrajectory;
    if (trajectory == null || trajectory.isEmpty) return;
    final frame = trajectory.sampleAt(t);
    if (frame == null) return;

    _x = frame.x;
    _y = frame.y;
    _z = frame.z;
    _replayPitchRad = frame.pitchRad;
    _replayRollRad = frame.rollRad;
    _replayYawRad = frame.yawRad;
    _replayQuat = Quat.fromEuler(
      pitch: frame.pitchRad,
      roll: frame.rollRad,
      yaw: frame.yawRad,
    );
    _yaw = ((-frame.yawRad * 180.0 / pi) % 360.0 + 360.0) % 360.0;
    _stableHeadingDeg = _yaw;
    _currentGroundHeightM = _computeGroundHeightAt(_x, _y, _z);

    final dur = trajectory.duration;
    final tPrev = max(0.0, t - 0.05);
    final tNext = min(dur, t + 0.05);
    final span = tNext - tPrev;
    if (span > 1e-4) {
      final a = trajectory.sampleAt(tPrev)!;
      final b = trajectory.sampleAt(tNext)!;
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final dz = b.z - a.z;
      _speedKmh = (sqrt(dx * dx + dy * dy + dz * dz) / span) * 3.6;
    } else {
      _speedKmh = 0.0;
    }
  }

  void _handleRaceFinished(RaceManager manager) {
    feedback.triggerFinish();
    final framesCopy = List<GhostFrame>.from(_recordedGhostFrames);
    if (framesCopy.isEmpty ||
        (manager.elapsedSeconds - framesCopy.last.t) > 1e-4) {
      framesCopy.add(GhostFrame(
        t: manager.elapsedSeconds,
        x: _x,
        y: _y,
        z: _z,
        pitchRad: pitchRad,
        rollRad: rollRad,
        yawRad: yawRad,
      ));
    }
    if (framesCopy.length == 1) {
      if (framesCopy.first.t > 0.0) {
        framesCopy.insert(
          0,
          GhostFrame(
            t: 0.0,
            x: framesCopy.first.x,
            y: framesCopy.first.y,
            z: framesCopy.first.z,
            pitchRad: framesCopy.first.pitchRad,
            rollRad: framesCopy.first.rollRad,
            yawRad: framesCopy.first.yawRad,
          ),
        );
      } else {
        framesCopy.add(
          GhostFrame(
            t: max(0.1, manager.elapsedSeconds),
            x: _x,
            y: _y,
            z: _z,
            pitchRad: pitchRad,
            rollRad: rollRad,
            yawRad: yawRad,
          ),
        );
      }
    }
    _lastReplayFrames = List<GhostFrame>.unmodifiable(framesCopy);

    if (manager.timeAttackMode) {
      records
          .saveTimeAttackResult(
        mapId: manager.course.mapId,
        gatesCleared: manager.gatesCleared,
        score: manager.score,
        bestCombo: manager.bestCombo,
      )
          .then((res) {
        if (_disposed) return;
        _lastRunWasNewRecord = res.isNewRecord;
        _safeNotify();
      });
    } else {
      final isStandardCourse =
          _courseDifficulty == CourseDifficulty.medium &&
              _courseDirection == CourseDirection.standard;
      records
          .saveRaceResult(
        mapId: manager.course.mapId,
        profileId: activeProfile.type.name,
        elapsedSeconds: manager.elapsedSeconds,
        score: manager.score,
        bestCombo: manager.bestCombo,
        ghostFrames: isStandardCourse ? framesCopy : null,
      )
          .then((res) {
        if (_disposed) return;
        _lastRunWasNewRecord = res.isNewRecord;
        final profileBest =
            res.record.bestTimeForProfile(activeProfile.type.name);
        if (profileBest != null) {
          manager.bestTimes[manager.course.mapId] = profileBest;
        }
        _safeNotify();
      });
    }
  }

  void _handleFreestyleFinished(FreestyleManager manager) {
    feedback.triggerFinish();
    records
        .saveFreestyleResult(
      mapId: activeMap.id,
      score: manager.score,
      bestCombo: manager.bestCombo,
      challengeCompleted: manager.challengeCompleted,
    )
        .then((res) {
      if (_disposed) return;
      _lastRunWasNewRecord = res.isNewRecord;
      _safeNotify();
    });
  }

  /// Respawn imediato após queda.
  void respawn() {
    if (_simulatorMode == SimulatorMode.freestyle) {
      _freestyleManager?.start();
    } else if (_simulatorMode == SimulatorMode.missions) {
      _missionManager?.restart(autopilot: false);
    }
    reset(preserveFlightMode: true);
    armAndTakeoff();
    notifyListeners();
  }

  /// Reinicia a corrida ou sessão atual no mesmo circuito.
  void restartRace() {
    _lastRunWasNewRecord = false;
    _recordedGhostFrames.clear();
    _ghostSampleAccum = 0.0;
    if (_simulatorMode == SimulatorMode.freestyle) {
      _freestyleManager ??= _createFreestyleManager();
      _freestyleManager!.start();
    } else if (_simulatorMode == SimulatorMode.missions) {
      _missionManager ??=
          _createMissionManager(_resolveSelectedMissionFor(activeMap));
      _missionManager!.restart(autopilot: false);
    } else {
      _raceManager ??= _createRaceManager(
        activeMap,
        timeAttack: _simulatorMode == SimulatorMode.timeAttack,
      );
      _raceManager!.restart();
    }
    reset(preserveFlightMode: true);
  }

  /// Reseta o voo mantendo o circuito atual.
  void resetRace() {
    reset(preserveFlightMode: true);
  }

  /// Alterna entre NORMAL → SPORT → ACRO.
  void cycleFlightMode() {
    switch (_flightMode) {
      case FlightControlMode.stabilized:
        _flightMode = FlightControlMode.sport;
        break;
      case FlightControlMode.sport:
        _flightMode = FlightControlMode.acro;
        break;
      case FlightControlMode.acro:
        _flightMode = FlightControlMode.stabilized;
        break;
    }
    notifyListeners();
  }

  void setFlightMode(FlightControlMode mode) {
    if (_flightMode != mode) {
      _flightMode = mode;
      notifyListeners();
    }
  }

  /// Alterna o modo de câmera entre 1ª Pessoa (FPV) e 3ª Pessoa.
  void toggleCameraMode() {
    _cameraMode = _cameraMode == CameraViewMode.fpv
        ? CameraViewMode.thirdPerson
        : CameraViewMode.fpv;
    notifyListeners();
  }

  void setCameraMode(CameraViewMode mode) {
    if (_cameraMode != mode) {
      _cameraMode = mode;
      notifyListeners();
    }
  }

  void togglePrimaryView() {
    _isMapPrimaryView = !_isMapPrimaryView;
    notifyListeners();
  }

  void setMapPrimaryView(bool isPrimary) {
    if (_isMapPrimaryView != isPrimary) {
      _isMapPrimaryView = isPrimary;
      notifyListeners();
    }
  }

  void toggleTileLayer() {
    _isSatellite = !_isSatellite;
    notifyListeners();
  }

  void setSatellite(bool value) {
    if (_isSatellite != value) {
      _isSatellite = value;
      notifyListeners();
    }
  }

  /// Seleciona o perfil físico do drone (Mini 249g, Pro Cine 900g, FPV Racer).
  void selectDroneProfile(DroneProfile profile) {
    physics.selectProfile(profile);
    _applyPhysicsParams();
    _syncSavedBestTimeToRaceManager();
    notifyListeners();
  }

  /// Configura dificuldade e direção (padrão ou reversa) do circuito.
  void setCourseVariant({
    CourseDifficulty? difficulty,
    CourseDirection? direction,
  }) {
    final nextDiff = difficulty ?? _courseDifficulty;
    final nextDir = direction ?? _courseDirection;
    if (nextDiff == _courseDifficulty && nextDir == _courseDirection) return;
    _courseDifficulty = nextDiff;
    _courseDirection = nextDir;
    if (isRaceMode) {
      _raceManager = _createRaceManager(
        activeMap,
        timeAttack: _simulatorMode == SimulatorMode.timeAttack,
      )..start();
      _syncSavedBestTimeToRaceManager();
      reset(preserveFlightMode: true);
      return;
    }
    notifyListeners();
  }

  /// Atualiza ajustes de aparência 3D, FOV FPV, peso e bateria da Garagem.
  void setDroneTuning(DroneTuning tuning, {bool persist = true}) {
    _hasExplicitTuningOverride = true;
    _droneTuning = tuning;
    _applyPhysicsParams();
    if (persist) {
      records.saveDroneTuning(tuning);
    }
    notifyListeners();
  }

  /// Seleciona e (se em modo Missões) inicia uma missão aérea no mapa ativo.
  void selectMission(AerialMission mission, {bool autopilot = false}) {
    _selectedMissionId = mission.id;
    _missionManager = _createMissionManager(mission);
    if (_simulatorMode == SimulatorMode.missions) {
      _missionManager!.start(autopilot: autopilot);
      _applyMissionRecommendedWind(mission);
      reset(preserveFlightMode: true);
      if (autopilot) {
        armAndTakeoff();
      }
      return;
    }
    notifyListeners();
  }

  /// Ativa ou desativa o piloto automático da missão atual.
  void setMissionAutopilot(bool enabled) {
    if (_simulatorMode != SimulatorMode.missions) return;
    final mm = _missionManager;
    if (mm == null) return;
    if (enabled && (mm.isCompleted || mm.isFailed)) {
      mm.restart(autopilot: true);
      reset(preserveFlightMode: true);
    } else {
      mm.setAutopilot(enabled);
    }
    if (mm.autopilotEnabled && _status == SimulatorStatus.landed) {
      armAndTakeoff();
      return;
    }
    notifyListeners();
  }

  void toggleMissionAutopilot() {
    setMissionAutopilot(!isMissionAutopilotActive);
  }

  /// Seleciona o horário do dia / iluminação da cena 3D.
  void setTimeOfDay(TimeOfDayPreset preset) {
    if (_timeOfDay != preset) {
      _timeOfDay = preset;
      notifyListeners();
    }
  }

  /// Configura intensidade do vento (0.0 = Calmo, 1.0 = Padrão, 1.8 = Rajadas Fortes).
  void setWindMultiplier(double multiplier) {
    _windMultiplier = multiplier.clamp(0.0, 2.5);
    _applyMapWind(activeMap);
    notifyListeners();
  }

  /// Ajusta parâmetros avançados do modo Acro.
  void setAcroSettings(AcroSettings settings, {bool persist = true}) {
    _hasExplicitAcroOverride = true;
    sixDof.acroSettings = settings;
    if (persist) {
      records.saveAcroSettings(settings);
    }
    notifyListeners();
  }

  /// Aplica um preset rápido de agilidade Acro (Suave, Padrão ou Freestyle).
  void setAcroPreset(AcroRatePreset preset, {bool persist = true}) {
    final updated = AcroSettings.forPreset(
      preset,
      fpvUptiltDeg: sixDof.acroSettings.fpvUptiltDeg,
      coordinatedTurn: sixDof.acroSettings.coordinatedTurn,
      floatingJoysticks: sixDof.acroSettings.floatingJoysticks,
      manualAcroThrottle: sixDof.acroSettings.manualAcroThrottle,
    );
    setAcroSettings(updated, persist: persist);
  }

  void setGhostEnabled(bool enabled) {
    if (_ghostEnabled != enabled) {
      _ghostEnabled = enabled;
      notifyListeners();
    }
  }

  void setAudioEnabled(bool enabled) {
    if (feedback.audioEnabled != enabled) {
      feedback.audioEnabled = enabled;
      notifyListeners();
    }
  }

  void setHapticsEnabled(bool enabled) {
    if (feedback.hapticsEnabled != enabled) {
      feedback.hapticsEnabled = enabled;
      notifyListeners();
    }
  }

  /// Seleciona um cenário de decolagem, redefine o Home e reseta o voo.
  void selectTakeoffLocation(FlightMap map) {
    physics.selectMap(map);
    _applyMapWind(map);
    reset();
    if (_simulatorMode == SimulatorMode.gateRace ||
        _simulatorMode == SimulatorMode.timeAttack) {
      _raceManager = _createRaceManager(
        map,
        timeAttack: _simulatorMode == SimulatorMode.timeAttack,
      )..start();
      _syncSavedBestTimeToRaceManager();
    } else if (_simulatorMode == SimulatorMode.freestyle) {
      _freestyleManager = _createFreestyleManager()..start();
    } else if (_simulatorMode == SimulatorMode.missions) {
      _selectedMissionId = null;
      final mission = _resolveSelectedMissionFor(map);
      _missionManager = _createMissionManager(mission)..start();
      _applyMissionRecommendedWind(mission);
    }
  }

  /// Configura vento e turbulência específicos de cada cenário.
  void _applyMapWind(FlightMap map) {
    late Vec3 base;
    late double turb;
    switch (WorldGenerator.scenarioFor(map)) {
      case WorldScenario.urban:
        base = const Vec3(2.0, -1.0, 0.0);
        turb = 1.1;
        break;
      case WorldScenario.forest:
        base = const Vec3(1.2, 0.6, 0.0);
        turb = 0.7;
        break;
      case WorldScenario.canyon:
        base = const Vec3(4.2, -1.8, 0.2);
        turb = 1.5;
        break;
    }
    sixDof.baseWindWorld =
        _windMultiplier == 1.0 ? base : base * _windMultiplier;
    sixDof.turbulenceIntensity =
        _windMultiplier == 1.0 ? turb : turb * _windMultiplier;
    _windSpeedMps = sixDof.baseWindWorld.length;
    if (_windSpeedMps > 0.01) {
      _windDirectionDeg =
          (atan2(sixDof.baseWindWorld.x, sixDof.baseWindWorld.y) *
                      180.0 /
                      pi +
                  360.0) %
              360.0;
    }
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      update(fixedDt);
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    physics.dispose();
    super.dispose();
  }

  /// Arma os motores e sobe automaticamente até 10 m acima da superfície atual.
  void armAndTakeoff() {
    if (_status == SimulatorStatus.crashed) {
      reset();
    }
    _currentGroundHeightM = _computeGroundHeightAt(_x, _y, _z);
    _takeoffTargetAltitude = _currentGroundHeightM + targetTakeoffAltitude;
    _isArmed = true;
    _status = SimulatorStatus.takingOff;
    sixDof.reset(
      position: Vec3(_x, _y, max(_z, _currentGroundHeightM + 0.03)),
      yawRad: -_yaw * pi / 180.0,
      batteryPercent: _battery,
    );
    sixDof.setArmed(true);
    notifyListeners();
  }

  /// Inicia a descida até a superfície abaixo do drone (solo ou telhado).
  void land() {
    if (_status == SimulatorStatus.landed ||
        _status == SimulatorStatus.disarmed ||
        _status == SimulatorStatus.crashed) {
      return;
    }
    _landingTargetX = _x;
    _landingTargetY = _y;
    _status = SimulatorStatus.landing;
    notifyListeners();
  }

  /// Retorna ao Home com piloto automático e pousa.
  void triggerRTH() {
    if (_status == SimulatorStatus.landed ||
        _status == SimulatorStatus.landing ||
        _status == SimulatorStatus.crashed) {
      return;
    }
    _status = SimulatorStatus.rth;
    notifyListeners();
  }

  /// Reseta o simulador, a física 6-DOF e a bateria.
  void reset({bool preserveFlightMode = false}) {
    _clearReplayState(clearFrames: true);
    _status = SimulatorStatus.landed;
    _x = 0.0;
    _y = 0.0;
    _z = 0.0;
    _currentGroundHeightM = 0.0;
    _takeoffTargetAltitude = targetTakeoffAltitude;
    _landingTargetX = 0.0;
    _landingTargetY = 0.0;
    _yaw = 0.0;
    _stableHeadingDeg = 0.0;
    _trailPoints.clear();
    _speedKmh = 0.0;
    _manualThrottle = 0.0;
    _manualYaw = 0.0;
    _manualPitch = 0.0;
    _manualRoll = 0.0;
    _battery = 100.0;
    _isArmed = false;
    _cameraMode = CameraViewMode.fpv;
    _isMapPrimaryView = false;
    _impactShake = 0.0;
    _inNoFlyZone = false;
    _currentNfzName = null;
    _isGeofenceWarning = false;
    _isGeofenceBreach = false;
    _recordedGhostFrames.clear();
    _ghostSampleAccum = 0.0;
    if (!preserveFlightMode) {
      _flightMode = FlightControlMode.stabilized;
    }
    physics.resetBattery();
    physics.selectMap(physics.activeMap);
    sixDof.reset(
      position: Vec3.zero,
      yawRad: 0.0,
      batteryPercent: 100.0,
    );
    sixDof.setArmed(false);
    _lastSnapshot = sixDof.snapshot;
    _applyMapWind(physics.activeMap);
    notifyListeners();
  }

  /// Define entradas manuais analógicas (Modo 2).
  void setManualInput({
    double throttle = 0.0,
    double yaw = 0.0,
    double pitch = 0.0,
    double roll = 0.0,
  }) {
    _manualThrottle = throttle.clamp(-1.0, 1.0);
    _manualYaw = yaw.clamp(-1.0, 1.0);
    _manualPitch = pitch.clamp(-1.0, 1.0);
    _manualRoll = roll.clamp(-1.0, 1.0);
    physics.setManualInput(_manualThrottle, _manualYaw, _manualPitch, _manualRoll);

    if (isMissionAutopilotActive &&
        (_manualThrottle.abs() > 0.15 ||
            _manualYaw.abs() > 0.15 ||
            _manualPitch.abs() > 0.15 ||
            _manualRoll.abs() > 0.15)) {
      _missionManager?.setAutopilot(false);
    }

    if ((_status == SimulatorStatus.hovering ||
            _status == SimulatorStatus.takingOff) &&
        (_manualThrottle.abs() > 0.05 ||
            _manualYaw.abs() > 0.05 ||
            _manualPitch.abs() > 0.05 ||
            _manualRoll.abs() > 0.05)) {
      _status = SimulatorStatus.flying;
    }
  }

  /// Posiciona o drone (usado por testes e teleporte).
  void setPosition(double newX, double newY, [double? newZ]) {
    _x = newX;
    _y = newY;
    if (newZ != null) _z = newZ;
    _currentGroundHeightM = _computeGroundHeightAt(_x, _y, _z);
    _syncSixDofPosition();
    notifyListeners();
  }

  void setYaw(double newYaw) {
    _yaw = (newYaw % 360.0 + 360.0) % 360.0;
    _syncSixDofPosition();
    notifyListeners();
  }

  void _syncSixDofPosition() {
    sixDof.applyExternalCollisionCorrection(
      correctedPosition: Vec3(_x, _y, _z),
      correctedVelocity: const Vec3(0, 0, 0),
    );
    _lastSnapshot = sixDof.snapshot;
  }

  void setBattery(double percent) {
    _battery = percent.clamp(0.0, 100.0);
    _checkBatteryFailSafe();
    notifyListeners();
  }

  void setGimbalPitch(double degrees) {
    physics.setGimbalPitch(degrees);
    notifyListeners();
  }

  void adjustGimbalPitch(double deltaDegrees) {
    physics.adjustGimbalPitch(deltaDegrees);
    notifyListeners();
  }

  void _checkBatteryFailSafe() {
    if (_battery < 15.0 &&
        _status != SimulatorStatus.rth &&
        _status != SimulatorStatus.landing &&
        _status != SimulatorStatus.landed &&
        _isArmed) {
      triggerRTH();
    }
  }

  double _computeGroundHeightAt(
    double east,
    double north,
    double currentAltitude,
  ) {
    double surface = 0.0;
    final obstacles = WorldGenerator.generateFor(activeMap);
    for (final obstacle in obstacles) {
      if (!obstacle.isWalkableRoof) continue;
      if (!obstacle.coversPoint(east, north)) continue;
      if (currentAltitude >= obstacle.height - roofSnapMargin &&
          obstacle.height > surface) {
        surface = obstacle.height;
      }
    }
    return surface;
  }

  // ────────────────────────────────────────────────────────────
  // Loop principal
  // ────────────────────────────────────────────────────────────

  /// Avança a simulação 6-DOF com delta time fixo (0.016s).
  void update([double dt = fixedDt]) {
    if (_isReplaying) {
      if (!_isReplayPaused) {
        final dur = replayDurationSeconds;
        _replayTimeSeconds += dt * _replaySpeed;
        if (_replayTimeSeconds >= dur) {
          _replayTimeSeconds = dur;
          _isReplayPaused = true;
        }
      }
      _applyReplaySample(_replayTimeSeconds);
      notifyListeners();
      return;
    }

    if (_isArmed && _status != SimulatorStatus.landed) {
      _checkBatteryFailSafe();
    }

    // Em solo/desarmado a atitude é apenas visual (bancada), como antes.
    if (!_isArmed) {
      final lerpFactor = (dt * 10.0).clamp(0.0, 1.0);
      _benchPitchDeg += ((_manualPitch * -25.0) - _benchPitchDeg) * lerpFactor;
      _benchRollDeg += ((_manualRoll * 25.0) - _benchRollDeg) * lerpFactor;
      if (_manualPitch == 0.0 && _benchPitchDeg.abs() < 0.05) {
        _benchPitchDeg = 0.0;
      }
      if (_manualRoll == 0.0 && _benchRollDeg.abs() < 0.05) {
        _benchRollDeg = 0.0;
      }
    } else {
      _benchPitchDeg = 0.0;
      _benchRollDeg = 0.0;
    }

    final input = _buildStickInput();
    final previousVz = _lastSnapshot?.velocity.z ?? 0.0;
    final groundHeightM = _computeGroundHeightAt(_x, _y, _z);
    _currentGroundHeightM = groundHeightM;
    final effectiveMode =
        isMissionAutopilotActive ? FlightControlMode.stabilized : _flightMode;
    var snapshot = sixDof.step(
      input: input,
      dt: dt,
      mode: effectiveMode,
      groundHeightM: groundHeightM,
    );

    _applySnapshot(snapshot);
    final collision = _resolveWorldCollisions(snapshot);
    final minClearance = collision.minClearance;
    snapshot = _lastSnapshot ?? snapshot;
    _enforceGeofenceAndNfz(snapshot);
    _currentGroundHeightM = _computeGroundHeightAt(_x, _y, _z);

    // Impacto violento no solo ou telhado durante voo armado.
    if (_status != SimulatorStatus.crashed &&
        snapshot.isGrounded &&
        previousVz < -hardGroundImpactMs) {
      _triggerCrash(previousVz.abs(), const Vec3(0, 0, 1), snapshot);
    }
    _advanceStatusMachine();

    if (_status == SimulatorStatus.crashed) {
      _crashTimer += dt;
    }

    final race = _raceManager;
    if (race != null && isRaceMode) {
      if (race.status == RaceStatus.racing &&
          _status != SimulatorStatus.crashed) {
        if (_recordedGhostFrames.isEmpty) {
          _recordedGhostFrames.add(GhostFrame(
            t: race.elapsedSeconds,
            x: _x,
            y: _y,
            z: _z,
            pitchRad: pitchRad,
            rollRad: rollRad,
            yawRad: yawRad,
          ));
        }
        _ghostSampleAccum += dt;
        if (_ghostSampleAccum >= 0.10) {
          _ghostSampleAccum -= 0.10;
          _recordedGhostFrames.add(GhostFrame(
            t: race.elapsedSeconds,
            x: _x,
            y: _y,
            z: _z,
            pitchRad: pitchRad,
            rollRad: rollRad,
            yawRad: yawRad,
          ));
        }
      }
      race.update(
        dt: dt,
        x: _x,
        y: _y,
        z: _z,
        speedKmh: _speedKmh,
        crashed: _status == SimulatorStatus.crashed,
      );
    }

    final freestyle = _freestyleManager;
    if (freestyle != null && _simulatorMode == SimulatorMode.freestyle) {
      freestyle.update(
        dt: dt,
        altitude: _z,
        speedKmh: _speedKmh,
        verticalSpeedMs: snapshot.verticalSpeedMps,
        omegaPitchRadS: snapshot.angularVelocityBody.x,
        omegaRollRadS: snapshot.angularVelocityBody.y,
        omegaYawRadS: snapshot.angularVelocityBody.z,
        minObstacleClearance: minClearance,
        crashed: _status == SimulatorStatus.crashed,
        upWorldZ:
            snapshot.orientation.rotateBodyToWorld(const Vec3(0.0, 0.0, 1.0)).z,
        horizontalSpeedMs: sqrt(snapshot.velocity.x * snapshot.velocity.x +
            snapshot.velocity.y * snapshot.velocity.y),
        inTightGap: collision.inTightGap,
        underBridge: collision.underBridge,
      );
    }

    final mission = _missionManager;
    if (mission != null && _simulatorMode == SimulatorMode.missions) {
      mission.update(
        dt: dt,
        x: _x,
        y: _y,
        z: _z,
        isLanded: _status == SimulatorStatus.landed,
        isGrounded: snapshot.isGrounded,
        groundHeightM: _currentGroundHeightM,
        crashed: _status == SimulatorStatus.crashed,
        inNoFlyZone: _inNoFlyZone,
        geofenceBreach: _isGeofenceBreach,
      );
    }

    _impactShake = max(0.0, _impactShake - dt * 1.5);
    notifyListeners();
  }

  void _enforceGeofenceAndNfz(PhysicsSnapshot snapshot) {
    final validation = GeofenceValidator.validateCartesian(
      x: _x,
      y: _y,
      velocityX: snapshot.velocity.x,
      velocityY: snapshot.velocity.y,
      maxRadiusMeters: activeMap.radiusMeters,
      warningRadiusMeters: activeMap.warningRadiusMeters,
      noFlyZones: activeMap.noFlyZones,
      origin: activeMap.center,
    );

    _inNoFlyZone = validation.inNoFlyZone;
    _currentNfzName = validation.currentNfzName;
    _isGeofenceWarning = validation.isGeofenceWarning;
    _isGeofenceBreach = validation.isGeofenceBreach;

    if (validation.isGeofenceBreach &&
        _isArmed &&
        _status != SimulatorStatus.crashed &&
        _status != SimulatorStatus.landed) {
      sixDof.applyExternalCollisionCorrection(
        correctedPosition: Vec3(validation.x, validation.y, _z),
        correctedVelocity: Vec3(
          validation.velocityX,
          validation.velocityY,
          snapshot.velocity.z,
        ),
      );
      _x = validation.x;
      _y = validation.y;
      _lastSnapshot = sixDof.snapshot;
    }

    if ((_inNoFlyZone || _isGeofenceWarning) &&
        _isArmed &&
        _status != SimulatorStatus.crashed &&
        _status != SimulatorStatus.landed) {
      feedback.triggerWarning();
    }
  }

  void _applySnapshot(PhysicsSnapshot snapshot) {
    _lastSnapshot = snapshot;
    _x = snapshot.position.x;
    _y = snapshot.position.y;
    _z = snapshot.position.z;
    _yaw = ((-snapshot.yawRad * 180.0 / pi) % 360.0 + 360.0) % 360.0;
    if (snapshot.orientation.rotateBodyToWorld(const Vec3(0.0, 0.0, 1.0)).z >
        0.35) {
      _stableHeadingDeg = _yaw;
    }
    if (_isArmed && _z > 0.25) {
      if (_trailPoints.isEmpty) {
        _trailPoints.add((_x, _y));
      } else {
        final (lx, ly) = _trailPoints.last;
        final dx = _x - lx;
        final dy = _y - ly;
        if (dx * dx + dy * dy >= 6.25) {
          _trailPoints.add((_x, _y));
          if (_trailPoints.length > 45) {
            _trailPoints.removeAt(0);
          }
        }
      }
    }
    _speedKmh = snapshot.speedKmh;
    _battery = snapshot.batteryPercent;
    _windSpeedMps = snapshot.windVelocityWorld.length;
  }

  double _safeCruiseAltitudeTo(double tx, double ty, double targetZ) {
    var safeZ = targetZ;
    final sx = tx - _x;
    final sy = ty - _y;
    final segLenSq = sx * sx + sy * sy;
    final obstacles = WorldGenerator.generateFor(activeMap);
    for (final o in obstacles) {
      final clearanceR = o.isCylindrical
          ? o.radius + 3.5
          : max(o.width, o.depth) * 0.72 + 3.5;
      var t = 0.0;
      if (segLenSq > 1e-4) {
        t = (((o.x - _x) * sx + (o.y - _y) * sy) / segLenSq).clamp(0.0, 1.0);
      }
      final closestX = _x + sx * t;
      final closestY = _y + sy * t;
      final dx = o.x - closestX;
      final dy = o.y - closestY;
      if (dx * dx + dy * dy <= clearanceR * clearanceR) {
        final distToTarget = sqrt(pow(o.x - tx, 2) + pow(o.y - ty, 2));
        if (t > 0.92 && distToTarget < clearanceR && targetZ >= o.height) {
          continue;
        }
        safeZ = max(safeZ, o.height + 5.5);
      }
    }
    return safeZ.clamp(targetZ, activeMap.maxAltitudeMeters - 2.0);
  }

  /// Gera sticks sintéticos para modos automáticos (decolagem, RTH, pouso, missão autônoma).
  PilotStickInput _buildStickInput() {
    switch (_status) {
      case SimulatorStatus.takingOff:
        final throttle =
            ((_takeoffTargetAltitude - _z) * 0.6).clamp(-0.3, 1.0);
        return PilotStickInput(throttle: throttle);

      case SimulatorStatus.rth:
        // Navega para o Home com controlador de velocidade em malha fechada.
        final dx = -_x;
        final dy = -_y;
        final yawRadNow = _lastSnapshot?.yawRad ?? 0.0;
        final forwardX = -sin(yawRadNow);
        final forwardY = cos(yawRadNow);
        final rightX = cos(yawRadNow);
        final rightY = sin(yawRadNow);

        final vx = _lastSnapshot?.velocity.x ?? 0.0;
        final vy = _lastSnapshot?.velocity.y ?? 0.0;

        // Velocidade desejada proporcional à distância restante (com teto).
        final desiredVx = (dx * 1.2).clamp(-8.0, 8.0);
        final desiredVy = (dy * 1.2).clamp(-8.0, 8.0);
        final errVx = desiredVx - vx;
        final errVy = desiredVy - vy;

        final forwardError = errVx * forwardX + errVy * forwardY;
        final rightError = errVx * rightX + errVy * rightY;

        return PilotStickInput(
          throttle: ((rthAltitude - _z) * 0.4).clamp(-0.5, 1.0),
          pitch: (forwardError * 0.16).clamp(-0.6, 0.6),
          roll: (rightError * 0.16).clamp(-0.6, 0.6),
        );

      case SimulatorStatus.landing:
        // Desce mantendo correção horizontal suave sobre o ponto alvo de pouso.
        final yawRadNow = _lastSnapshot?.yawRad ?? 0.0;
        final forwardX = -sin(yawRadNow);
        final forwardY = cos(yawRadNow);
        final rightX = cos(yawRadNow);
        final rightY = sin(yawRadNow);
        final vx = _lastSnapshot?.velocity.x ?? 0.0;
        final vy = _lastSnapshot?.velocity.y ?? 0.0;

        final errVx = ((_landingTargetX - _x) * 0.9).clamp(-3.0, 3.0) - vx;
        final errVy = ((_landingTargetY - _y) * 0.9).clamp(-3.0, 3.0) - vy;

        return PilotStickInput(
          throttle: -1.0,
          pitch: ((errVx * forwardX + errVy * forwardY) * 0.12)
              .clamp(-0.4, 0.4),
          roll: ((errVx * rightX + errVy * rightY) * 0.12)
              .clamp(-0.4, 0.4),
        );

      case SimulatorStatus.hovering:
      case SimulatorStatus.flying:
        final cp = _missionManager?.activeCheckpoint;
        if (isMissionAutopilotActive && cp != null) {
          final dx = cp.x - _x;
          final dy = cp.y - _y;
          final horizDist = sqrt(dx * dx + dy * dy);
          if (cp.requireLanding && horizDist < 2.2 && _z <= cp.z + 14.0) {
            _landingTargetX = cp.x;
            _landingTargetY = cp.y;
            _status = SimulatorStatus.landing;
            return const PilotStickInput(throttle: -1.0);
          }

          final yawRadNow = _lastSnapshot?.yawRad ?? 0.0;
          final forwardX = -sin(yawRadNow);
          final forwardY = cos(yawRadNow);
          final rightX = cos(yawRadNow);
          final rightY = sin(yawRadNow);

          final vx = _lastSnapshot?.velocity.x ?? 0.0;
          final vy = _lastSnapshot?.velocity.y ?? 0.0;

          final baseTargetAlt = cp.requireLanding ? (cp.z + 5.0) : cp.z;
          final cruiseAlt = _safeCruiseAltitudeTo(cp.x, cp.y, baseTargetAlt);
          final needClimbFirst = _z < cruiseAlt - 2.5 && horizDist > 10.0;
          final maxHorizSpeed = needClimbFirst ? 1.5 : 9.0;

          final desiredVx = (dx * 1.1).clamp(-maxHorizSpeed, maxHorizSpeed);
          final desiredVy = (dy * 1.1).clamp(-maxHorizSpeed, maxHorizSpeed);
          final errVx = desiredVx - vx;
          final errVy = desiredVy - vy;

          final forwardError = errVx * forwardX + errVy * forwardY;
          final rightError = errVx * rightX + errVy * rightY;

          var yawCmd = 0.0;
          if (horizDist > 4.0) {
            final targetYawDeg =
                (atan2(dx, dy) * 180.0 / pi + 360.0) % 360.0;
            var yawErr = targetYawDeg - _yaw;
            if (yawErr > 180.0) yawErr -= 360.0;
            if (yawErr < -180.0) yawErr += 360.0;
            yawCmd = (yawErr * pi / 180.0 * 0.85).clamp(-0.6, 0.6);
          }

          return PilotStickInput(
            throttle: ((cruiseAlt - _z) * 0.55).clamp(-0.65, 1.0),
            yaw: yawCmd,
            pitch: (forwardError * 0.16).clamp(-0.6, 0.6),
            roll: (rightError * 0.16).clamp(-0.6, 0.6),
          );
        }

        return PilotStickInput(
          throttle: _manualThrottle,
          pitch: _manualPitch,
          roll: _manualRoll,
          yaw: _manualYaw,
        );

      case SimulatorStatus.disarmed:
      case SimulatorStatus.landed:
      case SimulatorStatus.crashed:
        return PilotStickInput.neutral;
    }
  }

  void _advanceStatusMachine() {
    switch (_status) {
      case SimulatorStatus.takingOff:
        if (_z >= _takeoffTargetAltitude - 0.15) {
          _status = SimulatorStatus.hovering;
        }
        break;

      case SimulatorStatus.rth:
        if (sqrt(_x * _x + _y * _y) < 1.5) {
          // Alinhado ao Home: encaixa o ponto de pouso e inicia a descida.
          _x = 0.0;
          _y = 0.0;
          _landingTargetX = 0.0;
          _landingTargetY = 0.0;
          _status = SimulatorStatus.landing;
        }
        break;

      case SimulatorStatus.landing:
        if (_z <= _currentGroundHeightM + 0.08) {
          _z = _currentGroundHeightM;
          // Pouso automático no solo: encaixa no Home se já estiver próximo.
          if (_currentGroundHeightM <= 0.01 && sqrt(_x * _x + _y * _y) <= 2.5) {
            _x = 0.0;
            _y = 0.0;
          }
          _status = SimulatorStatus.landed;
          _isArmed = false;
          sixDof.setArmed(false);
        }
        break;

      case SimulatorStatus.crashed:
        // Mantém o card de queda visível por um instante antes de encerrar.
        if (_z <= _currentGroundHeightM + 0.02 && _crashTimer >= 0.5) {
          _z = _currentGroundHeightM;
          _status = SimulatorStatus.landed;
          _isArmed = false;
        }
        break;

      case SimulatorStatus.hovering:
      case SimulatorStatus.flying:
      case SimulatorStatus.disarmed:
      case SimulatorStatus.landed:
        break;
    }
  }

  // ────────────────────────────────────────────────────────────
  // Colisão com obstáculos 3D
  // ────────────────────────────────────────────────────────────

  ({double minClearance, bool inTightGap, bool underBridge})
      _resolveWorldCollisions(PhysicsSnapshot snapshot) {
    if (_status == SimulatorStatus.crashed ||
        _status == SimulatorStatus.landed ||
        _status == SimulatorStatus.disarmed) {
      return (minClearance: 999.0, inTightGap: false, underBridge: false);
    }

    final obstacles = WorldGenerator.generateFor(activeMap);
    if (obstacles.isEmpty) {
      return (minClearance: 999.0, inTightGap: false, underBridge: false);
    }

    var east = snapshot.position.x;
    var north = snapshot.position.y;
    var altitude = snapshot.position.z;
    final velocity = snapshot.velocity;

    double velocityEast = velocity.x;
    double velocityNorth = velocity.y;

    bool collided = false;
    double impactSpeed = 0.0;
    double normalX = 0.0;
    double normalY = 0.0;
    double minClearance = 999.0;
    final trackClearance = _simulatorMode == SimulatorMode.freestyle;
    final nearObstacleDirs = <(double, double)>[];

    for (final WorldObstacle obstacle in obstacles) {
      if (trackClearance && altitude < obstacle.height + 3.0) {
        final dxObs = obstacle.x - east;
        final dyObs = obstacle.y - north;
        final distCenter = sqrt(dxObs * dxObs + dyObs * dyObs);
        final approxRadius = obstacle.isCylindrical
            ? obstacle.radius
            : max(obstacle.width, obstacle.depth) * 0.5;
        final clearance = distCenter - approxRadius;
        if (clearance < minClearance) {
          minClearance = clearance;
        }
        if (clearance < 12.0 &&
            altitude < obstacle.height + 1.5 &&
            distCenter > 1e-3) {
          nearObstacleDirs.add((dxObs / distCenter, dyObs / distCenter));
        }
      }

      if (altitude >= obstacle.height - 0.05) continue;
      if (obstacle.isWalkableRoof &&
          obstacle.coversPoint(east, north) &&
          altitude >= obstacle.height - roofSnapMargin) {
        continue;
      }
      if (!obstacle.collidesAt(east, north, droneRadiusMeters)) continue;

      final resolved = obstacle.resolve(east, north, droneRadiusMeters);
      east = resolved.x;
      north = resolved.y;

      final approaching =
          -(velocityEast * resolved.normalX + velocityNorth * resolved.normalY);
      if (approaching > impactSpeed) {
        impactSpeed = approaching;
        normalX = resolved.normalX;
        normalY = resolved.normalY;
      }
      collided = true;
    }

    var inTightGap = false;
    if (nearObstacleDirs.length >= 2) {
      for (var i = 0; i < nearObstacleDirs.length && !inTightGap; i++) {
        for (var j = i + 1; j < nearObstacleDirs.length; j++) {
          final dot = nearObstacleDirs[i].$1 * nearObstacleDirs[j].$1 +
              nearObstacleDirs[i].$2 * nearObstacleDirs[j].$2;
          if (dot < -0.25) {
            inTightGap = true;
            break;
          }
        }
      }
    }
    final underBridge = trackClearance &&
        WorldGenerator.scenarioFor(activeMap) == WorldScenario.canyon &&
        (north + 60.0).abs() <= 6.5 &&
        east >= -215.0 &&
        east <= 205.0 &&
        altitude >= 1.5 &&
        altitude <= 25.0;

    if (!collided) {
      return (
        minClearance: minClearance,
        inTightGap: inTightGap,
        underBridge: underBridge,
      );
    }

    // Ricochete afastando da normal (restituição 0.35).
    final correctedVelocity = Vec3(
      velocityEast - (1.0 + collisionRestitution) * impactSpeed * normalX,
      velocityNorth - (1.0 + collisionRestitution) * impactSpeed * normalY,
      velocity.z,
    );

    final angularMagnitude =
        (4.0 + 6.0 * (impactSpeed / 12.0)).clamp(4.0, 10.0);
    final angularImpulse = Vec3(
      (normalY * angularMagnitude).clamp(-10.0, 10.0),
      (-normalX * angularMagnitude).clamp(-10.0, 10.0),
      ((normalX - normalY) * angularMagnitude * 0.35).clamp(-10.0, 10.0),
    );

    sixDof.applyExternalCollisionCorrection(
      correctedPosition: Vec3(east, north, altitude),
      correctedVelocity: correctedVelocity,
      angularImpulseBody: angularImpulse,
    );

    _impactShake = max(_impactShake, (impactSpeed / 10.0).clamp(0.2, 1.0));
    _x = east;
    _y = north;
    _lastSnapshot = sixDof.snapshot;

    if (impactSpeed >= crashImpactSpeedMs) {
      _triggerCrash(impactSpeed, Vec3(normalX, normalY, 0), _lastSnapshot!);
    }
    return (
      minClearance: minClearance,
      inTightGap: inTightGap,
      underBridge: underBridge,
    );
  }

  /// Dispara o estado de crash: corta os motores e registra o impacto.
  void _triggerCrash(
    double impactSpeedMs,
    Vec3 normal,
    PhysicsSnapshot snapshot,
  ) {
    _status = SimulatorStatus.crashed;
    _isArmed = false;
    sixDof.setArmed(false);

    _crashImpactSpeedKmh = impactSpeedMs * 3.6;
    _lastCrashTimestamp = DateTime.now();
    _crashTimer = 0.0;
    _impactShake = 1.0;
    feedback.triggerCrash(_crashImpactSpeedKmh);

    // Ricochete + giro violento proporcional à batida.
    final magnitude = (4.0 + 6.0 * (impactSpeedMs / 12.0)).clamp(4.0, 10.0);
    sixDof.applyExternalCollisionCorrection(
      correctedPosition: snapshot.position,
      correctedVelocity: Vec3(
        snapshot.velocity.x * 0.65 + normal.x * magnitude * 0.4,
        snapshot.velocity.y * 0.65 + normal.y * magnitude * 0.4,
        max(0.0, snapshot.velocity.z * 0.3),
      ),
      angularImpulseBody: Vec3(
        normal.y * magnitude,
        -normal.x * magnitude,
        magnitude * 0.6,
      ),
    );

    _lastSnapshot = sixDof.snapshot;
  }
}
