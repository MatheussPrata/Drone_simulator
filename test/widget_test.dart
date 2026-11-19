import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/main.dart';
import 'package:drone_simulator/widgets/fpv_camera_view.dart';
import 'package:drone_simulator/widgets/fpv_osd_overlay.dart';
import 'package:drone_simulator/widgets/gimbal_slider.dart';
import 'package:drone_simulator/widgets/mini_map_widget.dart';
import 'package:drone_simulator/widgets/telemetry_hud.dart';
import 'package:drone_simulator/widgets/virtual_joystick.dart';
import 'package:drone_simulator/widgets/world_3d_view.dart';

void main() {
  group('Etapa 5 - Layout Estilo DJI Fly e Alternância PiP', () {
    testWidgets('DroneSimulatorApp inicializa com FPV 100% no fundo e Mini-Mapa no PiP', (tester) async {
      await tester.pumpWidget(const DroneSimulatorApp());
      await tester.pump();

      expect(find.byType(FlightSimulatorScreen), findsOneWidget);
      expect(find.byType(TelemetryHud), findsOneWidget);
      expect(find.byType(GimbalSlider), findsOneWidget);
      expect(find.byType(VirtualJoystick), findsNWidgets(2));
      expect(find.text('THROTTLE / YAW'), findsOneWidget);
      expect(find.text('PITCH / ROLL'), findsOneWidget);

      // 3D World e OSD ocupando tela cheia por padrão
      expect(find.byType(World3dView), findsOneWidget);
      expect(find.byType(FpvOsdOverlay), findsOneWidget);

      // Mini-Mapa no card PiP no canto inferior esquerdo
      expect(find.byType(MiniMapWidget), findsOneWidget);
      expect(find.byKey(const Key('pip_card_gesture')), findsOneWidget);
      expect(find.byKey(const Key('pip_swap_button')), findsOneWidget);
      expect(find.text('MAPA'), findsOneWidget); // Badge indicando mapa no PiP

      // Joysticks com opacidade configurada
      final joysticks = tester.widgetList<VirtualJoystick>(find.byType(VirtualJoystick));
      for (final stick in joysticks) {
        expect(stick.opacity, equals(0.70));
      }
    });

    testWidgets('Critério de aceite: Alternância fluida entre FPV e Mapa em tela cheia via botão de swap', (tester) async {
      await tester.pumpWidget(const DroneSimulatorApp());
      await tester.pump();

      // Estado Inicial: FPV tela cheia, Mini-Mapa no PiP
      expect(find.byType(FpvOsdOverlay), findsOneWidget);
      expect(find.text('MAPA'), findsOneWidget);

      // Toca no botão de expandir/trocar (swap)
      await tester.tap(find.byKey(const Key('pip_swap_button')));
      await tester.pump();

      // Estado 2: Mapa vai para tela cheia e FPV vira a janela pequena no canto
      expect(find.text('FPV'), findsOneWidget); // Badge agora indica FPV no PiP
      expect(find.byType(MiniMapWidget), findsOneWidget);
      expect(find.byType(FpvCameraView), findsOneWidget);
      // FpvOsdOverlay não é renderizado sobre o mapa em tela cheia
      expect(find.byType(FpvOsdOverlay), findsNothing);

      // Toca no card PiP para alternar de volta
      await tester.tap(find.byKey(const Key('pip_card_gesture')));
      await tester.pump();

      // Retorna ao estado inicial: FPV tela cheia com OSD
      expect(find.text('MAPA'), findsOneWidget);
      expect(find.byType(FpvOsdOverlay), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Pilotagem completa com visão em primeira pessoa e joysticks translúcidos', (tester) async {
      await tester.pumpWidget(const DroneSimulatorApp());
      await tester.pump();

      // Arrasto no joystick esquerdo para throttle
      final leftGestureFinder = find.byKey(const Key('virtual_joystick_gesture')).first;
      final leftCenter = tester.getCenter(leftGestureFinder);
      await tester.dragFrom(leftCenter, const Offset(0, -30)); // Para cima (-dy) = subir
      await tester.pump();

      // Arrasto no joystick direito para pitch/roll
      final rightGestureFinder = find.byKey(const Key('virtual_joystick_gesture')).last;
      final rightCenter = tester.getCenter(rightGestureFinder);
      await tester.dragFrom(rightCenter, const Offset(20, -20)); // Avançar e rolar
      await tester.pump();

      // Arrasto no slider de gimbal
      final sliderFinder = find.byType(GimbalSlider);
      expect(sliderFinder, findsOneWidget);
      final sliderCenter = tester.getCenter(sliderFinder);
      await tester.dragFrom(sliderCenter, const Offset(0, 30));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
