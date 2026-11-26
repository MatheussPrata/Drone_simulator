import 'package:flutter/material.dart';
import 'package:drone_simulator/main.dart';
import 'package:drone_simulator/models/drone_profile.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/services/records_repository.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/game_hud_overlay.dart';

/// Página inicial em paisagem para selecionar Modo de Jogo, Mapa, Drone e Iluminação.
class HomeMenuScreen extends StatefulWidget {
  final RecordsRepository? recordsRepository;

  const HomeMenuScreen({super.key, this.recordsRepository});

  @override
  State<HomeMenuScreen> createState() => _HomeMenuScreenState();
}

class _HomeMenuScreenState extends State<HomeMenuScreen> {
  late final RecordsRepository _records;

  SimulatorMode _selectedMode = SimulatorMode.gateRace;
  FlightMap _selectedMap = FlightMap.dronePark;
  DroneProfile _selectedProfile = DroneProfile.fpvRacer;
  FlightControlMode _selectedFlightMode = FlightControlMode.stabilized;
  TimeOfDayPreset _selectedTimeOfDay = TimeOfDayPreset.day;
  CourseDifficulty _selectedDifficulty = CourseDifficulty.medium;
  CourseDirection _selectedDirection = CourseDirection.standard;
  String? _selectedMissionId;
  AcroSettings _acroSettings = const AcroSettings();
  DroneTuning _droneTuning = const DroneTuning();
  bool _audioEnabled = true;
  bool _hapticsEnabled = true;
  bool _ghostEnabled = true;

  @override
  void initState() {
    super.initState();
    _records = widget.recordsRepository ?? RecordsRepository();
    if (_records.hasSavedAcroSettings) {
      _acroSettings = _records.acroSettings;
    }
    if (_records.hasSavedDroneTuning) {
      _droneTuning = _records.droneTuning;
    }
    _selectedMissionId = AerialMission.forMap(_selectedMap).first.id;
    _records.loadAll().then((_) {
      if (mounted) {
        setState(() {
          if (_records.hasSavedAcroSettings) {
            _acroSettings = _records.acroSettings;
          }
          if (_records.hasSavedDroneTuning) {
            _droneTuning = _records.droneTuning;
          }
        });
      }
    });
  }

  void _selectMode(SimulatorMode mode) {
    setState(() {
      _selectedMode = mode;
      if (mode == SimulatorMode.freestyle) {
        _selectedFlightMode = FlightControlMode.acro;
        if (!_records.hasSavedAcroSettings) {
          _acroSettings = AcroSettings.forPreset(
            AcroRatePreset.freestyle,
            fpvUptiltDeg: _acroSettings.fpvUptiltDeg,
            coordinatedTurn: _acroSettings.coordinatedTurn,
            floatingJoysticks: _acroSettings.floatingJoysticks,
            manualAcroThrottle: _acroSettings.manualAcroThrottle,
          );
        }
      } else if (mode == SimulatorMode.missions) {
        final missions = AerialMission.forMap(_selectedMap);
        if (_selectedMissionId == null ||
            !missions.any((m) => m.id == _selectedMissionId)) {
          _selectedMissionId = missions.first.id;
        }
      }
    });
  }

  Future<void> _startFlight() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FlightSimulatorScreen(
          initialMode: _selectedMode,
          initialMap: _selectedMap,
          initialProfile: _selectedProfile,
          initialFlightMode: _selectedFlightMode,
          initialTimeOfDay: _selectedTimeOfDay,
          initialAcroSettings: _acroSettings,
          initialCourseDifficulty: _selectedDifficulty,
          initialCourseDirection: _selectedDirection,
          initialMissionId: _selectedMissionId,
          initialDroneTuning: _droneTuning,
          initialAudioEnabled: _audioEnabled,
          initialHapticsEnabled: _hapticsEnabled,
          initialGhostEnabled: _ghostEnabled,
          recordsRepository: _records,
        ),
      ),
    );
    await _records.loadAll();
    if (mounted) {
      setState(() {
        if (_records.hasSavedAcroSettings) {
          _acroSettings = _records.acroSettings;
        }
        if (_records.hasSavedDroneTuning) {
          _droneTuning = _records.droneTuning;
        }
      });
    }
  }

  void _openGarageSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          void applyTuning(DroneTuning updated) {
            setState(() => _droneTuning = updated);
            setSheetState(() {});
            _records.saveDroneTuning(updated);
          }

          return SafeArea(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height - 28,
              ),
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF141B24).withOpacity(0.97),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.cyanAccent.withOpacity(0.6)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Garagem & Tuning do Drone',
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        key: const Key('garage_sheet_close_button'),
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cor dos LEDs e Faixa',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 11.5),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (var i = 0;
                                  i < DroneTuning.ledPalette.length;
                                  i++)
                                GestureDetector(
                                  key: Key('garage_led_$i'),
                                  onTap: () => applyTuning(
                                    _droneTuning.copyWith(
                                      ledColorHex: DroneTuning.ledPalette[i],
                                    ),
                                  ),
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(
                                        int.parse(
                                          'FF${DroneTuning.ledPalette[i].substring(1)}',
                                          radix: 16,
                                        ),
                                      ),
                                      border: Border.all(
                                        color: _droneTuning.ledColorHex ==
                                                DroneTuning.ledPalette[i]
                                            ? Colors.white
                                            : Colors.white24,
                                        width: _droneTuning.ledColorHex ==
                                                DroneTuning.ledPalette[i]
                                            ? 2.4
                                            : 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Cor dos Braços',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 11.5),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (var i = 0;
                                  i < DroneTuning.armPalette.length;
                                  i++)
                                GestureDetector(
                                  key: Key('garage_arm_$i'),
                                  onTap: () => applyTuning(
                                    _droneTuning.copyWith(
                                      armColorHex: DroneTuning.armPalette[i],
                                    ),
                                  ),
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(
                                        int.parse(
                                          'FF${DroneTuning.armPalette[i].substring(1)}',
                                          radix: 16,
                                        ),
                                      ),
                                      border: Border.all(
                                        color: _droneTuning.armColorHex ==
                                                DroneTuning.armPalette[i]
                                            ? Colors.cyanAccent
                                            : Colors.white24,
                                        width: _droneTuning.armColorHex ==
                                                DroneTuning.armPalette[i]
                                            ? 2.4
                                            : 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _sliderRow(
                            sliderKey: const Key('garage_fov_slider'),
                            label: 'FOV Câmera',
                            valueText: '${_droneTuning.cameraFovDeg.round()}°',
                            value: _droneTuning.cameraFovDeg,
                            min: 55.0,
                            max: 105.0,
                            onChanged: (v) => applyTuning(
                              _droneTuning.copyWith(cameraFovDeg: v),
                            ),
                          ),
                          Wrap(
                            spacing: 6,
                            children: [
                              _presetChip(
                                label: 'Cine 64°',
                                selected:
                                    (_droneTuning.cameraFovDeg - 64.0).abs() < 2.0,
                                onTap: () => applyTuning(
                                  _droneTuning.copyWith(cameraFovDeg: 64.0),
                                ),
                              ),
                              _presetChip(
                                label: 'FPV 82°',
                                selected:
                                    (_droneTuning.cameraFovDeg - 82.0).abs() < 2.0,
                                onTap: () => applyTuning(
                                  _droneTuning.copyWith(cameraFovDeg: 82.0),
                                ),
                              ),
                              _presetChip(
                                label: 'Wide 98°',
                                selected:
                                    (_droneTuning.cameraFovDeg - 98.0).abs() < 2.0,
                                onTap: () => applyTuning(
                                  _droneTuning.copyWith(cameraFovDeg: 98.0),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          _sliderRow(
                            sliderKey: const Key('garage_weight_slider'),
                            label: 'Peso Frame',
                            valueText:
                                '${(_droneTuning.weightMultiplier * 100).round()}%',
                            value: _droneTuning.weightMultiplier,
                            min: 0.80,
                            max: 1.30,
                            onChanged: (v) => applyTuning(
                              _droneTuning.copyWith(weightMultiplier: v),
                            ),
                          ),
                          _sliderRow(
                            sliderKey: const Key('garage_battery_slider'),
                            label: 'Bateria',
                            valueText:
                                '${(_droneTuning.batteryCapacityMultiplier * 100).round()}%',
                            value: _droneTuning.batteryCapacityMultiplier,
                            min: 0.75,
                            max: 1.50,
                            onChanged: (v) => applyTuning(
                              _droneTuning.copyWith(
                                batteryCapacityMultiplier: v,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              key: const Key('btn_garage_reset'),
                              onPressed: () => applyTuning(const DroneTuning()),
                              icon: const Icon(Icons.restore, size: 15),
                              label: const Text('Restaurar Padrão'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openAcroSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          void applyAcro(AcroSettings updated) {
            setState(() => _acroSettings = updated);
            setSheetState(() {});
            _records.saveAcroSettings(updated);
          }

          return SafeArea(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height - 28,
              ),
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF141B24).withOpacity(0.97),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amberAccent.withOpacity(0.6)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Calibração do Modo ACRO / FPV',
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        key: const Key('acro_sheet_close_button'),
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            children: [
                              _presetChip(
                                key: const Key('acro_preset_smooth'),
                                label: 'Suave (135°/s)',
                                selected:
                                    _acroSettings.preset == AcroRatePreset.smooth,
                                onTap: () => applyAcro(
                                  AcroSettings.forPreset(
                                    AcroRatePreset.smooth,
                                    fpvUptiltDeg: _acroSettings.fpvUptiltDeg,
                                    coordinatedTurn:
                                        _acroSettings.coordinatedTurn,
                                    floatingJoysticks:
                                        _acroSettings.floatingJoysticks,
                                    manualAcroThrottle:
                                        _acroSettings.manualAcroThrottle,
                                  ),
                                ),
                              ),
                              _presetChip(
                                key: const Key('acro_preset_standard'),
                                label: 'Padrão (175°/s)',
                                selected: _acroSettings.preset ==
                                    AcroRatePreset.standard,
                                onTap: () => applyAcro(
                                  AcroSettings.forPreset(
                                    AcroRatePreset.standard,
                                    fpvUptiltDeg: _acroSettings.fpvUptiltDeg,
                                    coordinatedTurn:
                                        _acroSettings.coordinatedTurn,
                                    floatingJoysticks:
                                        _acroSettings.floatingJoysticks,
                                    manualAcroThrottle:
                                        _acroSettings.manualAcroThrottle,
                                  ),
                                ),
                              ),
                              _presetChip(
                                key: const Key('acro_preset_freestyle'),
                                label: 'Freestyle (310°/s)',
                                selected: _acroSettings.preset ==
                                    AcroRatePreset.freestyle,
                                onTap: () => applyAcro(
                                  AcroSettings.forPreset(
                                    AcroRatePreset.freestyle,
                                    fpvUptiltDeg: _acroSettings.fpvUptiltDeg,
                                    coordinatedTurn:
                                        _acroSettings.coordinatedTurn,
                                    floatingJoysticks:
                                        _acroSettings.floatingJoysticks,
                                    manualAcroThrottle:
                                        _acroSettings.manualAcroThrottle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _sliderRow(
                            sliderKey: const Key('acro_expo_slider'),
                            label: 'Expo do Stick',
                            valueText: '${(_acroSettings.expo * 100).round()}%',
                            value: _acroSettings.expo,
                            min: 0.0,
                            max: 0.85,
                            onChanged: (v) =>
                                applyAcro(_acroSettings.copyWith(expo: v)),
                          ),
                          _sliderRow(
                            sliderKey: const Key('acro_uptilt_slider'),
                            label: 'Uptilt Câmera FPV',
                            valueText: '${_acroSettings.fpvUptiltDeg.round()}°',
                            value: _acroSettings.fpvUptiltDeg,
                            min: 0.0,
                            max: 30.0,
                            onChanged: (v) => applyAcro(
                                _acroSettings.copyWith(fpvUptiltDeg: v)),
                          ),
                          SwitchListTile(
                            key: const Key('acro_horizon_switch'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Assistência de Horizonte (estabiliza ao soltar o stick)',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            value: _acroSettings.horizonAssist > 0.05,
                            activeColor: Colors.amberAccent,
                            onChanged: (enabled) => applyAcro(
                              _acroSettings.copyWith(
                                horizonAssist: enabled ? 0.48 : 0.0,
                              ),
                            ),
                          ),
                          SwitchListTile(
                            key: const Key('acro_coordinated_switch'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Curva Coordenada (Auto-Yaw em curvas)',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            value: _acroSettings.coordinatedTurn,
                            activeColor: Colors.amberAccent,
                            onChanged: (enabled) => applyAcro(
                              _acroSettings.copyWith(coordinatedTurn: enabled),
                            ),
                          ),
                          SwitchListTile(
                            key: const Key('acro_floating_sticks_switch'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Joystick Flutuante (toque livre nas laterais)',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            value: _acroSettings.floatingJoysticks,
                            activeColor: Colors.amberAccent,
                            onChanged: (enabled) => applyAcro(
                              _acroSettings.copyWith(
                                floatingJoysticks: enabled,
                              ),
                            ),
                          ),
                          SwitchListTile(
                            key: const Key('acro_manual_throttle_switch'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Throttle Livre no Acro (sem auto-centro)',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            value: _acroSettings.manualAcroThrottle,
                            activeColor: Colors.amberAccent,
                            onChanged: (enabled) => applyAcro(
                              _acroSettings.copyWith(
                                manualAcroThrottle: enabled,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _presetChip({
    Key? key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      key: key,
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      selectedColor: Colors.amberAccent.withOpacity(0.28),
      onSelected: (_) => onTap(),
    );
  }

  Widget _sliderRow({
    Key? sliderKey,
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            '$label: $valueText',
            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
          ),
        ),
        Expanded(
          child: Slider(
            key: sliderKey,
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: Colors.amberAccent,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C1219),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0C1219),
              Color(0xFF132234),
              Color(0xFF0A1017),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 10),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 42, child: _buildModesColumn()),
                      const SizedBox(width: 12),
                      Expanded(flex: 58, child: _buildSetupColumn()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.cyanAccent.withOpacity(0.6)),
                  ),
                  child: const Icon(Icons.flight_takeoff,
                      color: Colors.cyanAccent, size: 20),
                ),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'DRONE SIMULATOR 3D',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      'Escolha o modo de jogo, cenário e setup de voo',
                      style: TextStyle(color: Colors.white60, fontSize: 10.5),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTimeOfDayChips(),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('btn_home_audio'),
                  tooltip: _audioEnabled ? 'Áudio ligado' : 'Áudio desligado',
                  onPressed: () => setState(() {
                    _audioEnabled = !_audioEnabled;
                    _hapticsEnabled = _audioEnabled;
                  }),
                  icon: Icon(
                    _audioEnabled ? Icons.volume_up : Icons.volume_off,
                    color: _audioEnabled ? Colors.cyanAccent : Colors.white38,
                    size: 20,
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('btn_home_garage'),
                  onPressed: _openGarageSheet,
                  icon: const Icon(Icons.build_circle_outlined,
                      size: 15, color: Colors.cyanAccent),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.cyanAccent.withOpacity(0.55)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  label: const Text(
                    'Garagem',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  key: const Key('btn_home_acro_config'),
                  onPressed: _openAcroSheet,
                  icon: const Icon(Icons.tune, size: 15, color: Colors.amberAccent),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.amberAccent.withOpacity(0.55)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  label: const Text(
                    'Acro',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeOfDayChips() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _lightPill(TimeOfDayPreset.day, Icons.wb_sunny, 'Dia'),
          _lightPill(TimeOfDayPreset.sunset, Icons.wb_twilight, 'Tarde'),
          _lightPill(TimeOfDayPreset.night, Icons.nights_stay, 'Noite'),
        ],
      ),
    );
  }

  Widget _lightPill(TimeOfDayPreset preset, IconData icon, String label) {
    final selected = _selectedTimeOfDay == preset;
    return GestureDetector(
      key: Key('home_light_${preset.name}'),
      onTap: () => setState(() => _selectedTimeOfDay = preset),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.cyanAccent.withOpacity(0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13, color: selected ? Colors.cyanAccent : Colors.white54),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.cyanAccent : Colors.white60,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModesColumn() {
    final modes = [
      (
        mode: SimulatorMode.freeFlight,
        title: 'Voo Livre',
        subtitle: 'Exploração livre, pouso em prédios, RTH e treino sem relógio.',
        icon: Icons.flight,
        color: Colors.cyanAccent,
      ),
      (
        mode: SimulatorMode.gateRace,
        title: 'Corrida de Portais',
        subtitle: '10 portais cronometrados, Ghost do recorde e medalhas.',
        icon: Icons.flag,
        color: Colors.lightGreenAccent,
      ),
      (
        mode: SimulatorMode.timeAttack,
        title: 'Time Attack',
        subtitle: 'Contra o relógio infinito: cada portal adiciona segundos extras.',
        icon: Icons.timer,
        color: Colors.orangeAccent,
      ),
      (
        mode: SimulatorMode.freestyle,
        title: 'Freestyle Acro',
        subtitle: '90s para Power Loops, Split-S, Gaps, Under Bridge e Flips.',
        icon: Icons.cyclone,
        color: Colors.purpleAccent,
      ),
      (
        mode: SimulatorMode.missions,
        title: 'Missões & Trabalho',
        subtitle: 'Rotas autônomas, inspeção, pouso em telhado e patrulha NFZ.',
        icon: Icons.assignment_turned_in,
        color: Colors.tealAccent,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MODO DE JOGO',
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              itemCount: modes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 5),
              itemBuilder: (context, index) {
                final item = modes[index];
                final selected = _selectedMode == item.mode;
                return InkWell(
                  key: Key('mode_${item.mode.name}'),
                  onTap: () => _selectMode(item.mode),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: selected
                          ? item.color.withOpacity(0.16)
                          : Colors.black.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? item.color : Colors.white12,
                        width: selected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(item.icon,
                            color: selected ? item.color : Colors.white54,
                            size: 18),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.title,
                                style: TextStyle(
                                  color: selected ? item.color : Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 9.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (selected)
                          Icon(Icons.check_circle, color: item.color, size: 16),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupColumn() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CENÁRIO & RECORDES',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: FlightMap.availableMaps.map((map) {
                      final selected = _selectedMap.id == map.id;
                      final rec = _records.recordFor(map.id);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _buildMapCard(map, rec, selected),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'DRONE & MODO DE CONTROLE',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: DroneProfile.all.map((p) {
                      final selected = _selectedProfile.type == p.type;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _buildProfileChip(p, selected),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildControlModeChip(
                          FlightControlMode.stabilized, 'NORMAL', 'Auto-nível'),
                      const SizedBox(width: 6),
                      _buildControlModeChip(
                          FlightControlMode.sport, 'SPORT', 'Rápido 45°'),
                      const SizedBox(width: 6),
                      _buildControlModeChip(
                          FlightControlMode.acro, 'ACRO', 'FPV Livre'),
                      const SizedBox(width: 8),
                      if (_selectedMode == SimulatorMode.gateRace)
                        FilterChip(
                          label: const Text('Ghost',
                              style: TextStyle(fontSize: 10.5)),
                          selected: _ghostEnabled,
                          selectedColor: Colors.cyanAccent.withOpacity(0.22),
                          onSelected: (v) => setState(() => _ghostEnabled = v),
                        ),
                    ],
                  ),
                  if (_selectedMode == SimulatorMode.gateRace ||
                      _selectedMode == SimulatorMode.timeAttack) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _variantChip(
                          key: const Key('course_dir_standard'),
                          label: 'Padrão',
                          selected:
                              _selectedDirection == CourseDirection.standard,
                          color: Colors.cyanAccent,
                          onTap: () => setState(() =>
                              _selectedDirection = CourseDirection.standard),
                        ),
                        _variantChip(
                          key: const Key('course_dir_reverse'),
                          label: 'Reversa',
                          selected:
                              _selectedDirection == CourseDirection.reverse,
                          color: Colors.cyanAccent,
                          onTap: () => setState(() =>
                              _selectedDirection = CourseDirection.reverse),
                        ),
                        _variantChip(
                          key: const Key('course_diff_easy'),
                          label: 'Fácil',
                          selected:
                              _selectedDifficulty == CourseDifficulty.easy,
                          color: Colors.greenAccent,
                          onTap: () => setState(() =>
                              _selectedDifficulty = CourseDifficulty.easy),
                        ),
                        _variantChip(
                          key: const Key('course_diff_medium'),
                          label: 'Médio',
                          selected:
                              _selectedDifficulty == CourseDifficulty.medium,
                          color: Colors.amberAccent,
                          onTap: () => setState(() =>
                              _selectedDifficulty = CourseDifficulty.medium),
                        ),
                        _variantChip(
                          key: const Key('course_diff_pro'),
                          label: 'Pro',
                          selected:
                              _selectedDifficulty == CourseDifficulty.pro,
                          color: Colors.redAccent,
                          onTap: () => setState(
                              () => _selectedDifficulty = CourseDifficulty.pro),
                        ),
                      ],
                    ),
                  ],
                  if (_selectedMode == SimulatorMode.missions) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children:
                          AerialMission.forMap(_selectedMap).map((mission) {
                        final selected = _selectedMissionId == mission.id;
                        final done = _records
                            .recordFor(_selectedMap.id)
                            .completedMissions
                            .contains(mission.id);
                        return ChoiceChip(
                          key: Key('home_mission_${mission.id}'),
                          avatar: done
                              ? const Icon(Icons.check_circle,
                                  size: 14, color: Colors.greenAccent)
                              : null,
                          label: Text(mission.name,
                              style: const TextStyle(fontSize: 10)),
                          selected: selected,
                          selectedColor: Colors.tealAccent.withOpacity(0.24),
                          onSelected: (_) =>
                              setState(() => _selectedMissionId = mission.id),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              key: const Key('btn_start_simulator'),
              onPressed: _startFlight,
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: const Color(0xFF081018),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              label: Text(
                'INICIAR VOO · ${_selectedMap.name.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _variantChip({
    required Key key,
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      key: key,
      label: Text(label, style: const TextStyle(fontSize: 10)),
      selected: selected,
      selectedColor: color.withOpacity(0.24),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (_) => onTap(),
    );
  }

  Widget _buildMapCard(FlightMap map, MapRecord rec, bool selected) {
    String recordText;
    MedalTier medal = MedalTier.none;
    switch (_selectedMode) {
      case SimulatorMode.gateRace:
        final profileBest = rec.bestTimeForProfile(_selectedProfile.type.name);
        medal = rec.medalForProfile(_selectedProfile.type.name);
        recordText = profileBest != null
            ? 'Melhor: ${GameHudOverlay.formatTime(profileBest)}'
            : 'Sem recorde';
        break;
      case SimulatorMode.timeAttack:
        recordText = rec.bestTimeAttackGates > 0
            ? 'Portais: ${rec.bestTimeAttackGates}'
            : 'Sem recorde';
        break;
      case SimulatorMode.freestyle:
        if (rec.freestyleChallengeCompleted) {
          medal = MedalTier.gold;
        }
        recordText = rec.bestFreestyleScore > 0
            ? '${rec.bestFreestyleScore.round()} pts'
            : 'Sem recorde';
        break;
      case SimulatorMode.missions:
        final totalMissions = AerialMission.forMap(map).length;
        recordText = '${rec.completedMissions.length}/$totalMissions missões';
        break;
      case SimulatorMode.freeFlight:
        recordText = 'Raio ${map.radiusMeters.round()}m';
        break;
    }

    return InkWell(
      key: Key('home_map_${map.id}'),
      onTap: () => setState(() {
        _selectedMap = map;
        final missions = AerialMission.forMap(map);
        if (_selectedMissionId == null ||
            !missions.any((m) => m.id == _selectedMissionId)) {
          _selectedMissionId = missions.first.id;
        }
      }),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.cyanAccent.withOpacity(0.16)
              : Colors.black.withOpacity(0.30),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.cyanAccent : Colors.white12,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    map.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.cyanAccent : Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _medalBadge(medal),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              recordText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _medalBadge(MedalTier medal) {
    switch (medal) {
      case MedalTier.gold:
        return const Icon(Icons.emoji_events, color: Colors.amberAccent, size: 15);
      case MedalTier.silver:
        return const Icon(Icons.emoji_events, color: Color(0xFFD0D8E0), size: 15);
      case MedalTier.bronze:
        return const Icon(Icons.emoji_events, color: Color(0xFFCD7F32), size: 15);
      case MedalTier.none:
        return const SizedBox.shrink();
    }
  }

  Widget _buildProfileChip(DroneProfile profile, bool selected) {
    return InkWell(
      key: Key('profile_${profile.type.name}'),
      onTap: () => setState(() => _selectedProfile = profile),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.orangeAccent.withOpacity(0.16)
              : Colors.black.withOpacity(0.28),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? Colors.orangeAccent : Colors.white12,
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.orangeAccent : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${profile.maxSpeedKmh.round()} km/h · ${profile.batteryMinutes}m',
              style: const TextStyle(color: Colors.white54, fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlModeChip(
      FlightControlMode mode, String title, String sub) {
    final selected = _selectedFlightMode == mode;
    return Expanded(
      child: InkWell(
        key: Key('ctrl_${mode.name}'),
        onTap: () => setState(() => _selectedFlightMode = mode),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? Colors.amberAccent.withOpacity(0.18)
                : Colors.black.withOpacity(0.26),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Colors.amberAccent : Colors.white12,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: selected ? Colors.amberAccent : Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                sub,
                style: const TextStyle(color: Colors.white54, fontSize: 8.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
