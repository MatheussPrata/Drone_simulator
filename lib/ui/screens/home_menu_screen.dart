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
  AcroSettings _acroSettings = const AcroSettings();
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
    _records.loadAll().then((_) {
      if (mounted) {
        setState(() {
          if (_records.hasSavedAcroSettings) {
            _acroSettings = _records.acroSettings;
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
          );
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
      });
    }
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
        subtitle: '90s para somar Power Loops, Split-S, Flips 360°, Inverted e Dives.',
        icon: Icons.cyclone,
        color: Colors.purpleAccent,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(10),
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
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: modes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 7),
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
                        horizontal: 10, vertical: 8),
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
                            size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.title,
                                style: TextStyle(
                                  color: selected ? item.color : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                item.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (selected)
                          Icon(Icons.check_circle, color: item.color, size: 17),
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
      padding: const EdgeInsets.all(10),
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
                  const SizedBox(height: 6),
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
                  const SizedBox(height: 10),
                  const Text(
                    'DRONE & MODO DE CONTROLE',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
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
                  const SizedBox(height: 8),
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

  Widget _buildMapCard(FlightMap map, MapRecord rec, bool selected) {
    String recordText;
    switch (_selectedMode) {
      case SimulatorMode.gateRace:
        recordText = rec.bestRaceTimeSec != null
            ? 'Melhor: ${GameHudOverlay.formatTime(rec.bestRaceTimeSec!)}'
            : 'Sem recorde';
        break;
      case SimulatorMode.timeAttack:
        recordText = rec.bestTimeAttackGates > 0
            ? 'Portais: ${rec.bestTimeAttackGates}'
            : 'Sem recorde';
        break;
      case SimulatorMode.freestyle:
        recordText = rec.bestFreestyleScore > 0
            ? '${rec.bestFreestyleScore.round()} pts'
            : 'Sem recorde';
        break;
      case SimulatorMode.freeFlight:
        recordText = 'Raio ${map.radiusMeters.round()}m';
        break;
    }

    return InkWell(
      key: Key('home_map_${map.id}'),
      onTap: () => setState(() => _selectedMap = map),
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
                _medalBadge(rec.medal),
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
