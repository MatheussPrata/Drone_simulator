import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';

/// Widget de mapa real (Satélite / OpenStreetMap) com geofence, zonas No-Fly e drone dinâmico.
///
/// Pode ser utilizado como mapa principal em tela cheia (substituindo a grade vazia)
/// ou como mini-mapa em Picture-in-Picture.
class MiniMapWidget extends StatefulWidget {
  final SimulatorController? controller;
  final double droneX;
  final double droneY;
  final double droneZ;
  final double yaw;
  final FlightMap? flightMap;
  final bool followDrone;
  final bool isSatellite;
  final double initialZoom;
  final bool showControls;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  const MiniMapWidget({
    super.key,
    this.controller,
    this.droneX = 0.0,
    this.droneY = 0.0,
    this.droneZ = 0.0,
    this.yaw = 0.0,
    this.flightMap,
    this.followDrone = true,
    this.isSatellite = true,
    this.initialZoom = 16.5,
    this.showControls = true,
    this.width,
    this.height,
    this.borderRadius,
    this.onTap,
  });

  @override
  State<MiniMapWidget> createState() => _MiniMapWidgetState();
}

class _MiniMapWidgetState extends State<MiniMapWidget> {
  final MapController _mapController = MapController();
  late bool _isSatellite;
  late bool _followDrone;
  String? _lastMapId;

  @override
  void initState() {
    super.initState();
    _isSatellite = widget.controller?.isSatellite ?? widget.isSatellite;
    _followDrone = widget.followDrone;
    widget.controller?.addListener(_onControllerUpdate);
  }

  @override
  void didUpdateWidget(MiniMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerUpdate);
      widget.controller?.addListener(_onControllerUpdate);
    }
    if (widget.controller != null) {
      _isSatellite = widget.controller!.isSatellite;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    final ctrl = widget.controller;
    if (ctrl != null) {
      if (_isSatellite != ctrl.isSatellite) {
        _isSatellite = ctrl.isSatellite;
      }
      if (_followDrone) {
        final activeMap = widget.flightMap ?? ctrl.physics.activeMap;
        final currentLatLng = FlightMap.metersToLatLng(ctrl.x, ctrl.y, activeMap.center);
        _mapController.move(currentLatLng, _mapController.camera.zoom);
      }
    }
    setState(() {});
  }

  void _checkMapChange(FlightMap activeMap) {
    if (_lastMapId != activeMap.id) {
      _lastMapId = activeMap.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(activeMap.center, activeMap.initialZoom);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final activeMap = widget.flightMap ?? ctrl?.physics.activeMap ?? FlightMap.dronePark;
    final double curX = ctrl != null ? ctrl.x : widget.droneX;
    final double curY = ctrl != null ? ctrl.y : widget.droneY;
    final double curZ = ctrl != null ? ctrl.z : widget.droneZ;
    final double curYaw = ctrl != null ? (ctrl.yaw != 0.0 ? ctrl.yaw : ctrl.physics.state.heading) : widget.yaw;
    final bool isGeofenceWarning = ctrl?.physics.state.isGeofenceWarning ?? false;

    _checkMapChange(activeMap);

    final LatLng dronePosition = FlightMap.metersToLatLng(curX, curY, activeMap.center);

    Widget mapContent = Stack(
      children: [
        // ── Camada FlutterMap com Tiles Reais ──
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: activeMap.center,
            initialZoom: widget.initialZoom,
            cameraConstraint: CameraConstraint.containCenter(
              bounds: activeMap.bounds,
            ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            // 1. Provedor de Tiles Reais (Satélite Esri / Ruas OpenStreetMap)
            TileLayer(
              urlTemplate: _isSatellite
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{y}/{x}.png',
              userAgentPackageName: 'com.dronesim.drone_simulator',
            ),

            // 2. Círculos Geofence (500m) e No-Fly Zones
            CircleLayer(
              circles: [
                // Geofence de 500m (área autorizada)
                CircleMarker(
                  point: activeMap.center,
                  radius: activeMap.radiusMeters,
                  useRadiusInMeter: true,
                  color: isGeofenceWarning
                      ? Colors.red.withOpacity(0.08)
                      : Colors.cyan.withOpacity(0.05),
                  borderColor: isGeofenceWarning
                      ? Colors.redAccent
                      : Colors.cyanAccent.withOpacity(0.8),
                  borderStrokeWidth: 2.0,
                ),

                // Anel de aviso preventivo de 400m (80% do geofence)
                CircleMarker(
                  point: activeMap.center,
                  radius: activeMap.warningRadiusMeters,
                  useRadiusInMeter: true,
                  color: Colors.transparent,
                  borderColor: Colors.amberAccent.withOpacity(0.4),
                  borderStrokeWidth: 1.5,
                ),

                // Zonas No-Fly (NFZ) em vermelho translúcido
                ...activeMap.noFlyZones.map(
                  (nfz) => CircleMarker(
                    point: nfz.center,
                    radius: nfz.radiusMeters,
                    useRadiusInMeter: true,
                    color: Colors.red.withOpacity(0.28),
                    borderColor: Colors.redAccent,
                    borderStrokeWidth: 2.0,
                  ),
                ),

                // Helipad Central (Ponto de Pouso H)
                CircleMarker(
                  point: activeMap.homePosition,
                  radius: 20.0,
                  useRadiusInMeter: true,
                  color: Colors.blue.withOpacity(0.15),
                  borderColor: Colors.blueAccent.withOpacity(0.85),
                  borderStrokeWidth: 1.5,
                ),
              ],
            ),

            // 3. Marcadores de Home, NFZs e Drone
            MarkerLayer(
              markers: [
                // Ponto Home "H"
                Marker(
                  point: activeMap.homePosition,
                  width: 30,
                  height: 30,
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
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),

                // Etiquetas de No-Fly Zone
                ...activeMap.noFlyZones.map(
                  (nfz) => Marker(
                    point: nfz.center,
                    width: 100,
                    height: 24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.redAccent, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.block, color: Colors.redAccent, size: 11),
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

                // Marcador do Drone (Rotacionado pelo Yaw)
                Marker(
                  point: dronePosition,
                  width: 48,
                  height: 48,
                  child: Transform.rotate(
                    angle: curYaw * pi / 180.0,
                    child: CustomPaint(
                      size: const Size(48, 48),
                      painter: _MiniMapDronePainter(altitude: curZ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        // ── Controles Flutuantes do Mapa ──
        if (widget.showControls)
          Positioned(
            right: 12,
            top: 75,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Alternar Satélite / Ruas
                  IconButton(
                    icon: Icon(
                      _isSatellite ? Icons.satellite_alt : Icons.map,
                      color: Colors.cyanAccent,
                      size: 20,
                    ),
                    tooltip: _isSatellite ? 'Mudar para Mapa de Ruas' : 'Mudar para Satélite',
                    onPressed: () {
                      setState(() {
                        _isSatellite = !_isSatellite;
                      });
                      widget.controller?.setSatellite(_isSatellite);
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  const Divider(color: Colors.white24, height: 8),

                  // Seguir Drone (Trava de câmera)
                  IconButton(
                    icon: Icon(
                      _followDrone ? Icons.gps_fixed : Icons.gps_not_fixed,
                      color: _followDrone ? Colors.greenAccent : Colors.white60,
                      size: 20,
                    ),
                    tooltip: _followDrone ? 'Câmera seguindo drone' : 'Seguir drone',
                    onPressed: () {
                      setState(() {
                        _followDrone = !_followDrone;
                        if (_followDrone) {
                          _mapController.move(dronePosition, _mapController.camera.zoom);
                        }
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  const Divider(color: Colors.white24, height: 8),

                  // Zoom In (+)
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white, size: 20),
                    tooltip: 'Aproximar',
                    onPressed: () {
                      _mapController.move(
                        _mapController.camera.center,
                        (_mapController.camera.zoom + 0.5).clamp(12.0, 19.0),
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),

                  // Zoom Out (-)
                  IconButton(
                    icon: const Icon(Icons.remove, color: Colors.white, size: 20),
                    tooltip: 'Afastar',
                    onPressed: () {
                      _mapController.move(
                        _mapController.camera.center,
                        (_mapController.camera.zoom - 0.5).clamp(12.0, 19.0),
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    if (widget.width != null || widget.height != null || widget.borderRadius != null) {
      return ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.zero,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: mapContent,
        ),
      );
    }

    return SizedBox.expand(child: mapContent);
  }
}

/// Desenha o ícone do quadricóptero com braços em X, motores e luzes de navegação
class _MiniMapDronePainter extends CustomPainter {
  final double altitude;

  _MiniMapDronePainter({this.altitude = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final armLength = size.width * 0.35;

    // Sombra projetada se o drone estiver em altitude (z > 0)
    if (altitude > 0.5) {
      final shadowOffset = Offset(2 + (altitude / 10).clamp(0.0, 6.0), 3 + (altitude / 10).clamp(0.0, 6.0));
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
      canvas.drawCircle(center + shadowOffset, 12, shadowPaint);
    }

    // Braços em X
    final armPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center + Offset(-armLength, -armLength),
      center + Offset(armLength, armLength),
      armPaint,
    );
    canvas.drawLine(
      center + Offset(armLength, -armLength),
      center + Offset(-armLength, armLength),
      armPaint,
    );

    // Motores com LEDs frontais e traseiros
    const motorRadius = 4.5;
    final frontLedPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;
    final backLedPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;

    // Motores dianteiros (vermelhos)
    canvas.drawCircle(center + Offset(-armLength, -armLength), motorRadius, frontLedPaint);
    canvas.drawCircle(center + Offset(armLength, -armLength), motorRadius, frontLedPaint);

    // Motores traseiros (verdes)
    canvas.drawCircle(center + Offset(-armLength, armLength), motorRadius, backLedPaint);
    canvas.drawCircle(center + Offset(armLength, armLength), motorRadius, backLedPaint);

    // Corpo central do drone
    final bodyPaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 6.5, bodyPaint);

    final bodyBorder = Paint()
      ..color = const Color(0xFF003844)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(center, 6.5, bodyBorder);

    // Indicador de proa (seta frontal)
    final arrowPaint = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, center + Offset(0, -armLength - 5), arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _MiniMapDronePainter oldDelegate) {
    return oldDelegate.altitude != altitude;
  }
}
