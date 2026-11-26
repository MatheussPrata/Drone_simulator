import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:drone_simulator/services/records_repository.dart';
import 'package:drone_simulator/simulation/freestyle_manager.dart';
import 'package:drone_simulator/simulation/race_manager.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';

/// HUD do Modo Jogo (Corrida, Time Attack, Freestyle) + cards de queda, vitória e replay.
class GameHudOverlay extends StatelessWidget {
  final SimulatorController controller;
  final VoidCallback? onOpenHomeMenu;

  const GameHudOverlay({
    super.key,
    required this.controller,
    this.onOpenHomeMenu,
  });

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
        final isFreestyle = controller.isFreestyle;
        final raceStatus = controller.raceStatus;
        final freestyle = controller.freestyleManager;
        final replaying = controller.isReplaying;
        final crashed = !replaying && controller.isCrashed;
        final finished = !replaying &&
            ((isRace && raceStatus == RaceStatus.finished) ||
                (isFreestyle && (freestyle?.isFinished ?? false)));

        return Stack(
          children: [
            if (replaying)
              Positioned(
                top: 74,
                left: 12,
                right: 12,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: _buildReplayBar(context),
                  ),
                ),
              ),
            if ((isRace || isFreestyle) && !replaying && !crashed && !finished)
              Positioned(
                top: 74,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isRace) _buildRacePanel(),
                      if (isFreestyle && freestyle != null)
                        _buildFreestylePanel(freestyle),
                    ],
                  ),
                ),
              ),
            if (crashed)
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _buildCrashCard(context),
                ),
              ),
            if (finished)
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _buildFinishCard(context),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildReplayBar(BuildContext context) {
    final duration = math.max(0.1, controller.replayDurationSeconds);
    final current = controller.replayTimeSeconds.clamp(0.0, duration);
    final isThirdPerson = controller.cameraMode == CameraViewMode.thirdPerson;

    return Container(
      key: const Key('replay_controls_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.84),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.55),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: const Text(
                  'REPLAY',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${formatTime(controller.replayTimeSeconds)} / '
                '${formatTime(controller.replayDurationSeconds)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    key: const Key('replay_progress_slider'),
                    value: current,
                    min: 0.0,
                    max: duration,
                    activeColor: Colors.cyanAccent,
                    inactiveColor: Colors.white24,
                    onChanged: controller.replayDurationSeconds > 0.0
                        ? controller.seekReplay
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _replayActionButton(
                  key: const Key('btn_replay_play_pause'),
                  icon: controller.isReplayPaused
                      ? Icons.play_arrow
                      : Icons.pause,
                  label: controller.isReplayPaused ? 'Play' : 'Pausar',
                  color: Colors.cyanAccent,
                  onTap: controller.toggleReplayPause,
                ),
                const SizedBox(width: 6),
                _replayActionButton(
                  key: const Key('btn_replay_restart'),
                  icon: Icons.replay,
                  label: 'Início',
                  color: Colors.white70,
                  onTap: controller.restartReplay,
                ),
                const SizedBox(width: 6),
                _replayActionButton(
                  key: const Key('btn_replay_speed'),
                  icon: Icons.speed,
                  label: '${controller.replaySpeed}x',
                  color: Colors.amberAccent,
                  onTap: controller.cycleReplaySpeed,
                ),
                const SizedBox(width: 6),
                _replayActionButton(
                  key: const Key('btn_replay_camera'),
                  icon: isThirdPerson
                      ? Icons.accessibility_new
                      : Icons.videocam,
                  label: isThirdPerson ? '3ªP' : 'FPV',
                  color: Colors.lightGreenAccent,
                  onTap: controller.toggleCameraMode,
                ),
                const SizedBox(width: 6),
                _replayActionButton(
                  key: const Key('btn_replay_exit'),
                  icon: Icons.close,
                  label: 'Sair',
                  color: Colors.redAccent,
                  onTap: controller.stopReplay,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _replayActionButton({
    required Key key,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      key: key,
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: color),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.55)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      label: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRacePanel() {
    final isTimeAttack = controller.isTimeAttack;
    final gateNumber = (controller.raceGateIndex + 1).clamp(1, 99);
    final total = controller.raceTotalGates;
    final combo = controller.raceCombo;
    final rem = controller.raceRemainingSeconds;
    final lowTime = isTimeAttack && rem <= 6.0;

    return Container(
      key: const Key('race_panel'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: lowTime
              ? Colors.redAccent.withOpacity(0.85)
              : Colors.cyanAccent.withOpacity(0.55),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isTimeAttack
                ? 'TIME ATTACK · ${controller.activeMap.name.toUpperCase()}'
                : '${controller.raceCourse?.name ?? 'CORRIDA'} · '
                    '${controller.activeMap.name.toUpperCase()}',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 9,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isTimeAttack) ...[
                _metric(
                  'RESTANTE',
                  formatTime(rem),
                  lowTime ? Colors.redAccent : Colors.orangeAccent,
                ),
                _divider(),
                _metric(
                  'PORTAIS',
                  '${controller.raceGatesCleared}',
                  Colors.cyanAccent,
                ),
              ] else ...[
                _metric('PORTAL', '$gateNumber/$total', Colors.cyanAccent),
                _divider(),
                _metric('TEMPO', formatTime(controller.raceElapsedSeconds),
                    Colors.white),
              ],
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
        ],
      ),
    );
  }

  Widget _buildFreestylePanel(FreestyleManager fs) {
    final showTrickBanner =
        fs.lastTrickLabel != null && fs.lastTrickAgeSec < 2.2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const Key('freestyle_panel'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.72),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.purpleAccent.withOpacity(0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _metric(
                  'TEMPO', formatTime(fs.remainingSeconds), Colors.white),
              _divider(),
              _metric('MANOBRAS', '${fs.tricksCount}', Colors.purpleAccent),
              _divider(),
              _metric(
                  'PONTOS', '${fs.score.round()} pts', Colors.amberAccent),
              if (fs.combo > 1) ...[
                _divider(),
                _metric('COMBO', 'x${fs.combo}', Colors.deepOrangeAccent),
              ],
            ],
          ),
        ),
        if (showTrickBanner) ...[
          const SizedBox(height: 6),
          Container(
            key: const Key('freestyle_trick_banner'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.purple.shade900.withOpacity(0.88),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.amberAccent),
            ),
            child: Text(
              '${fs.lastTrickLabel}  +${fs.lastTrickPoints.round()} pts',
              style: const TextStyle(
                color: Colors.amberAccent,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ],
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
            height: 46,
            child: ElevatedButton.icon(
              key: const Key('btn_restart_flight'),
              onPressed: () {
                if (controller.isRaceMode || controller.isFreestyle) {
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
          if (onOpenHomeMenu != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onOpenHomeMenu,
              child: const Text('VOLTAR AO MENU INICIAL',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFinishCard(BuildContext context) {
    final isTimeAttack = controller.isTimeAttack;
    final isFreestyle = controller.isFreestyle;
    final fs = controller.freestyleManager;
    final best = controller.raceBestTime;
    final medal = isTimeAttack || isFreestyle
        ? MedalTier.none
        : medalForRaceTime(controller.raceElapsedSeconds);

    final title = isTimeAttack
        ? 'TIME ATTACK ENCERRADO!'
        : (isFreestyle ? 'FREESTYLE CONCLUÍDO!' : 'CIRCUITO CONCLUÍDO!');

    return Container(
      key: const Key('race_finish_card'),
      width: 370,
      padding: const EdgeInsets.all(20),
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
          const Icon(Icons.emoji_events, color: Colors.amberAccent, size: 42),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          if (controller.lastRunWasNewRecord) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amberAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.amberAccent),
              ),
              child: const Text(
                'NOVO RECORDE!',
                style: TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (isTimeAttack) ...[
            Text(
              'Portais cruzados: ${controller.raceGatesCleared}',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Pontuação: ${controller.raceScore.round()} pts',
              style: const TextStyle(color: Colors.amberAccent, fontSize: 15),
            ),
          ] else if (isFreestyle && fs != null) ...[
            Text(
              'Manobras realizadas: ${fs.tricksCount}',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Pontuação: ${fs.score.round()} pts · Melhor Combo x${fs.bestCombo}',
              style: const TextStyle(color: Colors.amberAccent, fontSize: 14),
            ),
          ] else ...[
            Text(
              'Tempo: ${formatTime(controller.raceElapsedSeconds)}',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Pontuação: ${controller.raceScore.round()} pts',
              style: const TextStyle(color: Colors.amberAccent, fontSize: 15),
            ),
            if (medal != MedalTier.none) ...[
              const SizedBox(height: 4),
              Text(
                'Medalha: ${_medalLabel(medal)}',
                style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
            ],
            if (best != null) ...[
              const SizedBox(height: 4),
              Text(
                'Recorde: ${formatTime(best)}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ],
          const SizedBox(height: 16),
          if (controller.hasReplayAvailable) ...[
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                key: const Key('btn_watch_replay'),
                onPressed: controller.startReplay,
                icon: const Icon(Icons.play_circle_outline, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: const BorderSide(color: Colors.cyanAccent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                label: const Text(
                  'ASSISTIR REPLAY',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            height: 44,
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
          if (onOpenHomeMenu != null) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const Key('btn_finish_home'),
              onPressed: onOpenHomeMenu,
              child: const Text('VOLTAR AO MENU INICIAL',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  static String _medalLabel(MedalTier medal) {
    switch (medal) {
      case MedalTier.gold:
        return 'OURO';
      case MedalTier.silver:
        return 'PRATA';
      case MedalTier.bronze:
        return 'BRONZE';
      case MedalTier.none:
        return '';
    }
  }
}
