import 'package:flutter/material.dart';

import 'package:drone_simulator/simulation/race_manager.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';

/// HUD do Modo Jogo (corrida de portais) + cards de queda e vitória.
class GameHudOverlay extends StatelessWidget {
  final SimulatorController controller;

  const GameHudOverlay({super.key, required this.controller});

  static String formatTime(double seconds) {
    final total = seconds.clamp(0.0, 5999.9);
    final minutes = total ~/ 60;
    final rest = total - minutes * 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${rest.toStringAsFixed(1).padLeft(4, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isRace = controller.isRaceMode;
        final raceStatus = controller.raceStatus;
        final crashed = controller.isCrashed;
        final finished = raceStatus == RaceStatus.finished;

        return Stack(
          children: [
            if (isRace && !crashed && !finished)
              Positioned(
                top: 74,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(child: _buildRacePanel()),
                ),
              ),
            if (crashed)
              Center(child: _buildCrashCard(context)),
            if (finished) Center(child: _buildFinishCard(context)),
          ],
        );
      },
    );
  }

  Widget _buildRacePanel() {
    final gateNumber = (controller.raceGateIndex + 1).clamp(1, 99);
    final total = controller.raceTotalGates;
    final combo = controller.raceCombo;

    return Container(
      key: const Key('race_panel'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _metric('PORTAL', '$gateNumber/$total', Colors.cyanAccent),
          _divider(),
          _metric('TEMPO', formatTime(controller.raceElapsedSeconds),
              Colors.white),
          _divider(),
          _metric('PONTOS', '${controller.raceScore.round()} pts',
              Colors.amberAccent),
          _divider(),
          _metric('PRÓXIMO',
              '${controller.raceDistanceToGate.toStringAsFixed(0)} m',
              Colors.greenAccent),
          if (combo > 1) ...[
            _divider(),
            _metric('COMBO', 'x$combo', Colors.deepOrangeAccent),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 9,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 26,
        color: Colors.white12,
      );

  Widget _buildCrashCard(BuildContext context) {
    return Container(
      key: const Key('crash_card'),
      width: 340,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A0E0E).withOpacity(0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 24, spreadRadius: 4),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.redAccent, size: 42),
          const SizedBox(height: 8),
          const Text(
            'QUEDA DETECTADA',
            style: TextStyle(
              color: Colors.redAccent,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Impacto a ${controller.crashImpactSpeedKmh.toStringAsFixed(1)} km/h',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              key: const Key('btn_restart_flight'),
              onPressed: () {
                if (controller.isRaceMode) {
                  controller.restartRace();
                } else {
                  controller.respawn();
                }
              },
              icon: const Icon(Icons.refresh),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              label: const Text(
                'REINICIAR VOO',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinishCard(BuildContext context) {
    final best = controller.raceBestTime;
    return Container(
      key: const Key('race_finish_card'),
      width: 360,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2418).withOpacity(0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.greenAccent, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 24, spreadRadius: 4),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events, color: Colors.amberAccent, size: 46),
          const SizedBox(height: 8),
          const Text(
            'CIRCUITO CONCLUÍDO!',
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 19,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Tempo: ${formatTime(controller.raceElapsedSeconds)}',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'Pontuação: ${controller.raceScore.round()} pts',
            style: const TextStyle(color: Colors.amberAccent, fontSize: 15),
          ),
          if (best != null) ...[
            const SizedBox(height: 4),
            Text(
              'Recorde: ${formatTime(best)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              key: const Key('btn_race_replay'),
              onPressed: controller.restartRace,
              icon: const Icon(Icons.replay),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              label: const Text(
                'JOGAR NOVAMENTE',
                style:
                    TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
