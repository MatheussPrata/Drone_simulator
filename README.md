# Drone Simulator 🛸

Simulador tático de voo de drone desenvolvido em **Flutter**, com renderização nativa 2D via `CustomPainter`, controles analógicos Modo 2, loop de física a 60 FPS, gerenciamento de bateria e sistema rigoroso de Geofence e Zonas de Exclusão Aérea (No-Fly Zones).

---

## 🚀 Como Rodar o Projeto

### Pré-requisitos
- **Flutter SDK:** >= 3.24.0
- **Dispositivo ou Emulador:** Android (orientação horizontal forçada)

### Execução
```bash
# Obter dependências
flutter pub get

# Executar em dispositivo ou emulador conectado
flutter run

# Executar testes unitários e de widgets
flutter test

# Validar conformidade de código
flutter analyze
```

---

## 🕹️ Controles de Pilotagem (Modo 2)

A interface utiliza o padrão mundial de pilotagem de drones e aeromodelos (**Modo 2**), com dois joysticks virtuais analógicos sobre o mapa:

### Joystick Esquerdo
- **Vertical (Throttle):**
  - **Empurrar para cima:** Aumenta a aceleração e sobe a altitude ($z$).
  - **Puxar para baixo:** Reduz a altitude e desce o drone.
- **Horizontal (Yaw):**
  - **Mover para esquerda/direita:** Gira a proa (heading) do drone sobre o próprio eixo.

### Joystick Direito
- **Vertical (Pitch):**
  - **Empurrar para cima:** Inclina o drone para a frente e avança no espaço 2D.
  - **Puxar para baixo:** Inclina para trás e recua.
- **Horizontal (Roll):**
  - **Mover para esquerda/direita:** Translação lateral (*strafe*) para a esquerda ou direita.

### Botões de Comando (HUD Superior)
- **Decolar:** Arma os motores e realiza subida assistida automática até 10 metros, estabilizando em *hovering*.
- **Pousar:** Inicia descida controlada vertical até o solo ($z = 0$) e desarma os motores com segurança.
- **RTH (Return to Home):** Calcula a rota de retorno à base $(0, 0)$, move o drone a uma velocidade constante de 8 m/s e pousa automaticamente ao chegar.
- **Reset:** Restaura a posição, atitude e parâmetros do drone de volta ao ponto inicial com 100% de bateria.

---

## 🛡️ Regras de Geofence e No-Fly Zones

1. **Geofence Máximo (500 metros):**
   - O drone possui um raio máximo autorizado de **500m** a partir do ponto de decolagem $(0, 0)$.
   - Ao atingir a barreira de 500m, o avanço radial para fora é fisicamente bloqueado pela engine física (`GeofenceValidator`), mantendo apenas movimento tangencial ou de retorno.
   - Um **banner vermelho de advertência** é disparado no topo da tela.

2. **Área de Advertência de Proximidade (400 metros):**
   - Ao ultrapassar 80% do raio máximo (400m), o piloto recebe alertas visuais preventivos no HUD.

3. **Zonas de Exclusão Aérea (No-Fly Zones - NFZ):**
   - Áreas restritas (aeroportos, helipontos e áreas de segurança) são desenhadas em vermelho translúcido no mapa.
   - A entrada em uma NFZ gera um alerta sonoro/visual prioritário imediato no HUD.

4. **Fail-Safe de Bateria:**
   - O consumo de energia é simulado em tempo real proporcionalmente à altitude e velocidade.
   - Caso a bateria atinja um nível crítico (**< 15%**), o simulador aciona **RTH automático**, garantindo o retorno à base antes do esgotamento completo.

---

## 📐 Arquitetura dos Módulos

```
lib/
├── main.dart                          # Ponto de entrada (landscape forçado, Stack principal com mapa real)
├── widgets/
│   ├── mini_map_widget.dart           # Mapa real (Satélite/OSM) com geofence, zonas No-Fly e drone dinâmico
│   ├── map_canvas.dart                # Canvas 2D nativo (grade, geofence, NFZs e sombra por altitude)
│   ├── telemetry_hud.dart             # Barra superior (Alt, Vel, Home, Bateria, Ações e Alertas)
│   └── virtual_joystick.dart          # Joystick analógico circular desacoplado com autocentralização
└── simulation/
    ├── simulator_controller.dart      # Loop temporal a 60 FPS e máquina de estados de voo
    ├── flight_physics.dart            # Integração e typedefs da engine de física
    └── geofence_validator.dart        # Validação geométrica cartesiana e geográfica de limites
```
