# Drone Simulator

## Estado Atual

### Concluído (Bloco 1)
- **Pouso e decolagem em telhados no motor 6-DoF ([simulator_controller.dart](lib/simulation/simulator_controller.dart)):**
  - Adicionado cálculo dinâmico da superfície caminhável abaixo do drone (`_computeGroundHeightAt` com `WorldObstacle.isWalkableRoof` e `coversPoint`), propagando `groundHeightM` real para `QuadrotorPhysicsEngine.step(...)`.
  - Expostos `currentGroundHeightM` e `altitudeAgl`.
  - Ajustados `armAndTakeoff()`, `land()`, `reset()`, `setPosition()`, `_buildStickInput()`, `_advanceStatusMachine()` e `_resolveWorldCollisions()` para suportar pouso suave, crash vertical e decolagem a partir do topo de prédios/galpões/represa sem ejeção lateral indevida nem perda de posição horizontal, preservando colisões laterais nas paredes.
- **Otimização de rebuilds a 60 FPS em `FlightSimulatorScreen` ([main.dart](lib/main.dart)):**
  - `_FlightSimulatorScreenState._onControllerTick()` agora só dispara `setState` quando `isMapPrimaryView` muda, eliminando rebuilds da tela raiz e dos `VirtualJoystick`s a cada frame de 16 ms.
- **Persistência e edição sincronizada de `AcroSettings`:**
  - `AcroSettings` ganhou `toJson`, `fromJson` (com `clamp` defensivo), `operator ==` e `hashCode` em [quadrotor_physics_6dof.dart](lib/simulation/quadrotor_physics_6dof.dart).
  - `RecordsRepository` persiste e restaura `AcroSettings` na chave `drone_simulator_acro_settings_v1` via `saveAcroSettings` e `loadAll()` ([records_repository.dart](lib/services/records_repository.dart)).
  - `SimulatorController`, `HomeMenuScreen` ([home_menu_screen.dart](lib/ui/screens/home_menu_screen.dart)) e `MapSettingsModal` ([map_settings_modal.dart](lib/widgets/map_settings_modal.dart)) sincronizam presets, `Expo`, `Uptilt FPV`, `Assistência de Horizonte` e `Curva Coordenada (Auto-Yaw)` entre pré-voo e em voo (com cabeçalho fixo no sheet da Home para caber em `640x360`).

### Concluído (Bloco 2)
- **Detecção real no plano orientado do portal (`Gate Race` & `Time Attack`):**
  - `RaceGate` ([race_course.dart](lib/models/race_course.dart)) expõe `planeNormal`, `signedPlaneDistance` e `inPlaneRadius` na convenção ENU (`0° = Norte`, `90° = Leste`).
  - `RaceManager` ([race_manager.dart](lib/simulation/race_manager.dart)) detecta cruzamento real de plano entre frames com interpolação linear (evitando falsos positivos paralelos e tunneling em alta velocidade), mantém fallback para teleporte direto no portal e calcula `lastGateAccuracy`.
  - Na cena 3D ([index.html](assets/scene3d/index.html)), `buildRaceGate` agrupa anel, halo e setas com rotação alinhada à orientação `yaw` ENU.
- **Novas manobras no `FreestyleManager` ([freestyle_manager.dart](lib/simulation/freestyle_manager.dart)):**
  - Adicionadas detecções de `POWER LOOP` (400 pts), `SPLIT-S` (380 pts, sem duplicar `DIVE RECOVERY`) e `INVERTED HANGTIME` (220 pts), além de `trickBreakdown` e passagem de `upWorldZ` e `horizontalSpeedMs` pelo `SimulatorController`.
  - Subtítulo do card Freestyle atualizado em [home_menu_screen.dart](lib/ui/screens/home_menu_screen.dart).
- **Replay pós-corrida reaproveitando `GhostFrame`:**
  - Adicionados `Quat.operator *` e `Quat.fromEuler` em [quadrotor_physics_6dof.dart](lib/simulation/quadrotor_physics_6dof.dart).
  - `SimulatorController` grava a trajetória de `gateRace` e `timeAttack` e oferece `startReplay()`, `toggleReplayPause()`, `seekReplay()`, `cycleReplaySpeed()` (`1.0x → 2.0x → 0.5x`), `restartReplay()` e `stopReplay()`, restaurando o modo de câmera ao sair.
  - `World3dView` ([world_3d_view.dart](lib/widgets/world_3d_view.dart)) silencia motores quando o replay está pausado e mantém o drone armado para renderização da câmera/quatérnio; `GameHudOverlay` ([game_hud_overlay.dart](lib/widgets/game_hud_overlay.dart)) exibe `ASSISTIR REPLAY` no card final e a barra `replay_controls_bar` sem overflow em `640x360`.
- **Validação:**
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`: 0 erros/avisos.
  - `flutter test`: 165 testes passando (incluindo [block1_improvements_test.dart](test/block1_improvements_test.dart) e [block2_gameplay_test.dart](test/block2_gameplay_test.dart)).

### Próximo Passo Pendente
- **Bloco 2 (complemento opcional):** Recorde e Ghost independentes por perfil de drone (`Mini 249g` vs `FPV Racer`).
- **Bloco 3 — Controles & Visual 3D:** Joystick flutuante (touch-anywhere) com opção de throttle sem auto-centro no Acro puro, suporte a gamepad/HID, alinhamento do `FpvOsdOverlay` com `fpvUptiltDeg`, marcador de projeção no solo para pouso em 3ª pessoa, melhoria de áudio de hélices e fallback vetorial offline no minimapa.
- **Limpeza opcional:** Avaliar remoção/unificação da árvore legada (`lib/ui/screens/simulator_screen.dart`, `lib/providers/simulation_provider.dart`, `lib/ui/widgets/`).
