import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:drone_simulator/models/drone_state.dart';
import 'package:drone_simulator/providers/simulation_provider.dart';
import 'package:drone_simulator/ui/widgets/telemetry_bar.dart';
import 'package:drone_simulator/ui/widgets/artificial_horizon.dart';
import 'package:drone_simulator/ui/widgets/virtual_joysticks.dart';
import 'dart:math';

class SimulatorScreen extends ConsumerStatefulWidget {
  const SimulatorScreen({super.key});

  @override
  ConsumerState<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends ConsumerState<SimulatorScreen> {
  final MapController _mapController = MapController();
  bool _useSatelliteMap = true;
  bool _showTip = true;
  double _currentThrottle = 0.0;
  double _currentYaw = 0.0;
  double _currentPitch = 0.0;
  double _currentRoll = 0.0;
  double _windSliderValue = 0.0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  Widget build(BuildContext context) {
    final droneState = ref.watch(simulationProvider);
    final notifier = ref.read(simulationProvider.notifier);
    final waypoints = notifier.waypoints;

    return Scaffold(
      body: Stack(
        children: [
          // ── Layer 1: Map ──
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(-23.5505, -46.6333),
              initialZoom: 17.0,
              onTap: (tapPosition, latLng) {
                notifier.addWaypoint(latLng);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _useSatelliteMap
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{y}/{x}.png',
                userAgentPackageName: 'com.dronesim.drone_simulator',
              ),
              // Waypoint polyline
              if (waypoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: waypoints.map((w) => w.position).toList(),
                      color: Colors.orangeAccent,
                      strokeWidth: 2.5,
                      isDotted: true,
                    ),
                  ],
                ),
              // Line from drone to first waypoint during mission
              if (droneState.flightMode == FlightMode.autoMission &&
                  waypoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [droneState.position, waypoints.first.position],
                      color: Colors.cyan.withOpacity(0.5),
                      strokeWidth: 1.5,
                      isDotted: true,
                    ),
                  ],
                ),
              // Markers layer
              MarkerLayer(
                markers: [
                  // Home marker
                  if (droneState.flightMode != FlightMode.disarmed)
                    Marker(
                      point: droneState.homePosition,
                      width: 32,
                      height: 32,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue.shade700,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'H',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Waypoint markers
                  ...waypoints.map(
                    (wp) => Marker(
                      point: wp.position,
                      width: 28,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.orange.shade700,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            '${wp.id}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Drone marker
                  Marker(
                    point: droneState.position,
                    width: 44,
                    height: 44,
                    child: Transform.rotate(
                      angle: droneState.heading * pi / 180.0,
                      child: CustomPaint(
                        size: const Size(44, 44),
                        painter: _DroneIconPainter(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Layer 2: Telemetry bar ──
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: TelemetryBar(),
          ),

          // ── Layer 3: Artificial horizon ──
          Positioned(
            top: 64,
            right: 10,
            child: ArtificialHorizon(
              pitch: droneState.pitch,
              roll: droneState.roll,
              heading: droneState.heading,
              size: 130,
            ),
          ),

          // ── Layer 4: Side panel ──
          Positioned(
            right: 10,
            top: 204,
            bottom: 160,
            child: SingleChildScrollView(
              child: Container(
                width: 140,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.cyan.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildActionButton(
                      'DECOLAR',
                      Icons.flight_takeoff,
                      Colors.green,
                      () => notifier.takeoff(),
                    ),
                    const SizedBox(height: 4),
                    _buildActionButton(
                      'MISSÃO',
                      Icons.route,
                      Colors.orange,
                      () => notifier.startMission(),
                    ),
                    const SizedBox(height: 4),
                    _buildActionButton(
                      'RTL',
                      Icons.home,
                      Colors.red,
                      () => notifier.triggerRTL(),
                    ),
                    const SizedBox(height: 4),
                    _buildActionButton(
                      'POUSAR',
                      Icons.flight_land,
                      Colors.amber,
                      () => notifier.land(),
                    ),
                    const SizedBox(height: 4),
                    _buildActionButton(
                      'LIMPAR ROTA',
                      Icons.delete_outline,
                      Colors.grey,
                      () => notifier.clearWaypoints(),
                    ),
                    const SizedBox(height: 8),
                    // Wind slider
                    Text(
                      'Vento: ${_windSliderValue.toStringAsFixed(0)} km/h',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        activeTrackColor: Colors.cyan,
                        inactiveTrackColor: Colors.grey.shade800,
                        thumbColor: Colors.cyan,
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        value: _windSliderValue,
                        min: 0,
                        max: 50,
                        onChanged: (value) {
                          setState(() {
                            _windSliderValue = value;
                          });
                          notifier.setWindSpeed(value);
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    // GPS toggle
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () => notifier.toggleGps(),
                        icon: Icon(
                          droneState.gpsLocked ? Icons.gps_fixed : Icons.gps_off,
                          size: 14,
                          color: droneState.gpsLocked
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                        label: Text(
                          droneState.gpsLocked ? 'GPS ON' : 'ATTI MODE',
                          style: TextStyle(
                            fontSize: 10,
                            color: droneState.gpsLocked
                                ? Colors.greenAccent
                                : Colors.redAccent,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: Colors.grey.shade900,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Map toggle
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _useSatelliteMap = !_useSatelliteMap;
                          });
                        },
                        icon: Icon(
                          _useSatelliteMap ? Icons.satellite_alt : Icons.map,
                          size: 14,
                          color: Colors.white70,
                        ),
                        label: Text(
                          _useSatelliteMap ? 'Satélite' : 'Ruas',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white70,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: Colors.grey.shade900,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Layer 5: Joysticks ──
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: DualJoysticks(
              onLeftChanged: (throttle, yaw) {
                _currentThrottle = throttle;
                _currentYaw = yaw;
                notifier.setManualInput(
                  _currentThrottle,
                  _currentYaw,
                  _currentPitch,
                  _currentRoll,
                );
              },
              onRightChanged: (pitch, roll) {
                _currentPitch = pitch;
                _currentRoll = roll;
                notifier.setManualInput(
                  _currentThrottle,
                  _currentYaw,
                  _currentPitch,
                  _currentRoll,
                );
              },
              onTouchDown: () {
                if (droneState.flightMode == FlightMode.autoMission) {
                  notifier.overrideToManual();
                }
              },
            ),
          ),

          // ── Layer 6: First-time tip ──
          if (_showTip)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showTip = false),
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 60),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.cyan.withOpacity(0.4),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyan.withOpacity(0.1),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.flight,
                            color: Colors.cyan,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Drone Simulator v1.0',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Toque no mapa para criar uma rota autônoma\n'
                            'ou use os controles na tela para pilotar.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: () => setState(() => _showTip = false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyan,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'ENTENDI',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 32,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.3),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: color.withOpacity(0.5), width: 1),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

class _DroneIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final armLength = size.width * 0.35;

    // Draw drone body (center circle)
    final bodyPaint = Paint()..color = Colors.cyan.shade700;
    canvas.drawCircle(center, 5, bodyPaint);

    // Draw arms (X shape)
    final armPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Top-left to bottom-right arm
    canvas.drawLine(
      center + Offset(-armLength, -armLength),
      center + Offset(armLength, armLength),
      armPaint,
    );
    // Top-right to bottom-left arm
    canvas.drawLine(
      center + Offset(armLength, -armLength),
      center + Offset(-armLength, armLength),
      armPaint,
    );

    // Draw motor circles at arm tips
    final motorPaint = Paint()
      ..color = Colors.cyan
      ..style = PaintingStyle.fill;
    const motorRadius = 4.0;
    canvas.drawCircle(center + Offset(-armLength, -armLength), motorRadius, motorPaint);
    canvas.drawCircle(center + Offset(armLength, -armLength), motorRadius, motorPaint);
    canvas.drawCircle(center + Offset(-armLength, armLength), motorRadius, motorPaint);
    canvas.drawCircle(center + Offset(armLength, armLength), motorRadius, motorPaint);

    // Draw direction indicator (front - top)
    final dirPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center,
      center + Offset(0, -armLength - 4),
      dirPaint,
    );

    // Draw small front triangle
    final trianglePath = Path()
      ..moveTo(center.dx, center.dy - armLength - 7)
      ..lineTo(center.dx - 3, center.dy - armLength - 2)
      ..lineTo(center.dx + 3, center.dy - armLength - 2)
      ..close();
    canvas.drawPath(trianglePath, Paint()..color = Colors.red);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
