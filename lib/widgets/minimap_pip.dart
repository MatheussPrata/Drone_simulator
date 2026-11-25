import 'dart:math';

import 'package:flutter/material.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/simulation/world_generator.dart';
import 'package:drone_simulator/widgets/fpv_camera_view.dart';
import 'package:drone_simulator/widgets/map_settings_modal.dart';
import 'package:drone_simulator/widgets/mini_map_widget.dart';

/// Card Picture-in-Picture (PiP) arredondado posicionado no canto da tela.
///
/// Alterna dinamicamente entre Radar Tático (quando FPV é a visão principal)
/// e câmera FPV (quando o mapa real está em tela cheia).
class MiniMapPip extends StatelessWidget {
  final SimulatorController controller;
  final VoidCallback? onToggle;
  final double width;
  final double height;

  const MiniMapPip({
    super.key,
    required this.controller,
    this.onToggle,
    this.width = 176,
    this.height = 114,
  });

  bool get _isFpvMain => !controller.isMapPrimaryView;

  ({String text, bool alert}) _radarStatus() {
    if (controller.isRaceMode) {
      final gate = (controller.raceGateIndex + 1).clamp(1, 99);
      final total = controller.raceTotalGates;
      final dist = controller.raceDistanceToGate.toStringAsFixed(0);
      return (text: 'PORTAL $gate/$total · ${dist}m', alert: false);
    }

    // Verifica obstáculo próximo na mesma altitude do drone
    double minGap = 999.0;
    final obstacles = WorldGenerator.generateFor(controller.activeMap);
    for (final o in obstacles) {
      if (controller.z >= o.height + 1.5) continue;
      final dx = o.x - controller.x;
      final dy = o.y - controller.y;
      final distCenter = sqrt(dx * dx + dy * dy);
      final footprint = o.isCylindrical ? o.radius : max(o.width, o.depth) * 0.5;
      final gap = distCenter - footprint;
      if (gap < minGap) minGap = gap;
    }

    if (controller.isArmed && minGap < 14.0) {
      return (
        text: 'OBSTÁCULO ${max(0.0, minGap).toStringAsFixed(0)}m',
        alert: true,
      );
    }

    final homeDist =
        sqrt(controller.x * controller.x + controller.y * controller.y);
    return (
      text: 'ALT ${controller.z.toStringAsFixed(0)}m · H ${homeDist.toStringAsFixed(0)}m',
      alert: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final status = _isFpvMain ? _radarStatus() : null;
        return GestureDetector(
          key: const Key('pip_card_gesture'),
          onTap: onToggle ?? () => controller.togglePrimaryView(),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (status?.alert ?? false)
                    ? Colors.redAccent
                    : Colors.cyanAccent.withOpacity(0.85),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.65),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10.5),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _isFpvMain
                        ? MiniMapWidget(
                            controller: controller,
                            followDrone: true,
                            showControls: false,
                          )
                        : FpvCameraView(
                            controller: controller,
                            showOsd: false,
                            showGroundMap: true,
                          ),
                  ),

                  // Botão discreto de camadas no canto do minimapa
                  Positioned(
                    top: 5,
                    left: 5,
                    child: GestureDetector(
                      key: const Key('pip_layers_button'),
                      onTap: () => MapSettingsModal.show(context, controller),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.cyanAccent.withOpacity(0.7),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.layers,
                          size: 13,
                          color: Colors.cyanAccent,
                        ),
                      ),
                    ),
                  ),

                  // Botão de expandir / alternar (Swap) com indicação visual [ ] MAPA / FPV
                  Positioned(
                    top: 5,
                    right: 5,
                    child: GestureDetector(
                      key: const Key('pip_swap_button'),
                      onTap: onToggle ?? () => controller.togglePrimaryView(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.cyanAccent.withOpacity(0.7),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isFpvMain ? Icons.crop_free : Icons.swap_horiz,
                              size: 13,
                              color: Colors.cyanAccent,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _isFpvMain ? 'MAPA' : 'FPV',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Barra inferior tática do Radar (portal ou alerta de obstáculo)
                  if (status != null)
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 4,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: status.alert
                                ? Colors.red.shade900.withOpacity(0.88)
                                : Colors.black.withOpacity(0.78),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: status.alert
                                  ? Colors.redAccent
                                  : Colors.cyanAccent.withOpacity(0.35),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            status.text,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: status.alert
                                  ? Colors.white
                                  : Colors.cyanAccent,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
