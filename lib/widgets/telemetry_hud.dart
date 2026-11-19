import 'dart:math';
import 'package:flutter/material.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/map_settings_modal.dart';

/// Posição dos botões de ação do HUD
enum HudActionsPlacement {
  top,
  side,
  none,
}

/// Widget de barra superior de telemetria e controle de voo.
///
/// Exibe:
/// - Altitude (z)
/// - Velocidade
/// - Distância do Home (0,0)
/// - Bateria (%)
/// - Banners de alerta vermelho quando [isGeofenceWarning] ou [isNoFlyWarning] estão ativos.
/// - Botões de ação rápida: Decolar, Pousar, RTH e Reset.
///
/// Pode ser utilizado de forma puramente declarativa com valores primitivos
/// e callbacks, ou integrado diretamente a um [SimulatorController].
class TelemetryHud extends StatelessWidget {
  final double altitude;
  final double speed;
  final double distanceToHome;
  final double battery;
  final bool isGeofenceWarning;
  final bool isNoFlyWarning;
  final String? warningMessage;

  final VoidCallback? onTakeoff;
  final VoidCallback? onLand;
  final VoidCallback? onRth;
  final VoidCallback? onReset;
  final VoidCallback? onToggleCameraMode;

  final CameraViewMode cameraMode;
  final SimulatorController? controller;
  final HudActionsPlacement actionsPlacement;

  const TelemetryHud({
    super.key,
    this.altitude = 0.0,
    this.speed = 0.0,
    this.distanceToHome = 0.0,
    this.battery = 100.0,
    this.isGeofenceWarning = false,
    this.isNoFlyWarning = false,
    this.warningMessage,
    this.onTakeoff,
    this.onLand,
    this.onRth,
    this.onReset,
    this.onToggleCameraMode,
    this.cameraMode = CameraViewMode.fpv,
    this.controller,
    this.actionsPlacement = HudActionsPlacement.top,
  });

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return AnimatedBuilder(
        animation: controller!,
        builder: (context, _) {
          final c = controller!;
          final dist = sqrt(c.x * c.x + c.y * c.y);
          final spd = c.physics.state.speedKmh;
          final geofenceWarn = c.physics.state.isGeofenceWarning;
          final noFlyWarn = c.physics.state.inNoFlyZone;

          return _buildHudContent(
            context: context,
            curAlt: c.z,
            curSpeed: spd,
            curDist: dist,
            curBattery: c.battery,
            curCameraMode: c.cameraMode,
            curGeofenceWarn: isGeofenceWarning || geofenceWarn,
            curNoFlyWarn: isNoFlyWarning || noFlyWarn,
            takeoffCb: onTakeoff ?? (c.isLanded ? c.armAndTakeoff : null),
            landCb: onLand ?? (!c.isLanded ? c.land : null),
            rthCb: onRth ?? (!c.isLanded ? c.triggerRTH : null),
            resetCb: onReset ?? c.reset,
            toggleCameraCb: onToggleCameraMode ?? c.toggleCameraMode,
          );
        },
      );
    }

    return _buildHudContent(
      context: context,
      curAlt: altitude,
      curSpeed: speed,
      curDist: distanceToHome,
      curBattery: battery,
      curCameraMode: cameraMode,
      curGeofenceWarn: isGeofenceWarning,
      curNoFlyWarn: isNoFlyWarning,
      takeoffCb: onTakeoff,
      landCb: onLand,
      rthCb: onRth,
      resetCb: onReset,
      toggleCameraCb: onToggleCameraMode,
    );
  }

  Widget _buildHudContent({
    required BuildContext context,
    required double curAlt,
    required double curSpeed,
    required double curDist,
    required double curBattery,
    required CameraViewMode curCameraMode,
    required bool curGeofenceWarn,
    required bool curNoFlyWarn,
    required VoidCallback? takeoffCb,
    required VoidCallback? landCb,
    required VoidCallback? rthCb,
    required VoidCallback? resetCb,
    required VoidCallback? toggleCameraCb,
  }) {
    return SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Barra Superior de Telemetria ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border.all(
                color: (curGeofenceWarn || curNoFlyWarn)
                    ? Colors.redAccent
                    : Colors.cyanAccent.withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                // Grupo de Telemetria
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildPill(
                      icon: Icons.height,
                      label: 'ALTITUDE',
                      value: '${curAlt.toStringAsFixed(1)} m',
                      valueColor: Colors.cyanAccent,
                    ),
                    _buildPill(
                      icon: Icons.speed,
                      label: 'VELOCIDADE',
                      value: '${curSpeed.toStringAsFixed(1)} km/h',
                      valueColor: Colors.white,
                    ),
                    _buildPill(
                      icon: Icons.home_outlined,
                      label: 'HOME',
                      value: '${curDist.toStringAsFixed(0)} m',
                      valueColor: Colors.white,
                    ),
                    _buildBatteryPill(curBattery),
                  ],
                ),

                // Grupo de Modo de Câmera e Ações de Voo (quando posicionados no topo)
                if (actionsPlacement == HudActionsPlacement.top)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildCameraModeButton(
                        cameraMode: curCameraMode,
                        onToggle: toggleCameraCb,
                      ),
                      _buildMapSettingsButton(context),
                      FlightActionButtons(
                        onTakeoff: takeoffCb,
                        onLand: landCb,
                        onRth: rthCb,
                        onReset: resetCb,
                        orientation: Axis.horizontal,
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // ── Banners de Alerta Vermelho ──
          if (curNoFlyWarn)
            _buildWarningBanner(
              key: const Key('banner_nofly'),
              icon: Icons.block,
              message: warningMessage ?? 'ALERTA: ZONA DE EXCLUSÃO AÉREA (NO-FLY ZONE)!',
            ),
          if (curGeofenceWarn)
            _buildWarningBanner(
              key: const Key('banner_geofence'),
              icon: Icons.warning_amber_rounded,
              message: warningMessage ?? 'ALERTA: LIMITE MÁXIMO DE GEOFENCE (500M) PRÓXIMO!',
            ),
        ],
      ),
    );
  }

  Widget _buildCameraModeButton({
    required CameraViewMode cameraMode,
    required VoidCallback? onToggle,
  }) {
    final isFpv = cameraMode == CameraViewMode.fpv;
    final label = isFpv ? '1ª Pessoa (FPV)' : '3ª Pessoa';
    final icon = isFpv ? Icons.videocam : Icons.accessibility_new;
    final isEnabled = onToggle != null;
    const color = Colors.cyanAccent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('btn_camera_mode'),
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isEnabled ? color.withOpacity(0.18) : Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isEnabled ? color.withOpacity(0.6) : Colors.white24,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isEnabled ? color : Colors.white38,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isEnabled ? color : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapSettingsButton(BuildContext context) {
    if (controller == null) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('btn_map_settings'),
        onTap: () => MapSettingsModal.show(context, controller!),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withOpacity(0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.cyanAccent.withOpacity(0.6),
              width: 1.0,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.layers,
                size: 14,
                color: Colors.cyanAccent,
              ),
              SizedBox(width: 4),
              Text(
                'Camadas',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPill({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 16),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryPill(double battery) {
    Color color;
    IconData icon;
    if (battery > 50) {
      color = Colors.greenAccent;
      icon = Icons.battery_full;
    } else if (battery > 20) {
      color = Colors.amberAccent;
      icon = Icons.battery_4_bar;
    } else {
      color = Colors.redAccent;
      icon = Icons.battery_alert;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'BATERIA',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '${battery.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner({
    required Key key,
    required IconData icon,
    required String message,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(top: 4, left: 12, right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withOpacity(0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Painel de botões de comando de voo (Decolar, Pousar, RTH e Reset).
///
/// Pode ser disposto horizontalmente (no topo) ou verticalmente (na lateral).
class FlightActionButtons extends StatelessWidget {
  final VoidCallback? onTakeoff;
  final VoidCallback? onLand;
  final VoidCallback? onRth;
  final VoidCallback? onReset;
  final Axis orientation;

  const FlightActionButtons({
    super.key,
    this.onTakeoff,
    this.onLand,
    this.onRth,
    this.onReset,
    this.orientation = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = [
      _buildButton(
        key: const Key('btn_takeoff'),
        icon: Icons.flight_takeoff,
        label: 'Decolar',
        color: Colors.greenAccent,
        onPressed: onTakeoff,
      ),
      _buildButton(
        key: const Key('btn_land'),
        icon: Icons.flight_land,
        label: 'Pousar',
        color: Colors.amberAccent,
        onPressed: onLand,
      ),
      _buildButton(
        key: const Key('btn_rth'),
        icon: Icons.home_work_outlined,
        label: 'RTH',
        color: Colors.cyanAccent,
        onPressed: onRth,
      ),
      _buildButton(
        key: const Key('btn_reset'),
        icon: Icons.refresh,
        label: 'Reset',
        color: Colors.redAccent,
        onPressed: onReset,
      ),
    ];

    if (orientation == Axis.vertical) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: buttons
              .map((b) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: b,
                  ))
              .toList(),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: buttons,
    );
  }

  Widget _buildButton({
    required Key key,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    final isEnabled = onPressed != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isEnabled ? color.withOpacity(0.18) : Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isEnabled ? color.withOpacity(0.6) : Colors.white24,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isEnabled ? color : Colors.white38,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isEnabled ? color : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
