import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:drone_simulator/models/drone_state.dart';
import 'package:drone_simulator/models/flight_map.dart';
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
  String? _lastMapId;
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

  void _checkMapChange(FlightMap activeMap) {
    if (_lastMapId != activeMap.id) {
      _lastMapId = activeMap.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(activeMap.center, activeMap.initialZoom);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final droneState = ref.watch(simulationProvider);
    final notifier = ref.read(simulationProvider.notifier);
    final waypoints = notifier.waypoints;
    final activeMap = droneState.activeMap;

    _checkMapChange(activeMap);

    return Scaffold(
      body: Stack(
        children: [
          // ── Layer 1: Map ──
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: activeMap.center,
              initialZoom: activeMap.initialZoom,
              cameraConstraint: CameraConstraint.containCenter(
                bounds: activeMap.bounds,
              ),
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

              // ── Geofence, Warnings, NFZs & Helipads ──
              CircleLayer(
                circles: [
                  // 1. Área de Voo Autorizada (Geofence principal)
                  CircleMarker(
                    point: activeMap.center,
                    radius: activeMap.radiusMeters,
                    useRadiusInMeter: true,
                    color: Colors.cyan.withOpacity(0.04),
                    borderColor: droneState.isGeofenceBreach
                        ? Colors.redAccent
                        : Colors.cyanAccent.withOpacity(0.7),
                    borderStrokeWidth: 2.0,
                  ),
                  // 2. Anel de Advertência de Proximidade (80% da área)
                  CircleMarker(
                    point: activeMap.center,
                    radius: activeMap.warningRadiusMeters,
                    useRadiusInMeter: true,
                    color: Colors.transparent,
                    borderColor: Colors.amberAccent.withOpacity(0.4),
                    borderStrokeWidth: 1.5,
                  ),
                  // 3. No-Fly Zones (NFZ) modeladas
                  ...activeMap.noFlyZones.map(
                    (nfz) => CircleMarker(
                      point: nfz.center,
                      radius: nfz.radiusMeters,
                      useRadiusInMeter: true,
                      color: Colors.red.withOpacity(0.24),
                      borderColor: Colors.redAccent,
                      borderStrokeWidth: 2.0,
                    ),
                  ),
                  // 4. Helipad central (círculos concêntricos de pouso)
                  CircleMarker(
                    point: droneState.homePosition,
                    radius: 20.0,
                    useRadiusInMeter: true,
                    color: Colors.blue.withOpacity(0.12),
                    borderColor: Colors.blueAccent.withOpacity(0.8),
                    borderStrokeWidth: 1.5,
                  ),
                  CircleMarker(
                    point: droneState.homePosition,
                    radius: 6.0,
                    useRadiusInMeter: true,
                    color: Colors.blue.withOpacity(0.25),
                    borderColor: Colors.white,
                    borderStrokeWidth: 2.0,
                  ),
                ],
              ),

              // ── Waypoint polylines ──
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
              // Linha do drone até o primeiro waypoint em missão
              if (droneState.flightMode == FlightMode.autoMission &&
                  waypoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [droneState.position, waypoints.first.position],
                      color: Colors.cyan.withOpacity(0.6),
                      strokeWidth: 1.5,
                      isDotted: true,
                    ),
                  ],
                ),

              // ── Markers Layer ──
              MarkerLayer(
                markers: [
                  // 1. Helipad Home Marker
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
                            color: Colors.black.withOpacity(0.5),
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

                  // 2. No-Fly Zone Labels
                  ...activeMap.noFlyZones.map(
                    (nfz) => Marker(
                      point: nfz.center,
                      width: 100,
                      height: 28,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.redAccent, width: 1),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.block, color: Colors.redAccent, size: 12),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                nfz.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 3. Map POIs & Obstacles (Gates, Torres, Birutas)
                  ...activeMap.pois.map(
                    (poi) => Marker(
                      point: poi.position,
                      width: 40,
                      height: 40,
                      child: _buildPoiWidget(poi),
                    ),
                  ),

                  // 4. Waypoint Markers
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

                  // 5. Drone Marker
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

          // ── Layer 2b: Geofence & NFZ HUD Alert Banner ──
          if (droneState.inNoFlyZone ||
              droneState.isGeofenceBreach ||
              droneState.isGeofenceWarning)
            Positioned(
              top: 60,
              left: 140,
              right: 140,
              child: _buildWarningHud(droneState),
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
            bottom: 155,
            child: SingleChildScrollView(
              child: Container(
                width: 140,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.cyan.withOpacity(0.3),
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
                      'RTL (VOLTAR)',
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
                      'ROTAS PRONTAS',
                      Icons.auto_awesome,
                      Colors.purpleAccent,
                      () => _showPresetMissionsDialog(context, activeMap, notifier),
                    ),
                    const SizedBox(height: 4),
                    _buildActionButton(
                      'CENTRALIZAR',
                      Icons.my_location,
                      Colors.cyanAccent,
                      () => _recenterMap(droneState),
                    ),
                    const SizedBox(height: 4),
                    _buildActionButton(
                      'LIMPAR ROTA',
                      Icons.delete_outline,
                      Colors.grey,
                      () => notifier.clearWaypoints(),
                    ),
                    const SizedBox(height: 6),
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
                  color: Colors.black.withOpacity(0.55),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 60),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.cyan.withOpacity(0.5),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyan.withOpacity(0.15),
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
                          const SizedBox(height: 12),
                          const Text(
                            'Drone Simulator — Área Modelada',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '• Área autorizada (Geofence): Raio de 500m / Teto 120m\n'
                            '• Ponto de decolagem "H" central com círculos de aproximação\n'
                            '• Toque no mapa para criar rotas ou use "ROTAS PRONTAS"\n'
                            '• Evite as áreas vermelhas (No-Fly Zones)',
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),
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
                              'COMEÇAR A VOAR',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
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

  Widget _buildWarningHud(DroneState droneState) {
    Color bg;
    IconData icon;
    String text;

    if (droneState.inNoFlyZone) {
      bg = Colors.red.shade900.withOpacity(0.9);
      icon = Icons.dangerous;
      text = 'ZONA PROIBIDA: ${droneState.currentNfzName ?? "ÁREA RESTRITA"}';
    } else if (droneState.isGeofenceBreach) {
      bg = Colors.red.shade800.withOpacity(0.85);
      icon = Icons.shield;
      text = 'LIMITE GEOFENCE (${droneState.activeMap.radiusMeters.toStringAsFixed(0)}m / ${droneState.activeMap.maxAltitudeMeters.toStringAsFixed(0)}m) ATINGIDO';
    } else {
      bg = Colors.amber.shade900.withOpacity(0.85);
      icon = Icons.warning_amber;
      text = 'ALERTA: APROXIMANDO DO PERÍMETRO (${droneState.distanceFromCenter.toStringAsFixed(0)}/${droneState.activeMap.radiusMeters.toStringAsFixed(0)}m)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white38, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoiWidget(MapPoi poi) {
    Color color;
    IconData icon;
    switch (poi.type) {
      case PoiType.gate:
        color = Colors.cyanAccent;
        icon = Icons.flag;
        break;
      case PoiType.tower:
        color = Colors.amberAccent;
        icon = Icons.cell_tower;
        break;
      case PoiType.windsock:
        color = Colors.greenAccent;
        icon = Icons.air;
        break;
      case PoiType.landingPad:
        color = Colors.blueAccent;
        icon = Icons.flight_land;
        break;
      case PoiType.obstacle:
        color = Colors.deepOrangeAccent;
        icon = Icons.warning_amber;
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
          child: Icon(icon, color: color, size: 12),
        ),
        if (poi.label != null)
          Text(
            poi.label!,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ),
      ],
    );
  }

  void _recenterMap(DroneState droneState) {
    _mapController.move(
      droneState.position,
      droneState.activeMap.initialZoom,
    );
  }

  void _showPresetMissionsDialog(
      BuildContext context, FlightMap activeMap, SimulationNotifier notifier) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        if (activeMap.presetMissions.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Nenhuma rota pronta configurada para este mapa.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Rotas Prontas — ${activeMap.name}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...activeMap.presetMissions.map(
                (mission) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.purple.withOpacity(0.2),
                    child: const Icon(Icons.route, color: Colors.purpleAccent, size: 18),
                  ),
                  title: Text(
                    mission.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${mission.description} • ${mission.waypoints.length} waypoints',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  trailing: const Icon(Icons.play_circle_fill, color: Colors.greenAccent),
                  onTap: () {
                    Navigator.pop(context);
                    notifier.loadPresetMission(mission);
                  },
                ),
              ),
            ],
          ),
        );
      },
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
