import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drone_simulator/models/drone_state.dart';
import 'package:drone_simulator/models/drone_profile.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/providers/simulation_provider.dart';
import 'package:drone_simulator/core/utils/geo_math.dart';

class TelemetryBar extends ConsumerWidget {
  const TelemetryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final droneState = ref.watch(simulationProvider);
    final notifier = ref.read(simulationProvider.notifier);
    final distFromHome =
        GeoMath.distanceMeters(droneState.position, droneState.homePosition);

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        border: Border(
          bottom: BorderSide(
            color: droneState.inNoFlyZone
                ? Colors.redAccent
                : (droneState.isGeofenceWarning
                    ? Colors.amberAccent
                    : Colors.cyan.withOpacity(0.4)),
            width: 1.5,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildModeBadge(droneState.flightMode),
            _buildGpsStatus(droneState.gpsLocked),
            _buildBattery(droneState.batteryPercent, droneState.voltage),
            _buildInfoItem(
              Icons.height,
              '${droneState.altitude.toStringAsFixed(1)}/${droneState.activeMap.maxAltitudeMeters.toStringAsFixed(0)}m',
              droneState.altitude >= droneState.activeMap.maxAltitudeMeters - 15
                  ? Colors.amberAccent
                  : Colors.white,
            ),
            _buildInfoItem(
              Icons.speed,
              '${droneState.speedKmh.toStringAsFixed(1)} km/h',
              Colors.white,
            ),
            _buildInfoItem(
              Icons.home_outlined,
              '${distFromHome.toStringAsFixed(0)} m',
              Colors.white,
            ),
            _buildGeofenceDistance(
              droneState.distanceFromCenter,
              droneState.activeMap.radiusMeters,
              droneState.isGeofenceWarning,
            ),
            _buildMapSelector(droneState.activeMap, notifier, context),
            _buildProfileSelector(droneState.activeProfile, notifier, context),
            IconButton(
              onPressed: () => notifier.resetBatteryAndDrone(),
              icon: const Icon(Icons.battery_charging_full, color: Colors.greenAccent),
              iconSize: 20,
              tooltip: 'Recarregar Bateria',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeBadge(FlightMode mode) {
    Color color;
    String label;
    switch (mode) {
      case FlightMode.disarmed:
        color = Colors.grey;
        label = 'DISARMED';
        break;
      case FlightMode.hover:
        color = Colors.green;
        label = 'HOVER';
        break;
      case FlightMode.manual:
        color = Colors.blue;
        label = 'MANUAL';
        break;
      case FlightMode.autoMission:
        color = Colors.orange;
        label = 'MISSION';
        break;
      case FlightMode.rtl:
        color = Colors.red;
        label = 'RTL';
        break;
      case FlightMode.landing:
        color = Colors.yellow;
        label = 'LANDING';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildGpsStatus(bool locked) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          locked ? Icons.gps_fixed : Icons.gps_off,
          color: locked ? Colors.greenAccent : Colors.redAccent,
          size: 18,
        ),
        const SizedBox(width: 4),
        Text(
          locked ? 'GPS' : 'ATTI',
          style: TextStyle(
            color: locked ? Colors.greenAccent : Colors.redAccent,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildBattery(double percent, double voltage) {
    Color color;
    IconData icon;
    if (percent > 50) {
      color = Colors.greenAccent;
      icon = Icons.battery_full;
    } else if (percent > 15) {
      color = Colors.yellowAccent;
      icon = Icons.battery_3_bar;
    } else {
      color = Colors.redAccent;
      icon = Icons.battery_alert;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 2),
        Text(
          '${percent.toStringAsFixed(0)}%',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${voltage.toStringAsFixed(1)}V',
          style: TextStyle(color: color.withOpacity(0.7), fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildInfoItem(IconData icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color.withOpacity(0.7), size: 16),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildGeofenceDistance(double currentDist, double maxRadius, bool isWarning) {
    final color = isWarning ? Colors.amberAccent : Colors.white70;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.fence, color: color, size: 15),
        const SizedBox(width: 3),
        Text(
          '${currentDist.toStringAsFixed(0)}/${maxRadius.toStringAsFixed(0)}m',
          style: TextStyle(
            color: color,
            fontWeight: isWarning ? FontWeight.bold : FontWeight.normal,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildMapSelector(
      FlightMap activeMap, SimulationNotifier notifier, BuildContext context) {
    return PopupMenuButton<FlightMap>(
      initialValue: activeMap,
      onSelected: (map) => notifier.selectMap(map),
      tooltip: 'Trocar Cenário / Mapa',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.cyan.withOpacity(0.12),
          border: Border.all(color: Colors.cyanAccent.withOpacity(0.6)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map, color: Colors.cyanAccent, size: 14),
            const SizedBox(width: 4),
            Text(
              activeMap.name.split(' (')[0],
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.cyanAccent, size: 16),
          ],
        ),
      ),
      itemBuilder: (context) => FlightMap.availableMaps
          .map((m) => PopupMenuItem<FlightMap>(
                value: m,
                child: Row(
                  children: [
                    Icon(
                      m.id == activeMap.id ? Icons.check_circle : Icons.circle_outlined,
                      size: 16,
                      color: m.id == activeMap.id ? Colors.cyan : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            m.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Raio ${m.radiusMeters.toStringAsFixed(0)}m • Teto ${m.maxAltitudeMeters.toStringAsFixed(0)}m',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildProfileSelector(
      DroneProfile active, SimulationNotifier notifier, BuildContext context) {
    return PopupMenuButton<DroneProfile>(
      initialValue: active,
      onSelected: (profile) => notifier.selectProfile(profile),
      tooltip: 'Trocar Drone',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.cyan.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.air, color: Colors.cyan, size: 14),
            const SizedBox(width: 4),
            Text(
              active.name,
              style: const TextStyle(color: Colors.cyan, fontSize: 11),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.cyan, size: 16),
          ],
        ),
      ),
      itemBuilder: (context) => DroneProfile.all
          .map((p) => PopupMenuItem<DroneProfile>(
                value: p,
                child: Text(p.name),
              ))
          .toList(),
    );
  }
}
