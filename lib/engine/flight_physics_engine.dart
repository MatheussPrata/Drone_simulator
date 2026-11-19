import 'dart:async';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:drone_simulator/core/utils/geo_math.dart';
import 'package:drone_simulator/models/drone_state.dart';
import 'package:drone_simulator/models/drone_profile.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/models/waypoint.dart';

class FlightPhysicsEngine {
  Timer? _timer;
  DroneState _state;
  FlightMap _activeMap;
  List<Waypoint> _waypoints = [];
  int _currentWaypointIndex = 0;
  double _hoverTimer = 0.0;
  double _manualThrottle = 0.0;
  double _manualYaw = 0.0;
  double _manualPitch = 0.0;
  double _manualRoll = 0.0;
  double _velocityX = 0.0; // m/s East-West
  double _velocityY = 0.0; // m/s North-South
  double _verticalVelocity = 0.0; // m/s Up-Down
  final Random _random = Random();

  Function(DroneState)? onStateChanged;

  DroneState get state => _state;
  FlightMap get activeMap => _activeMap;

  FlightPhysicsEngine({FlightMap? initialMap})
      : _activeMap = initialMap ?? FlightMap.dronePark,
        _state = DroneState(
          position: (initialMap ?? FlightMap.dronePark).homePosition,
          homePosition: (initialMap ?? FlightMap.dronePark).homePosition,
          activeProfile: DroneProfile.mini249g,
          activeMap: initialMap ?? FlightMap.dronePark,
        );

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), _tick);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
  }

  void _tick(Timer t) {
    const double dt = 0.05;
    final profile = _state.activeProfile;

    if (_state.flightMode == FlightMode.disarmed) {
      onStateChanged?.call(_state);
      return;
    }

    // ── Wind simulation ──
    final windRadians = _state.windDirectionDeg * pi / 180.0;
    final windSpeedMs = _state.windSpeedKmh / 3.6;
    final windForceX = windSpeedMs * sin(windRadians) * profile.windSensitivity;
    final windForceY = windSpeedMs * cos(windRadians) * profile.windSensitivity;

    double newBattery = _state.batteryPercent;
    double baseDrain = profile.baseDrainPerSecond * dt;

    // ── Mode-specific logic ──
    switch (_state.flightMode) {
      case FlightMode.hover:
      case FlightMode.manual:
        _processManualFlight(dt, profile, windForceX, windForceY);
        break;
      case FlightMode.autoMission:
        _processAutoMission(dt, profile, windForceX, windForceY);
        break;
      case FlightMode.rtl:
        _processRTL(dt, profile, windForceX, windForceY);
        break;
      case FlightMode.landing:
        _processLanding(dt, windForceX, windForceY);
        break;
      case FlightMode.disarmed:
        break;
    }

    // ── Wind drift (ATTI mode) or GPS compensation ──
    if (!_state.gpsLocked) {
      _velocityX += windForceX * dt;
      _velocityY += windForceY * dt;
    } else {
      // GPS compensates but costs more battery
      baseDrain += baseDrain * (windSpeedMs / 10.0).clamp(0.0, 1.5);
    }

    // ── Position update ──
    LatLng newPosition = GeoMath.offsetByMeters(
      _state.position,
      _velocityX * dt,
      _velocityY * dt,
    );

    // ── Geofence boundary enforcing ──
    double distFromCenter = GeoMath.distanceMeters(newPosition, _activeMap.center);
    bool breach = false;

    if (distFromCenter > _activeMap.radiusMeters) {
      breach = true;
      // Soft barrier: reposiciona na borda e inverte vetor de velocidade externo
      final bearingFromCenter = GeoMath.bearing(_activeMap.center, newPosition);
      final bearingRad = bearingFromCenter * pi / 180.0;
      newPosition = GeoMath.offsetByMeters(
        _activeMap.center,
        sin(bearingRad) * _activeMap.radiusMeters,
        cos(bearingRad) * _activeMap.radiusMeters,
      );
      _velocityX *= -0.2;
      _velocityY *= -0.2;
      distFromCenter = _activeMap.radiusMeters;
    }

    // ── Altitude update (com teto máximo do mapa modelado) ──
    double newAltitude = (_state.altitude + _verticalVelocity * dt).clamp(0.0, _activeMap.maxAltitudeMeters);
    if (newAltitude >= _activeMap.maxAltitudeMeters) {
      _verticalVelocity = min(0.0, _verticalVelocity);
      breach = true;
    }

    // ── Geofence warning threshold ──
    final isWarning = distFromCenter >= _activeMap.warningRadiusMeters ||
        newAltitude >= (_activeMap.maxAltitudeMeters - 15.0);

    // ── No-Fly Zone check ──
    bool inNfz = false;
    String? nfzName;
    for (final nfz in _activeMap.noFlyZones) {
      if (GeoMath.distanceMeters(newPosition, nfz.center) <= nfz.radiusMeters) {
        inNfz = true;
        nfzName = nfz.name;
        break;
      }
    }

    // ── Speed calculation ──
    final horizontalSpeed = sqrt(_velocityX * _velocityX + _velocityY * _velocityY);
    final speedKmh = horizontalSpeed * 3.6;

    // ── Battery drain ──
    if (_verticalVelocity > 0) {
      baseDrain += baseDrain * 0.5; // climbing costs more
    }
    baseDrain += baseDrain * (speedKmh / profile.maxSpeedKmh) * 0.3;
    newBattery = (newBattery - baseDrain).clamp(0.0, 100.0);
    final newVoltage = 9.9 + (newBattery / 100.0) * 2.7;

    // ── Visual pitch/roll ──
    double visualPitch = (_manualPitch * -25.0).clamp(-30.0, 30.0);
    double visualRoll = (_manualRoll * 25.0).clamp(-30.0, 30.0);

    if (_state.flightMode == FlightMode.autoMission ||
        _state.flightMode == FlightMode.rtl) {
      visualPitch = (-(horizontalSpeed / (profile.maxSpeedKmh / 3.6)) * 15.0).clamp(-25.0, 25.0);
      visualRoll = 0.0;
    }

    // ── Fail-safe: RTL at 15% battery ──
    FlightMode newMode = _state.flightMode;
    if (newBattery <= 15.0 &&
        newMode != FlightMode.rtl &&
        newMode != FlightMode.landing &&
        newMode != FlightMode.disarmed) {
      newMode = FlightMode.rtl;
    }

    // ── Landing complete ──
    if (newMode == FlightMode.landing && newAltitude <= 0.1) {
      newAltitude = 0.0;
      _velocityX = 0.0;
      _velocityY = 0.0;
      _verticalVelocity = 0.0;
      newMode = FlightMode.disarmed;
    }

    _state = _state.copyWith(
      position: newPosition,
      altitude: newAltitude,
      speedKmh: speedKmh,
      verticalSpeedMs: _verticalVelocity,
      heading: _state.heading,
      pitch: visualPitch,
      roll: visualRoll,
      batteryPercent: newBattery,
      voltage: newVoltage,
      flightMode: newMode,
      distanceFromCenter: distFromCenter,
      isGeofenceWarning: isWarning,
      isGeofenceBreach: breach,
      inNoFlyZone: inNfz,
      currentNfzName: nfzName,
    );

    onStateChanged?.call(_state);
  }

  void _processManualFlight(
      double dt, DroneProfile profile, double windForceX, double windForceY) {
    // Heading rotation (yaw)
    const double yawRate = 120.0; // deg/sec
    double newHeading = (_state.heading + _manualYaw * yawRate * dt) % 360.0;
    if (newHeading < 0) newHeading += 360.0;

    // Vertical velocity (throttle)
    if (_manualThrottle.abs() > 0.05) {
      _verticalVelocity = _manualThrottle > 0
          ? _manualThrottle * profile.maxAscentMs
          : _manualThrottle * profile.maxDescentMs;
    } else {
      _verticalVelocity *= 0.9; // hover damping
      if (_verticalVelocity.abs() < 0.05) _verticalVelocity = 0.0;
    }

    // Pitch & roll translate to local forward/backward & strafe
    final headingRad = newHeading * pi / 180.0;
    final forwardX = sin(headingRad);
    final forwardY = cos(headingRad);
    final rightX = cos(headingRad);
    final rightY = -sin(headingRad);

    final inputAccelX =
        (forwardX * _manualPitch + rightX * _manualRoll) * profile.accelerationMs2;
    final inputAccelY =
        (forwardY * _manualPitch + rightY * _manualRoll) * profile.accelerationMs2;

    _velocityX += inputAccelX * dt;
    _velocityY += inputAccelY * dt;

    // Aerodynamic drag
    if (_manualPitch.abs() < 0.05 && _manualRoll.abs() < 0.05) {
      _velocityX *= 0.92;
      _velocityY *= 0.92;
      if (_velocityX.abs() < 0.05) _velocityX = 0.0;
      if (_velocityY.abs() < 0.05) _velocityY = 0.0;
    }

    // Clamp horizontal speed to profile max
    final maxSpeedMs = profile.maxSpeedKmh / 3.6;
    final currentSpeed = sqrt(_velocityX * _velocityX + _velocityY * _velocityY);
    if (currentSpeed > maxSpeedMs) {
      final scale = maxSpeedMs / currentSpeed;
      _velocityX *= scale;
      _velocityY *= scale;
    }

    _state = _state.copyWith(heading: newHeading);
  }

  void _processAutoMission(
      double dt, DroneProfile profile, double windForceX, double windForceY) {
    if (_waypoints.isEmpty || _currentWaypointIndex >= _waypoints.length) {
      _state = _state.copyWith(flightMode: FlightMode.hover);
      return;
    }

    final target = _waypoints[_currentWaypointIndex];
    final distance = GeoMath.distanceMeters(_state.position, target.position);
    final targetBearing = GeoMath.bearing(_state.position, target.position);

    // Smooth heading rotation toward waypoint
    double headingDiff = targetBearing - _state.heading;
    if (headingDiff > 180) headingDiff -= 360;
    if (headingDiff < -180) headingDiff += 360;
    const rotationRate = 90.0; // degrees per second
    final maxRotation = rotationRate * dt;
    final rotation = headingDiff.clamp(-maxRotation, maxRotation);
    double newHeading = (_state.heading + rotation + 360.0) % 360.0;

    // Altitude adjustment
    final altDiff = target.targetAltitude - _state.altitude;
    if (altDiff.abs() > 0.5) {
      _verticalVelocity = altDiff > 0
          ? profile.maxAscentMs.clamp(0.0, altDiff.abs())
          : -profile.maxDescentMs.clamp(0.0, altDiff.abs());
    } else {
      _verticalVelocity *= 0.9;
    }

    if (distance > 3.0) {
      // Navigate toward waypoint
      _hoverTimer = 0.0;
      final headingRad = newHeading * pi / 180.0;
      final cruiseSpeed = (profile.maxSpeedKmh * 0.6) / 3.6; // 60% max speed
      final targetSpeed = (distance > 20)
          ? cruiseSpeed
          : cruiseSpeed * (distance / 20.0).clamp(0.3, 1.0);

      final currentSpeed = sqrt(_velocityX * _velocityX + _velocityY * _velocityY);
      if (currentSpeed < targetSpeed) {
        _velocityX += sin(headingRad) * profile.accelerationMs2 * dt;
        _velocityY += cos(headingRad) * profile.accelerationMs2 * dt;
      }

      // Clamp speed
      final speed = sqrt(_velocityX * _velocityX + _velocityY * _velocityY);
      if (speed > targetSpeed) {
        final scale = targetSpeed / speed;
        _velocityX *= scale;
        _velocityY *= scale;
      }
    } else {
      // Near waypoint - decelerate and hover
      _velocityX *= 0.85;
      _velocityY *= 0.85;
      _hoverTimer += dt;

      if (_hoverTimer >= target.hoverSeconds) {
        _currentWaypointIndex++;
        _hoverTimer = 0.0;
        if (_currentWaypointIndex >= _waypoints.length) {
          _state = _state.copyWith(flightMode: FlightMode.hover);
        }
      }
    }

    _state = _state.copyWith(heading: newHeading);
  }

  void _processRTL(
      double dt, DroneProfile profile, double windForceX, double windForceY) {
    // Phase 1: Climb to 30m safety altitude
    if (_state.altitude < 30.0) {
      _verticalVelocity = profile.maxAscentMs * 0.8;
      _velocityX *= 0.95;
      _velocityY *= 0.95;
      return;
    }

    // Phase 2: Navigate to home
    final distance = GeoMath.distanceMeters(_state.position, _state.homePosition);
    final targetBearing = GeoMath.bearing(_state.position, _state.homePosition);

    // Smooth heading rotation
    double headingDiff = targetBearing - _state.heading;
    if (headingDiff > 180) headingDiff -= 360;
    if (headingDiff < -180) headingDiff += 360;
    final maxRotation = 90.0 * dt;
    final rotation = headingDiff.clamp(-maxRotation, maxRotation);
    double newHeading = (_state.heading + rotation + 360.0) % 360.0;

    _verticalVelocity *= 0.95; // maintain altitude

    if (distance > 3.0) {
      final headingRad = newHeading * pi / 180.0;
      final rtlSpeed = (profile.maxSpeedKmh * 0.5) / 3.6;
      _velocityX += sin(headingRad) * profile.accelerationMs2 * dt;
      _velocityY += cos(headingRad) * profile.accelerationMs2 * dt;

      final speed = sqrt(_velocityX * _velocityX + _velocityY * _velocityY);
      if (speed > rtlSpeed) {
        final scale = rtlSpeed / speed;
        _velocityX *= scale;
        _velocityY *= scale;
      }
    } else {
      // Arrived home - begin landing
      _velocityX *= 0.8;
      _velocityY *= 0.8;
      _state = _state.copyWith(flightMode: FlightMode.landing);
    }

    _state = _state.copyWith(heading: newHeading);
  }

  void _processLanding(double dt, double windForceX, double windForceY) {
    _verticalVelocity = -1.5; // descend at 1.5 m/s
    _velocityX *= 0.95;
    _velocityY *= 0.95;
  }

  // ── Public API ──

  void selectMap(FlightMap newMap) {
    _activeMap = newMap;
    if (_state.flightMode == FlightMode.disarmed) {
      _state = _state.copyWith(
        activeMap: newMap,
        position: newMap.homePosition,
        homePosition: newMap.homePosition,
        altitude: 0.0,
      );
    } else {
      _state = _state.copyWith(activeMap: newMap);
    }
    onStateChanged?.call(_state);
  }

  void setManualInput(double throttle, double yaw, double pitch, double roll) {
    _manualThrottle = throttle.clamp(-1.0, 1.0);
    _manualYaw = yaw.clamp(-1.0, 1.0);
    _manualPitch = pitch.clamp(-1.0, 1.0);
    _manualRoll = roll.clamp(-1.0, 1.0);
  }

  void takeoff() {
    if (_state.flightMode == FlightMode.disarmed) {
      _state = _state.copyWith(
        flightMode: FlightMode.hover,
        altitude: 2.0,
        homePosition: _state.position,
      );
      _verticalVelocity = 0.0;
      _velocityX = 0.0;
      _velocityY = 0.0;
    }
  }

  void land() {
    if (_state.flightMode != FlightMode.disarmed) {
      _state = _state.copyWith(flightMode: FlightMode.landing);
    }
  }

  void startMission(List<Waypoint> waypoints) {
    if (waypoints.isEmpty) return;
    if (_state.flightMode == FlightMode.disarmed) {
      takeoff();
    }
    _waypoints = List.from(waypoints);
    _currentWaypointIndex = 0;
    _hoverTimer = 0.0;
    _state = _state.copyWith(flightMode: FlightMode.autoMission);
  }

  void triggerRTL() {
    if (_state.flightMode != FlightMode.disarmed) {
      _state = _state.copyWith(flightMode: FlightMode.rtl);
    }
  }

  void setWindSpeed(double kmh) {
    final direction = _random.nextDouble() * 360.0;
    _state = _state.copyWith(
      windSpeedKmh: kmh.clamp(0.0, 50.0),
      windDirectionDeg: direction,
    );
  }

  void toggleGps() {
    _state = _state.copyWith(gpsLocked: !_state.gpsLocked);
  }

  void selectProfile(DroneProfile profile) {
    _state = _state.copyWith(activeProfile: profile);
  }

  void resetBattery() {
    _state = _state.copyWith(batteryPercent: 100.0, voltage: 12.6);
  }

  void overrideToManual() {
    if (_state.flightMode == FlightMode.autoMission) {
      _state = _state.copyWith(flightMode: FlightMode.manual);
    }
  }
}
