import 'package:flutter/material.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/chase_drone_overlay.dart';
import 'package:drone_simulator/widgets/fpv_camera_view.dart';
import 'package:drone_simulator/widgets/map_settings_modal.dart';
import 'package:drone_simulator/widgets/mini_map_widget.dart';

/// Card Picture-in-Picture (PiP) arredondado posicionado no canto da tela.
///
/// Alterna dinamicamente entre Mini-Mapa (quando FPV é a visão principal)
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
    this.width = 156,
    this.height = 104,
  });

  bool get _isFpvMain => !controller.isMapPrimaryView;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return GestureDetector(
          key: const Key('pip_card_gesture'),
          onTap: onToggle ?? () => controller.togglePrimaryView(),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.85),
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
                  // Conteúdo interno do PiP:
                  // Mini-Mapa quando FPV é tela cheia; FPV quando Mapa é tela cheia.
                  Positioned.fill(
                    child: _isFpvMain
                        ? MiniMapWidget(
                            controller: controller,
                            followDrone: true,
                            showControls: false,
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              FpvCameraView(
                                controller: controller,
                                showOsd: false,
                                showGroundMap: true,
                              ),
                              if (controller.cameraMode == CameraViewMode.thirdPerson)
                                ChaseDroneOverlay(
                                  controller: controller,
                                ),
                            ],
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
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
