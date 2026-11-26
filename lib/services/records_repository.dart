import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:drone_simulator/models/drone_profile.dart';
import 'package:drone_simulator/simulation/quadrotor_physics_6dof.dart';

/// Medalhas de desempenho para corridas cronometradas.
enum MedalTier { none, bronze, silver, gold }

MedalTier medalForRaceTime(double? seconds) {
  if (seconds == null) return MedalTier.none;
  if (seconds <= 42.0) return MedalTier.gold;
  if (seconds <= 58.0) return MedalTier.silver;
  if (seconds <= 80.0) return MedalTier.bronze;
  return MedalTier.none;
}

/// Quadro amostrado de trajetória para reprodução do drone fantasma (Ghost).
class GhostFrame {
  final double t;
  final double x;
  final double y;
  final double z;
  final double pitchRad;
  final double rollRad;
  final double yawRad;

  const GhostFrame({
    required this.t,
    required this.x,
    required this.y,
    required this.z,
    required this.pitchRad,
    required this.rollRad,
    required this.yawRad,
  });

  List<double> toCompactList() => [
        _round(t, 2),
        _round(x, 2),
        _round(y, 2),
        _round(z, 2),
        _round(pitchRad, 3),
        _round(rollRad, 3),
        _round(yawRad, 3),
      ];

  factory GhostFrame.fromCompactList(List<dynamic> raw) {
    double at(int i) => i < raw.length ? (raw[i] as num).toDouble() : 0.0;
    return GhostFrame(
      t: at(0),
      x: at(1),
      y: at(2),
      z: at(3),
      pitchRad: at(4),
      rollRad: at(5),
      yawRad: at(6),
    );
  }

  Map<String, dynamic> toJson() => {
        't': _round(t, 2),
        'x': _round(x, 2),
        'y': _round(y, 2),
        'z': _round(z, 2),
        'pitchRad': _round(pitchRad, 3),
        'rollRad': _round(rollRad, 3),
        'yawRad': _round(yawRad, 3),
      };

  static double _round(double v, int decimals) {
    final factor = math.pow(10, decimals);
    return (v * factor).roundToDouble() / factor;
  }
}

/// Trajetória gravada com interpolação linear no tempo.
class GhostTrajectory {
  final List<GhostFrame> frames;

  const GhostTrajectory(this.frames);

  bool get isEmpty => frames.isEmpty;
  double get duration => frames.isEmpty ? 0.0 : frames.last.t;

  /// Amostra o estado interpolado para [elapsedSec].
  GhostFrame? sampleAt(double elapsedSec) {
    if (frames.isEmpty) return null;
    if (elapsedSec <= frames.first.t) return frames.first;
    if (elapsedSec >= frames.last.t) return frames.last;

    // Busca binária do intervalo que contém elapsedSec.
    var low = 0;
    var high = frames.length - 1;
    while (low + 1 < high) {
      final mid = (low + high) >> 1;
      if (frames[mid].t <= elapsedSec) {
        low = mid;
      } else {
        high = mid;
      }
    }

    final a = frames[low];
    final b = frames[high];
    final span = b.t - a.t;
    if (span <= 1e-6) return a;
    final alpha = ((elapsedSec - a.t) / span).clamp(0.0, 1.0);

    return GhostFrame(
      t: elapsedSec,
      x: a.x + (b.x - a.x) * alpha,
      y: a.y + (b.y - a.y) * alpha,
      z: a.z + (b.z - a.z) * alpha,
      pitchRad: _lerpAngle(a.pitchRad, b.pitchRad, alpha),
      rollRad: _lerpAngle(a.rollRad, b.rollRad, alpha),
      yawRad: _lerpAngle(a.yawRad, b.yawRad, alpha),
    );
  }

  static double _lerpAngle(double a, double b, double t) {
    var diff = (b - a) % (math.pi * 2.0);
    if (diff > math.pi) diff -= math.pi * 2.0;
    if (diff < -math.pi) diff += math.pi * 2.0;
    return a + diff * t;
  }
}

/// Recordes persistidos de um mapa específico.
class MapRecord {
  final String mapId;
  final double? bestRaceTimeSec;
  final double bestRaceScore;
  final int bestCombo;
  final int bestTimeAttackGates;
  final double bestTimeAttackScore;
  final double bestFreestyleScore;
  final Map<String, double> bestTimesByProfile;
  final List<GhostFrame> ghostFrames;
  final Map<String, List<GhostFrame>> ghostFramesByProfile;
  final Set<String> completedMissions;
  final bool freestyleChallengeCompleted;

  const MapRecord({
    required this.mapId,
    this.bestRaceTimeSec,
    this.bestRaceScore = 0.0,
    this.bestCombo = 1,
    this.bestTimeAttackGates = 0,
    this.bestTimeAttackScore = 0.0,
    this.bestFreestyleScore = 0.0,
    this.bestTimesByProfile = const {},
    this.ghostFrames = const [],
    this.ghostFramesByProfile = const {},
    this.completedMissions = const {},
    this.freestyleChallengeCompleted = false,
  });

  MedalTier get medal => medalForRaceTime(bestRaceTimeSec);
  GhostTrajectory get ghostTrajectory => GhostTrajectory(ghostFrames);

  double? bestTimeForProfile(String profileId) =>
      bestTimesByProfile[profileId];

  MedalTier medalForProfile(String profileId) =>
      medalForRaceTime(bestTimesByProfile[profileId]);

  GhostTrajectory ghostTrajectoryForProfile(String profileId) {
    final profileFrames = ghostFramesByProfile[profileId];
    if (profileFrames != null && profileFrames.isNotEmpty) {
      return GhostTrajectory(profileFrames);
    }
    if (ghostFramesByProfile.isEmpty &&
        ghostFrames.isNotEmpty &&
        (bestTimesByProfile.isEmpty ||
            bestTimesByProfile.containsKey(profileId))) {
      return GhostTrajectory(ghostFrames);
    }
    return const GhostTrajectory([]);
  }

  MapRecord copyWith({
    double? bestRaceTimeSec,
    double? bestRaceScore,
    int? bestCombo,
    int? bestTimeAttackGates,
    double? bestTimeAttackScore,
    double? bestFreestyleScore,
    Map<String, double>? bestTimesByProfile,
    List<GhostFrame>? ghostFrames,
    Map<String, List<GhostFrame>>? ghostFramesByProfile,
    Set<String>? completedMissions,
    bool? freestyleChallengeCompleted,
  }) {
    return MapRecord(
      mapId: mapId,
      bestRaceTimeSec: bestRaceTimeSec ?? this.bestRaceTimeSec,
      bestRaceScore: bestRaceScore ?? this.bestRaceScore,
      bestCombo: bestCombo ?? this.bestCombo,
      bestTimeAttackGates: bestTimeAttackGates ?? this.bestTimeAttackGates,
      bestTimeAttackScore: bestTimeAttackScore ?? this.bestTimeAttackScore,
      bestFreestyleScore: bestFreestyleScore ?? this.bestFreestyleScore,
      bestTimesByProfile: bestTimesByProfile ?? this.bestTimesByProfile,
      ghostFrames: ghostFrames ?? this.ghostFrames,
      ghostFramesByProfile: ghostFramesByProfile ?? this.ghostFramesByProfile,
      completedMissions: completedMissions ?? this.completedMissions,
      freestyleChallengeCompleted:
          freestyleChallengeCompleted ?? this.freestyleChallengeCompleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'mapId': mapId,
        'bestRaceTimeSec': bestRaceTimeSec,
        'bestRaceScore': bestRaceScore,
        'bestCombo': bestCombo,
        'bestTimeAttackGates': bestTimeAttackGates,
        'bestTimeAttackScore': bestTimeAttackScore,
        'bestFreestyleScore': bestFreestyleScore,
        'bestTimesByProfile': bestTimesByProfile,
        'ghostFrames': ghostFrames.map((f) => f.toCompactList()).toList(),
        'ghostFramesByProfile': {
          for (final entry in ghostFramesByProfile.entries)
            entry.key: entry.value.map((f) => f.toCompactList()).toList(),
        },
        'completedMissions': completedMissions.toList(),
        'freestyleChallengeCompleted': freestyleChallengeCompleted,
      };

  factory MapRecord.fromJson(Map<String, dynamic> json) {
    final mapId = (json['mapId'] as String?) ?? '';
    final rawByProfile =
        (json['bestTimesByProfile'] as Map<String, dynamic>?) ?? const {};
    final byProfile = <String, double>{};
    for (final entry in rawByProfile.entries) {
      final val = entry.value;
      if (val is num) byProfile[entry.key] = val.toDouble();
    }

    final rawGhost = (json['ghostFrames'] as List<dynamic>?) ?? const [];
    final frames = <GhostFrame>[];
    for (final item in rawGhost) {
      if (item is List<dynamic>) {
        frames.add(GhostFrame.fromCompactList(item));
      }
    }

    final rawGhostByProfile =
        (json['ghostFramesByProfile'] as Map<String, dynamic>?) ?? const {};
    final ghostByProfile = <String, List<GhostFrame>>{};
    for (final entry in rawGhostByProfile.entries) {
      final rawList = entry.value;
      if (rawList is List<dynamic>) {
        final parsed = <GhostFrame>[];
        for (final item in rawList) {
          if (item is List<dynamic>) {
            parsed.add(GhostFrame.fromCompactList(item));
          }
        }
        if (parsed.isNotEmpty) {
          ghostByProfile[entry.key] = List<GhostFrame>.unmodifiable(parsed);
        }
      }
    }

    final rawMissions =
        (json['completedMissions'] as List<dynamic>?) ?? const [];
    final completedMissions = <String>{
      for (final m in rawMissions)
        if (m is String && m.isNotEmpty) m,
    };

    return MapRecord(
      mapId: mapId,
      bestRaceTimeSec: (json['bestRaceTimeSec'] as num?)?.toDouble(),
      bestRaceScore: (json['bestRaceScore'] as num?)?.toDouble() ?? 0.0,
      bestCombo: (json['bestCombo'] as num?)?.toInt() ?? 1,
      bestTimeAttackGates:
          (json['bestTimeAttackGates'] as num?)?.toInt() ?? 0,
      bestTimeAttackScore:
          (json['bestTimeAttackScore'] as num?)?.toDouble() ?? 0.0,
      bestFreestyleScore:
          (json['bestFreestyleScore'] as num?)?.toDouble() ?? 0.0,
      bestTimesByProfile: byProfile,
      ghostFrames: frames,
      ghostFramesByProfile: ghostByProfile,
      completedMissions: Set<String>.unmodifiable(completedMissions),
      freestyleChallengeCompleted:
          (json['freestyleChallengeCompleted'] as bool?) ?? false,
    );
  }
}

/// Abstração simples de armazenamento chave-valor para persistência local.
abstract class KeyValueStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

/// Armazenamento em memória (usado em testes e fallback quando canal nativo indisponível).
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async {
    _data[key] = value;
  }
}

/// Implementação nativa Android via MethodChannel (SharedPreferences) com fallback seguro.
class MethodChannelKeyValueStore implements KeyValueStore {
  static const MethodChannel _channel =
      MethodChannel('com.dronesim.drone_simulator/storage');
  static final InMemoryKeyValueStore _fallback = InMemoryKeyValueStore();

  @override
  Future<String?> getString(String key) async {
    try {
      final val = await _channel.invokeMethod<String>('load', {'key': key});
      return val ?? await _fallback.getString(key);
    } catch (_) {
      return _fallback.getString(key);
    }
  }

  @override
  Future<void> setString(String key, String value) async {
    await _fallback.setString(key, value);
    try {
      await _channel.invokeMethod<bool>('save', {'key': key, 'value': value});
    } catch (_) {
      // Em testes unitários / headless sem Android host, mantém fallback em memória.
    }
  }
}

/// Repositório singleton/injetável de recordes, medalhas e trajetórias Ghost.
class RecordsRepository {
  static const String storageKey = 'drone_simulator_records_v1';
  static const String acroSettingsStorageKey =
      'drone_simulator_acro_settings_v1';
  static const String droneTuningStorageKey = 'drone_simulator_tuning_v1';

  final KeyValueStore _store;
  final Map<String, MapRecord> _records = {};
  AcroSettings _acroSettings = const AcroSettings();
  bool _hasSavedAcroSettings = false;
  DroneTuning _droneTuning = const DroneTuning();
  bool _hasSavedDroneTuning = false;
  bool _loaded = false;

  RecordsRepository({KeyValueStore? store})
      : _store = store ?? MethodChannelKeyValueStore();

  bool get isLoaded => _loaded;
  Map<String, MapRecord> get allRecords => Map.unmodifiable(_records);
  AcroSettings get acroSettings => _acroSettings;
  bool get hasSavedAcroSettings => _hasSavedAcroSettings;
  DroneTuning get droneTuning => _droneTuning;
  bool get hasSavedDroneTuning => _hasSavedDroneTuning;

  MapRecord recordFor(String mapId) =>
      _records[mapId] ?? MapRecord(mapId: mapId);

  Future<void> loadAll() async {
    final raw = await _store.getString(storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _records.clear();
        for (final entry in decoded.entries) {
          final val = entry.value;
          if (val is Map<String, dynamic>) {
            _records[entry.key] = MapRecord.fromJson(val);
          }
        }
      } catch (_) {
        // JSON corrompido não impede o app de iniciar.
      }
    }
    final rawAcro = await _store.getString(acroSettingsStorageKey);
    if (rawAcro != null && rawAcro.isNotEmpty) {
      try {
        final decodedAcro = jsonDecode(rawAcro);
        if (decodedAcro is Map<String, dynamic>) {
          _acroSettings = AcroSettings.fromJson(decodedAcro);
          _hasSavedAcroSettings = true;
        }
      } catch (_) {
        // JSON corrompido não impede o app de iniciar.
      }
    }
    final rawTuning = await _store.getString(droneTuningStorageKey);
    if (rawTuning != null && rawTuning.isNotEmpty) {
      try {
        final decodedTuning = jsonDecode(rawTuning);
        if (decodedTuning is Map<String, dynamic>) {
          _droneTuning = DroneTuning.fromJson(decodedTuning);
          _hasSavedDroneTuning = true;
        }
      } catch (_) {
        // JSON corrompido não impede o app de iniciar.
      }
    }
    _loaded = true;
  }

  Future<void> saveAcroSettings(AcroSettings settings) async {
    _acroSettings = settings;
    _hasSavedAcroSettings = true;
    await _store.setString(
      acroSettingsStorageKey,
      jsonEncode(settings.toJson()),
    );
  }

  Future<void> saveDroneTuning(DroneTuning tuning) async {
    _droneTuning = tuning;
    _hasSavedDroneTuning = true;
    await _store.setString(
      droneTuningStorageKey,
      jsonEncode(tuning.toJson()),
    );
  }

  Future<void> _persist() async {
    final payload = <String, dynamic>{
      for (final entry in _records.entries) entry.key: entry.value.toJson(),
    };
    await _store.setString(storageKey, jsonEncode(payload));
  }

  /// Salva resultado da corrida de 10 portais e atualiza o Ghost do perfil ao bater o recorde.
  Future<({bool isNewRecord, MapRecord record})> saveRaceResult({
    required String mapId,
    required String profileId,
    required double elapsedSeconds,
    required double score,
    required int bestCombo,
    List<GhostFrame>? ghostFrames,
  }) async {
    final current = recordFor(mapId);
    final isNewGlobalTime = current.bestRaceTimeSec == null ||
        elapsedSeconds < current.bestRaceTimeSec!;

    final updatedByProfile = Map<String, double>.from(current.bestTimesByProfile);
    final prevProfileBest = updatedByProfile[profileId];
    final isNewProfileTime =
        prevProfileBest == null || elapsedSeconds < prevProfileBest;
    if (isNewProfileTime) {
      updatedByProfile[profileId] = elapsedSeconds;
    }

    final updatedGhostByProfile = <String, List<GhostFrame>>{
      for (final entry in current.ghostFramesByProfile.entries)
        entry.key: List<GhostFrame>.unmodifiable(entry.value),
    };
    if (isNewProfileTime && ghostFrames != null && ghostFrames.isNotEmpty) {
      updatedGhostByProfile[profileId] =
          List<GhostFrame>.unmodifiable(ghostFrames);
    }

    final updated = current.copyWith(
      bestRaceTimeSec:
          isNewGlobalTime ? elapsedSeconds : current.bestRaceTimeSec,
      bestRaceScore: math.max(current.bestRaceScore, score),
      bestCombo: math.max(current.bestCombo, bestCombo),
      bestTimesByProfile: updatedByProfile,
      ghostFrames:
          (isNewGlobalTime && ghostFrames != null && ghostFrames.isNotEmpty)
              ? List<GhostFrame>.unmodifiable(ghostFrames)
              : current.ghostFrames,
      ghostFramesByProfile: updatedGhostByProfile,
    );

    _records[mapId] = updated;
    await _persist();
    return (isNewRecord: isNewProfileTime, record: updated);
  }

  Future<({bool isNewRecord, MapRecord record})> saveTimeAttackResult({
    required String mapId,
    required int gatesCleared,
    required double score,
    required int bestCombo,
  }) async {
    final current = recordFor(mapId);
    final isNewBest = gatesCleared > current.bestTimeAttackGates ||
        (gatesCleared == current.bestTimeAttackGates &&
            score > current.bestTimeAttackScore);

    final updated = current.copyWith(
      bestTimeAttackGates: math.max(current.bestTimeAttackGates, gatesCleared),
      bestTimeAttackScore: math.max(current.bestTimeAttackScore, score),
      bestCombo: math.max(current.bestCombo, bestCombo),
    );
    _records[mapId] = updated;
    await _persist();
    return (isNewRecord: isNewBest, record: updated);
  }

  Future<({bool isNewRecord, MapRecord record})> saveFreestyleResult({
    required String mapId,
    required double score,
    required int bestCombo,
    bool challengeCompleted = false,
  }) async {
    final current = recordFor(mapId);
    final isNewBest = score > current.bestFreestyleScore;

    final updated = current.copyWith(
      bestFreestyleScore: math.max(current.bestFreestyleScore, score),
      bestCombo: math.max(current.bestCombo, bestCombo),
      freestyleChallengeCompleted:
          current.freestyleChallengeCompleted || challengeCompleted,
    );
    _records[mapId] = updated;
    await _persist();
    return (isNewRecord: isNewBest, record: updated);
  }

  Future<MapRecord> saveMissionCompleted({
    required String mapId,
    required String missionId,
  }) async {
    final current = recordFor(mapId);
    final updatedMissions = Set<String>.from(current.completedMissions)
      ..add(missionId);
    final updated = current.copyWith(
      completedMissions: Set<String>.unmodifiable(updatedMissions),
    );
    _records[mapId] = updated;
    await _persist();
    return updated;
  }
}
