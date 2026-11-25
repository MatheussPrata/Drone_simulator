import 'package:flutter/services.dart';

/// Tipos de eventos sonoros despachados ao sintetizador Web Audio da cena 3D.
enum SimSoundKind { gate, trick, warning, crash, finish }

/// Evento sonoro com identificador único para evitar disparo duplicado.
class SimSoundEvent {
  final int id;
  final SimSoundKind kind;
  final double value;

  const SimSoundEvent({
    required this.id,
    required this.kind,
    this.value = 1.0,
  });
}

/// Serviço central de feedback tátil (vibração) e fila de áudio de jogo.
class FeedbackService {
  bool hapticsEnabled = true;
  bool audioEnabled = true;

  int _nextId = 1;
  final List<SimSoundEvent> _queue = [];
  DateTime? _lastWarningTime;

  void triggerGatePassed(int combo) {
    _safeHaptic(() => HapticFeedback.lightImpact());
    _enqueue(SimSoundKind.gate, combo.toDouble());
  }

  void triggerTrick(double points) {
    _safeHaptic(() => HapticFeedback.mediumImpact());
    _enqueue(SimSoundKind.trick, points);
  }

  void triggerWarning() {
    final now = DateTime.now();
    if (_lastWarningTime != null &&
        now.difference(_lastWarningTime!).inMilliseconds < 2400) {
      return;
    }
    _lastWarningTime = now;
    _safeHaptic(() => HapticFeedback.selectionClick());
    _enqueue(SimSoundKind.warning, 1.0);
  }

  void triggerCrash(double impactSpeedKmh) {
    _safeHaptic(() => HapticFeedback.heavyImpact());
    _enqueue(SimSoundKind.crash, impactSpeedKmh);
  }

  void triggerFinish() {
    _safeHaptic(() => HapticFeedback.mediumImpact());
    _enqueue(SimSoundKind.finish, 1.0);
  }

  void _enqueue(SimSoundKind kind, double value) {
    if (!audioEnabled) return;
    _queue.add(SimSoundEvent(id: _nextId++, kind: kind, value: value));
    if (_queue.length > 16) {
      _queue.removeAt(0);
    }
  }

  List<SimSoundEvent> drainPendingSounds() {
    if (_queue.isEmpty) return const [];
    if (!audioEnabled) {
      _queue.clear();
      return const [];
    }
    final items = List<SimSoundEvent>.from(_queue);
    _queue.clear();
    return items;
  }

  void _safeHaptic(Future<void> Function() action) {
    if (!hapticsEnabled) return;
    try {
      action().catchError((_) {});
    } catch (_) {
      // Sem ServicesBinding inicializado (testes unitários puros).
    }
  }
}
