import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/models/world_obstacle.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/simulation/world_generator.dart';

/// Radar tático 2D sincronizado em tempo real com os obstáculos, portais e geofence do 3D.
///
/// Pode ser utilizado como mapa principal em tela cheia (com controles) ou como
/// radar tático Drone-Up no card Picture-in-Picture.
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
  final bool? rotateWithDrone;
  final bool? tacticalDarkMode;
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
    this.rotateWithDrone,
    this.tacticalDarkMode,
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
  late bool _rotateWithDrone;
  late bool _tacticalDarkMode;
  String? _lastMapId;

  @override
  void initState() {
    super.initState();
    _isSatellite = widget.controller?.isSatellite ?? widget.isSatellite;
    _followDrone = widget.followDrone;
    _rotateWithDrone = widget.rotateWithDrone ?? !widget.showControls;
    _tacticalDarkMode = widget.tacticalDarkMode ?? !widget.showControls;
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
    if (oldWidget.rotateWithDrone != widget.rotateWithDrone &&
        widget.rotateWithDrone != null) {
      _rotateWithDrone = widget.rotateWithDrone!;
    }
    if (oldWidget.tacticalDarkMode != widget.tacticalDarkMode &&
        widget.tacticalDarkMode != null) {
      _tacticalDarkMode = widget.tacticalDarkMode!;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _safeMove(LatLng center, double zoom, double rotationDeg) {
    try {
      _mapController.moveAndRotate(center, zoom, rotationDeg);
    } catch (_) {
      // MapController pode ainda não estar anexado antes do 1º frame em testes.
    }
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    final ctrl = widget.controller;
    if (ctrl != null) {
      if (_isSatellite != ctrl.isSatellite) {
        _isSatellite = ctrl.isSatellite;
      }
      final rotDeg = _rotateWithDrone ? -ctrl.radarHeadingDeg : 0.0;
      if (_followDrone) {
        final activeMap = widget.flightMap ?? ctrl.physics.activeMap;
        final currentLatLng =
            FlightMap.metersToLatLng(ctrl.x, ctrl.y, activeMap.center);
        try {
          _mapController.moveAndRotate(
              currentLatLng, _mapController.camera.zoom, rotDeg);
        } catch (_) {}
      } else if (_rotateWithDrone) {
        try {
          _mapController.rotate(rotDeg);
        } catch (_) {}
      }
    }
    setState(() {});
  }

  void _checkMapChange(FlightMap activeMap) {
    if (_lastMapId != activeMap.id) {
      _lastMapId = activeMap.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final zoom = widget.showControls
              ? activeMap.initialZoom
              : max(activeMap.initialZoom, 16.8);
          _safeMove(activeMap.center, zoom, 0.0);
        }
      });
    }
  }

  Polygon _rectPolygon({
    required LatLng origin,
    required double cx,
    required double cy,
    required double width,
    required double depth,
    required Color fill,
    required Color border,
    double borderWidth = 1.0,
  }) {
    final hw = width * 0.5;
    final hd = depth * 0.5;
    return Polygon(
      points: [
        FlightMap.metersToLatLng(cx - hw, cy - hd, origin),
        FlightMap.metersToLatLng(cx + hw, cy - hd, origin),
        FlightMap.metersToLatLng(cx + hw, cy + hd, origin),
        FlightMap.metersToLatLng(cx - hw, cy + hd, origin),
      ],
      color: fill,
      borderColor: border,
      borderStrokeWidth: borderWidth,
      isFilled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final activeMap =
        widget.flightMap ?? ctrl?.physics.activeMap ?? FlightMap.dronePark;
    final double curX = ctrl != null ? ctrl.x : widget.droneX;
    final double curY = ctrl != null ? ctrl.y : widget.droneY;
    final double curZ = ctrl != null ? ctrl.z : widget.droneZ;
    final double curYaw = ctrl != null
        ? (ctrl.yaw != 0.0 ? ctrl.yaw : ctrl.physics.state.heading)
        : widget.yaw;
    final double radarHeading = ctrl?.radarHeadingDeg ?? curYaw;
    final double mapRotationDeg = _rotateWithDrone ? -radarHeading : 0.0;
    final bool isGeofenceWarning =
        ctrl?.isGeofenceWarning ?? ctrl?.physics.state.isGeofenceWarning ?? false;

    _checkMapChange(activeMap);

    final LatLng dronePosition =
        FlightMap.metersToLatLng(curX, curY, activeMap.center);

    final scenario = WorldGenerator.scenarioFor(activeMap);
    final obstacles = WorldGenerator.generateFor(activeMap);

    // ── Geometria do cenário + obstáculos retangulares (prédios, barragem, pilares) ──
    final polygons = <Polygon>[];
    if (scenario == WorldScenario.canyon) {
      polygons.add(_rectPolygon(
        origin: activeMap.center,
        cx: 10,
        cy: -250,
        width: 900,
        depth: 560,
        fill: const Color(0x551B7BA6),
        border: const Color(0x8838BDF8),
        borderWidth: 1.0,
      ));
      polygons.add(_rectPolygon(
        origin: activeMap.center,
        cx: -5,
        cy: -60,
        width: 430,
        depth: 11,
        fill: const Color(0x7794A3B8),
        border: const Color(0xBBCBD5E1),
        borderWidth: 1.0,
      ));
    } else if (scenario == WorldScenario.urban && _tacticalDarkMode) {
      polygons.add(_rectPolygon(
        origin: activeMap.center,
        cx: 0,
        cy: 0,
        width: 22,
        depth: 980,
        fill: const Color(0x55334155),
        border: const Color(0x4464748B),
        borderWidth: 0.6,
      ));
      polygons.add(_rectPolygon(
        origin: activeMap.center,
        cx: 0,
        cy: 0,
        width: 980,
        depth: 22,
        fill: const Color(0x55334155),
        border: const Color(0x4464748B),
        borderWidth: 0.6,
      ));
    }

    final obstacleCircles = <CircleMarker>[];
    for (final o in obstacles) {
      final atRisk = o.height >= curZ - 1.5;
      if (o.isCylindrical) {
        late Color fill;
        late Color border;
        if (o.type == ObstacleType.tower) {
          fill = atRisk ? const Color(0xBBFF3B30) : const Color(0x77F97316);
          border = Colors.redAccent;
        } else if (atRisk) {
          fill = const Color(0x77EF4444);
          border = const Color(0xBBFCA5A5);
        } else {
          fill = o.type == ObstacleType.tree
              ? const Color(0x4422C55E)
              : const Color(0x4494A3B8);
          border = Colors.transparent;
        }
        obstacleCircles.add(CircleMarker(
          point: FlightMap.metersToLatLng(o.x, o.y, activeMap.center),
          radius: max(o.radius, o.type == ObstacleType.tower ? 3.5 : 2.2),
          useRadiusInMeter: true,
          color: fill,
          borderColor: border,
          borderStrokeWidth: o.type == ObstacleType.tower ? 1.5 : 0.8,
        ));
      } else {
        final fill = atRisk ? const Color(0x88EF4444) : const Color(0x3D38BDF8);
        final border =
            atRisk ? Colors.redAccent : const Color(0x7738BDF8);
        polygons.add(_rectPolygon(
          origin: activeMap.center,
          cx: o.x,
          cy: o.y,
          width: o.width,
          depth: o.depth,
          fill: fill,
          border: border,
          borderWidth: atRisk ? 1.2 : 0.7,
        ));
      }
    }

    // ── Linhas táticas: rastro, cone de visão e rota para portais ──
    final polylines = <Polyline>[];

    // Cone de visão frontal (28m à frente, ±26°)
    final yawRad = curYaw * pi / 180.0;
    const coneRange = 28.0;
    const halfFov = 26.0 * pi / 180.0;
    final leftCone = FlightMap.metersToLatLng(
      curX + sin(yawRad - halfFov) * coneRange,
      curY + cos(yawRad - halfFov) * coneRange,
      activeMap.center,
    );
    final rightCone = FlightMap.metersToLatLng(
      curX + sin(yawRad + halfFov) * coneRange,
      curY + cos(yawRad + halfFov) * coneRange,
      activeMap.center,
    );
    polylines.add(Polyline(
      points: [leftCone, dronePosition, rightCone],
      color: Colors.cyanAccent.withOpacity(0.55),
      strokeWidth: 1.4,
    ));

    // Rastro recente de voo
    final trail = ctrl?.flightTrail ?? const <(double, double)>[];
    if (trail.length >= 2) {
      polylines.add(Polyline(
        points: [
          ...trail.map((p) => FlightMap.metersToLatLng(p.$1, p.$2, activeMap.center)),
          dronePosition,
        ],
        color: Colors.cyanAccent.withOpacity(0.65),
        strokeWidth: 2.0,
      ));
    }

    // Portais e rota do circuito (Corrida / Time Attack)
    final raceCourse = (ctrl != null && ctrl.isRaceMode) ? ctrl.raceCourse : null;
    final gateCircles = <CircleMarker>[];
    final gateMarkers = <Marker>[];
    if (raceCourse != null && raceCourse.gates.isNotEmpty) {
      final activeIndex = ctrl!.raceGateIndex;
      final nextIndex = (activeIndex + 1) % raceCourse.gates.length;

      final routePoints = [
        ...raceCourse.gates
            .map((g) => FlightMap.metersToLatLng(g.x, g.y, activeMap.center)),
        FlightMap.metersToLatLng(raceCourse.gates.first.x,
            raceCourse.gates.first.y, activeMap.center),
      ];
      polylines.add(Polyline(
        points: routePoints,
        color: Colors.white24,
        strokeWidth: 1.2,
      ));

      final activeGate = raceCourse.gates[activeIndex];
      final activeGateLatLng =
          FlightMap.metersToLatLng(activeGate.x, activeGate.y, activeMap.center);
      polylines.add(Polyline(
        points: [dronePosition, activeGateLatLng],
        color: Colors.amberAccent,
        strokeWidth: 2.2,
        isDotted: true,
      ));

      for (var i = 0; i < raceCourse.gates.length; i++) {
        final g = raceCourse.gates[i];
        final isActive = i == activeIndex;
        final isNext = i == nextIndex;
        final gateColor = isActive
            ? Colors.cyanAccent
            : (isNext ? Colors.greenAccent : Colors.white54);
        final pos = FlightMap.metersToLatLng(g.x, g.y, activeMap.center);

        gateCircles.add(CircleMarker(
          point: pos,
          radius: isActive ? g.radius * 1.4 : g.radius,
          useRadiusInMeter: true,
          color: gateColor.withOpacity(isActive ? 0.35 : 0.14),
          borderColor: gateColor,
          borderStrokeWidth: isActive ? 2.2 : 1.0,
        ));

        if (isActive || isNext || widget.showControls) {
          gateMarkers.add(Marker(
            point: pos,
            width: isActive ? 22 : 16,
            height: isActive ? 22 : 16,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? Colors.cyanAccent
                    : (isNext ? Colors.greenAccent : Colors.black87),
                border: Border.all(
                  color: Colors.black,
                  width: 1.2,
                ),
              ),
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  color: (isActive || isNext) ? Colors.black : Colors.white,
                  fontSize: isActive ? 10 : 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ));
        }
      }
    }

    final ghost = ctrl?.currentGhostFrame;

    final Widget mapContent = Stack(
      children: [
        // ── Camada FlutterMap com Tiles Reais + Radar Tático 3D ──
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: activeMap.center,
            initialZoom: widget.showControls
                ? widget.initialZoom
                : max(widget.initialZoom, 16.8),
            initialRotation: mapRotationDeg,
            cameraConstraint: CameraConstraint.containCenter(
              bounds: activeMap.bounds,
            ),
            interactionOptions: InteractionOptions(
              flags: widget.showControls ? InteractiveFlag.all : InteractiveFlag.none,
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

            // Máscara escura tática para leitura de obstáculos/portais estilo radar
            if (_tacticalDarkMode)
              IgnorePointer(
                child: Container(color: const Color(0xD808111B)),
              ),

            // 2. Polígonos do cenário e obstáculos retangulares (coloridos por altitude)
            PolygonLayer(polygons: polygons),

            // 3. Círculos Geofence (500m), No-Fly Zones, obstáculos cilíndricos e portais
            CircleLayer(
              circles: [
                CircleMarker(
                  point: activeMap.center,
                  radius: activeMap.radiusMeters,
                  useRadiusInMeter: true,
                  color: isGeofenceWarning
                      ? Colors.red.withOpacity(0.08)
                      : Colors.cyan.withOpacity(0.04),
                  borderColor: isGeofenceWarning
                      ? Colors.redAccent
                      : Colors.cyanAccent.withOpacity(0.75),
                  borderStrokeWidth: 2.0,
                ),
                CircleMarker(
                  point: activeMap.center,
                  radius: activeMap.warningRadiusMeters,
                  useRadiusInMeter: true,
                  color: Colors.transparent,
                  borderColor: Colors.amberAccent.withOpacity(0.35),
                  borderStrokeWidth: 1.2,
                ),
                ...activeMap.noFlyZones.map(
                  (nfz) => CircleMarker(
                    point: nfz.center,
                    radius: nfz.radiusMeters,
                    useRadiusInMeter: true,
                    color: Colors.red.withOpacity(0.26),
                    borderColor: Colors.redAccent,
                    borderStrokeWidth: 2.0,
                  ),
                ),
                ...obstacleCircles,
                ...gateCircles,
                CircleMarker(
                  point: activeMap.homePosition,
                  radius: 14.0,
                  useRadiusInMeter: true,
                  color: Colors.blue.withOpacity(0.18),
                  borderColor: Colors.blueAccent.withOpacity(0.85),
                  borderStrokeWidth: 1.5,
                ),
              ],
            ),

            // 4. Cone de visão, rastro de voo e linha até próximo portal
            PolylineLayer(polylines: polylines),

            // 5. Marcadores de Home, NFZs, Portais, Ghost e Drone
            MarkerLayer(
              markers: [
                Marker(
                  point: activeMap.homePosition,
                  width: widget.showControls ? 28 : 20,
                  height: widget.showControls ? 28 : 20,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blue.shade700,
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        'H',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: widget.showControls ? 13 : 10,
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.showControls)
                  ...activeMap.noFlyZones.map(
                    (nfz) => Marker(
                      point: nfz.center,
                      width: 100,
                      height: 24,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.redAccent, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.block,
                                color: Colors.redAccent, size: 11),
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
                ...gateMarkers,
                if (ghost != null)
                  Marker(
                    point: FlightMap.metersToLatLng(
                        ghost.x, ghost.y, activeMap.center),
                    width: 16,
                    height: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.cyanAccent.withOpacity(0.45),
                        border: Border.all(color: Colors.white70, width: 1),
                      ),
                    ),
                  ),
                Marker(
                  point: dronePosition,
                  width: widget.showControls ? 48 : 36,
                  height: widget.showControls ? 48 : 36,
                  child: Transform.rotate(
                    angle: (curYaw + mapRotationDeg) * pi / 180.0,
                    child: CustomPaint(
                      size: Size(widget.showControls ? 48 : 36,
                          widget.showControls ? 48 : 36),
                      painter: _MiniMapDronePainter(altitude: curZ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        // ── Controles Flutuantes do Mapa (quando em tela cheia) ──
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
                  IconButton(
                    icon: Icon(
                      _isSatellite ? Icons.satellite_alt : Icons.map,
                      color: Colors.cyanAccent,
                      size: 20,
                    ),
                    tooltip: _isSatellite
                        ? 'Mudar para Mapa de Ruas'
                        : 'Mudar para Satélite',
                    onPressed: () {
                      setState(() {
                        _isSatellite = !_isSatellite;
                      });
                      widget.controller?.setSatellite(_isSatellite);
                    },
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  IconButton(
                    icon: Icon(
                      _tacticalDarkMode ? Icons.radar : Icons.layers_clear,
                      color: _tacticalDarkMode
                          ? Colors.cyanAccent
                          : Colors.white60,
                      size: 20,
                    ),
                    tooltip: _tacticalDarkMode
                        ? 'Desativar Radar Escuro'
                        : 'Ativar Radar Escuro',
                    onPressed: () {
                      setState(() => _tacticalDarkMode = !_tacticalDarkMode);
                    },
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  IconButton(
                    icon: Icon(
                      _rotateWithDrone ? Icons.explore : Icons.north,
                      color: _rotateWithDrone
                          ? Colors.amberAccent
                          : Colors.white60,
                      size: 20,
                    ),
                    tooltip: _rotateWithDrone
                        ? 'Orientação: Proa para cima'
                        : 'Orientação: Norte fixo',
                    onPressed: () {
                      setState(() {
                        _rotateWithDrone = !_rotateWithDrone;
                        if (!_rotateWithDrone) {
                          try {
                            _mapController.rotate(0.0);
                          } catch (_) {}
                        }
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  const Divider(color: Colors.white24, height: 8),
                  IconButton(
                    icon: Icon(
                      _followDrone ? Icons.gps_fixed : Icons.gps_not_fixed,
                      color: _followDrone ? Colors.greenAccent : Colors.white60,
                      size: 20,
                    ),
                    tooltip:
                        _followDrone ? 'Câmera seguindo drone' : 'Seguir drone',
                    onPressed: () {
                      setState(() {
                        _followDrone = !_followDrone;
                        if (_followDrone) {
                          _safeMove(dronePosition, _mapController.camera.zoom,
                              mapRotationDeg);
                        }
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  const Divider(color: Colors.white24, height: 8),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white, size: 20),
                    tooltip: 'Aproximar',
                    onPressed: () {
                      _safeMove(
                        _mapController.camera.center,
                        (_mapController.camera.zoom + 0.5).clamp(12.0, 19.0),
                        mapRotationDeg,
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.remove, color: Colors.white, size: 20),
                    tooltip: 'Afastar',
                    onPressed: () {
                      _safeMove(
                        _mapController.camera.center,
                        (_mapController.camera.zoom - 0.5).clamp(12.0, 19.0),
                        mapRotationDeg,
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    if (widget.width != null ||
        widget.height != null ||
        widget.borderRadius != null) {
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

    if (altitude > 0.5) {
      final shadowOffset = Offset(2 + (altitude / 10).clamp(0.0, 6.0),
          3 + (altitude / 10).clamp(0.0, 6.0));
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
      canvas.drawCircle(center + shadowOffset, 10, shadowPaint);
    }

    final armPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center + Offset(-armLength, -armLength),
        center + Offset(armLength, armLength), armPaint);
    canvas.drawLine(center + Offset(armLength, -armLength),
        center + Offset(-armLength, armLength), armPaint);

    const motorRadius = 3.6;
    final frontLedPaint = Paint()..color = Colors.redAccent;
    final backLedPaint = Paint()..color = Colors.greenAccent;

    canvas.drawCircle(
        center + Offset(-armLength, -armLength), motorRadius, frontLedPaint);
    canvas.drawCircle(
        center + Offset(armLength, -armLength), motorRadius, frontLedPaint);
    canvas.drawCircle(
        center + Offset(-armLength, armLength), motorRadius, backLedPaint);
    canvas.drawCircle(
        center + Offset(armLength, armLength), motorRadius, backLedPaint);

    final bodyPaint = Paint()..color = Colors.cyanAccent;
    canvas.drawCircle(center, 5.5, bodyPaint);

    final bodyBorder = Paint()
      ..color = const Color(0xFF003844)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(center, 5.5, bodyBorder);

    final arrowPaint = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, center + Offset(0, -armLength - 4), arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _MiniMapDronePainter oldDelegate) {
    return oldDelegate.altitude != altitude;
  }
}
