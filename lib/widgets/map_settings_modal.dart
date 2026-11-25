import 'package:flutter/material.dart';
import 'package:drone_simulator/models/drone_profile.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';

/// Modal para configuração de camadas de mapa (Satélite / Ruas)
/// e seleção de locais pré-definidos de decolagem (Home 0,0).
class MapSettingsModal extends StatelessWidget {
  final SimulatorController controller;

  const MapSettingsModal({
    super.key,
    required this.controller,
  });

  /// Exibe o modal como BottomSheet estilizado com tema DJI escuro
  static Future<void> show(BuildContext context, SimulatorController controller) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => MapSettingsModal(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isSat = controller.isSatellite;
        final currentMapId = controller.activeMap.id;

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF141A22).withOpacity(0.96),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.65),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.75),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Cabeçalho com Título e Botão Fechar ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.layers, color: Colors.cyanAccent, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Camadas e Locais de Voo',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        key: const Key('modal_close_button'),
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Seção 1: Camada de Mapa (Satélite vs Ruas) ──
                  const Text(
                    'TIPO DE MAPA (TILES)',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTileOption(
                          key: const Key('btn_layer_satellite'),
                          title: 'Satélite',
                          subtitle: 'ArcGIS Imagery',
                          icon: Icons.satellite_alt,
                          isSelected: isSat,
                          onTap: () => controller.setSatellite(true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildTileOption(
                          key: const Key('btn_layer_streets'),
                          title: 'Ruas',
                          subtitle: 'OpenStreetMap',
                          icon: Icons.map,
                          isSelected: !isSat,
                          onTap: () => controller.setSatellite(false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // ── Seção 2: Locais Pré-definidos de Decolagem ──
                  const Text(
                    'LOCAIS DE DECOLAGEM (REDEFINE HOME 0,0)',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...FlightMap.predefinedTakeoffLocations.map((loc) {
                    final isSelected = currentMapId == loc.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildLocationTile(
                        context: context,
                        location: loc,
                        isSelected: isSelected,
                        onTap: () {
                          controller.selectTakeoffLocation(loc);
                        },
                      ),
                    );
                  }),
                  const SizedBox(height: 14),

                  // ── Seção 3: Modo de Jogo & Perfil de Drone ──
                  const Text(
                    'MODO DE JOGO & DRONE',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _modeChip('Voo Livre', SimulatorMode.freeFlight),
                      _modeChip('Corrida 10 Portais', SimulatorMode.gateRace),
                      _modeChip('Time Attack', SimulatorMode.timeAttack),
                      _modeChip('Freestyle Acro', SimulatorMode.freestyle),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: DroneProfile.all.map((p) {
                      final selected = controller.activeProfile.type == p.type;
                      return ChoiceChip(
                        label: Text(p.name, style: const TextStyle(fontSize: 11)),
                        selected: selected,
                        selectedColor: Colors.orangeAccent.withOpacity(0.28),
                        onSelected: (_) => controller.selectDroneProfile(p),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // ── Seção 4: Iluminação & Vento ──
                  const Text(
                    'ILUMINAÇÃO & VENTO',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _lightChip('Dia', TimeOfDayPreset.day),
                      _lightChip('Pôr do Sol', TimeOfDayPreset.sunset),
                      _lightChip('Noite', TimeOfDayPreset.night),
                      _windChip('Sem Vento', 0.0),
                      _windChip('Vento Padrão', 1.0),
                      _windChip('Rajadas Fortes', 1.8),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Seção 5: Calibração do Modo Acro / FPV & Áudio ──
                  const Text(
                    'AJUSTES ACRO / FPV & FEEDBACK',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      _acroChip('Suave', AcroRatePreset.smooth),
                      _acroChip('Padrão', AcroRatePreset.standard),
                      _acroChip('Freestyle', AcroRatePreset.freestyle),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          'Expo: ${(controller.acroSettings.expo * 100).round()}%',
                          style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: controller.acroSettings.expo.clamp(0.0, 0.85),
                          min: 0.0,
                          max: 0.85,
                          activeColor: Colors.amberAccent,
                          onChanged: (v) => controller.setAcroSettings(
                            controller.acroSettings.copyWith(expo: v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          'Uptilt FPV: ${controller.acroSettings.fpvUptiltDeg.round()}°',
                          style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: controller.acroSettings.fpvUptiltDeg.clamp(0.0, 30.0),
                          min: 0.0,
                          max: 30.0,
                          activeColor: Colors.amberAccent,
                          onChanged: (v) => controller.setAcroSettings(
                            controller.acroSettings.copyWith(fpvUptiltDeg: v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Assistência de Horizonte no Acro',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    value: controller.acroSettings.horizonAssist > 0.05,
                    activeColor: Colors.amberAccent,
                    onChanged: (v) => controller.setAcroSettings(
                      controller.acroSettings.copyWith(
                        horizonAssist: v ? 0.25 : 0.0,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Ghost do Recorde na Corrida',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    value: controller.ghostEnabled,
                    activeColor: Colors.cyanAccent,
                    onChanged: controller.setGhostEnabled,
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Som dos Motores e Vibração Tátil',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    value: controller.audioEnabled,
                    activeColor: Colors.cyanAccent,
                    onChanged: (v) {
                      controller.setAudioEnabled(v);
                      controller.setHapticsEnabled(v);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _modeChip(String label, SimulatorMode mode) {
    final selected = controller.simulatorMode == mode;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      selectedColor: Colors.lightGreenAccent.withOpacity(0.25),
      onSelected: (_) => controller.setSimulatorMode(mode),
    );
  }

  Widget _lightChip(String label, TimeOfDayPreset preset) {
    final selected = controller.timeOfDay == preset;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      selectedColor: Colors.cyanAccent.withOpacity(0.25),
      onSelected: (_) => controller.setTimeOfDay(preset),
    );
  }

  Widget _windChip(String label, double mult) {
    final selected = (controller.windMultiplier - mult).abs() < 0.05;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      selectedColor: Colors.lightBlueAccent.withOpacity(0.25),
      onSelected: (_) => controller.setWindMultiplier(mult),
    );
  }

  Widget _acroChip(String label, AcroRatePreset preset) {
    final selected = controller.acroSettings.preset == preset;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      selectedColor: Colors.amberAccent.withOpacity(0.25),
      onSelected: (_) => controller.setAcroPreset(preset),
    );
  }

  Widget _buildTileOption({
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.cyanAccent.withOpacity(0.18)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.15),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? Colors.cyanAccent : Colors.white60,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.cyanAccent : Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.cyanAccent.withOpacity(0.75)
                          : Colors.white38,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                size: 16,
                color: Colors.cyanAccent,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationTile({
    required BuildContext context,
    required FlightMap location,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final keyName = 'loc_${location.id}';
    return GestureDetector(
      key: Key(keyName),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.cyanAccent.withOpacity(0.16)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.12),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_on,
              size: 20,
              color: isSelected ? Colors.cyanAccent : Colors.white60,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    location.name,
                    style: TextStyle(
                      color: isSelected ? Colors.cyanAccent : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    location.description,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.cyanAccent.withOpacity(0.75)
                          : Colors.white38,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'ATIVO',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
