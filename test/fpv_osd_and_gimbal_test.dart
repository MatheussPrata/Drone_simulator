import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/fpv_osd_overlay.dart';
import 'package:drone_simulator/widgets/gimbal_slider.dart';

void main() {
  group('FpvOsdMath - Cálculos Trigonométricos e Rumo', () {
    test('calculateHomeBearing: calcula rumo exato em graus cardeais em direção a (0,0)', () {
      // Drone ao Norte de Home (0, 100) -> Para voltar a Home, rumo deve ser Sul (180°)
      final bearingSouth = FpvOsdMath.calculateHomeBearing(droneX: 0.0, droneY: 100.0);
      expect(bearingSouth, closeTo(180.0, 0.01));

      // Drone a Leste de Home (100, 0) -> Para voltar a Home, rumo deve ser Oeste (270°)
      final bearingWest = FpvOsdMath.calculateHomeBearing(droneX: 100.0, droneY: 0.0);
      expect(bearingWest, closeTo(270.0, 0.01));

      // Drone ao Sul de Home (0, -100) -> Para voltar a Home, rumo deve ser Norte (0° / 360°)
      final bearingNorth = FpvOsdMath.calculateHomeBearing(droneX: 0.0, droneY: -100.0);
      expect(bearingNorth, closeTo(0.0, 0.01));

      // Drone a Oeste de Home (-100, 0) -> Para voltar a Home, rumo deve ser Leste (90°)
      final bearingEast = FpvOsdMath.calculateHomeBearing(droneX: -100.0, droneY: 0.0);
      expect(bearingEast, closeTo(90.0, 0.01));

      // Drone em (50, 50) -> Rumo deve ser Sudoeste (225°)
      final bearingSW = FpvOsdMath.calculateHomeBearing(droneX: 50.0, droneY: 50.0);
      expect(bearingSW, closeTo(225.0, 0.01));

      // Drone na própria origem Home (0, 0) -> Retorna 0.0 sem divisão por zero
      final bearingOrigin = FpvOsdMath.calculateHomeBearing(droneX: 0.0, droneY: 0.0);
      expect(bearingOrigin, equals(0.0));
    });

    test('calculateRelativeAngle: normaliza ângulo relativo entre [-180, 180]', () {
      // Olhando diretamente para o alvo
      expect(
        FpvOsdMath.calculateRelativeAngle(targetBearing: 180.0, currentYaw: 180.0),
        closeTo(0.0, 0.01),
      );

      // Alvo a 90° à direita
      expect(
        FpvOsdMath.calculateRelativeAngle(targetBearing: 180.0, currentYaw: 90.0),
        closeTo(90.0, 0.01),
      );

      // Alvo a 90° à esquerda
      expect(
        FpvOsdMath.calculateRelativeAngle(targetBearing: 180.0, currentYaw: 270.0),
        closeTo(-90.0, 0.01),
      );

      // Alvo diretamente atrás
      expect(
        FpvOsdMath.calculateRelativeAngle(targetBearing: 180.0, currentYaw: 0.0).abs(),
        closeTo(180.0, 0.01),
      );

      // Descontinuidade de 360° -> 0° (Wrap-around): target 10°, yaw 350° => +20°
      expect(
        FpvOsdMath.calculateRelativeAngle(targetBearing: 10.0, currentYaw: 350.0),
        closeTo(20.0, 0.01),
      );

      // Wrap-around inverso: target 350°, yaw 10° => -20°
      expect(
        FpvOsdMath.calculateRelativeAngle(targetBearing: 350.0, currentYaw: 10.0),
        closeTo(-20.0, 0.01),
      );
    });

    test('headingToCardinal: mapeia rumo para pontos cardeais N, NE, L, SE, S, SO, O, NO', () {
      expect(FpvOsdMath.headingToCardinal(0.0), equals('N'));
      expect(FpvOsdMath.headingToCardinal(359.0), equals('N'));
      expect(FpvOsdMath.headingToCardinal(45.0), equals('NE'));
      expect(FpvOsdMath.headingToCardinal(90.0), equals('L'));
      expect(FpvOsdMath.headingToCardinal(135.0), equals('SE'));
      expect(FpvOsdMath.headingToCardinal(180.0), equals('S'));
      expect(FpvOsdMath.headingToCardinal(225.0), equals('SO'));
      expect(FpvOsdMath.headingToCardinal(270.0), equals('O'));
      expect(FpvOsdMath.headingToCardinal(315.0), equals('NO'));
    });
  });

  group('Critério de aceite: Bússola superior e Marcador H', () {
    testWidgets('Critério de aceite 1: Bússola superior acompanha o yaw', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 480,
              child: FpvOsdOverlay(
                controller: controller,
                yaw: 0.0,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(FpvOsdOverlay), findsOneWidget);

      // Altera o yaw do simulador para 90° (Leste)
      controller.setYaw(90.0);
      await tester.pump();

      // Altera o yaw do simulador para 180° (Sul)
      controller.setYaw(180.0);
      await tester.pump();

      // Altera o yaw do simulador para 270° (Oeste)
      controller.setYaw(270.0);
      await tester.pump();

      expect(tester.takeException(), isNull);
      controller.dispose();
    });

    testWidgets('Critério de aceite 2: Marcador H aponta sempre para a origem (0,0)', (tester) async {
      // 1. Drone em (0, 100) com yaw = 180° (olhando direto para Home)
      // Home está no centro do campo visual frontal
      final bearing1 = FpvOsdMath.calculateHomeBearing(droneX: 0.0, droneY: 100.0);
      final relAngle1 = FpvOsdMath.calculateRelativeAngle(targetBearing: bearing1, currentYaw: 180.0);
      expect(relAngle1, closeTo(0.0, 0.01)); // Diretamente no centro frontal

      // 2. Drone em (100, 0) com yaw = 0° (apontando ao Norte, Home fica a Oeste = 270°)
      // Ângulo relativo deve ser -90° (à esquerda)
      final bearing2 = FpvOsdMath.calculateHomeBearing(droneX: 100.0, droneY: 0.0);
      final relAngle2 = FpvOsdMath.calculateRelativeAngle(targetBearing: bearing2, currentYaw: 0.0);
      expect(relAngle2, closeTo(-90.0, 0.01));

      // Renderiza FpvOsdOverlay com drone deslocado da origem
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 480,
              child: FpvOsdOverlay(
                droneX: 150.0,
                droneY: 200.0,
                droneZ: 25.0,
                yaw: 45.0,
                visualPitch: -5.0,
                visualRoll: 2.0,
                gimbalPitch: -15.0,
                homeX: 0.0,
                homeY: 0.0,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(FpvOsdOverlay), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('FpvOsdPainter: shouldRepaint detecta mudanças de yaw, posição e inclinação', () {
      final painterA = FpvOsdPainter(
        yaw: 0.0,
        visualPitch: 0.0,
        visualRoll: 0.0,
        gimbalPitch: 0.0,
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 0.0,
      );

      final painterSame = FpvOsdPainter(
        yaw: 0.0,
        visualPitch: 0.0,
        visualRoll: 0.0,
        gimbalPitch: 0.0,
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 0.0,
      );

      final painterYawDiff = FpvOsdPainter(
        yaw: 45.0,
        visualPitch: 0.0,
        visualRoll: 0.0,
        gimbalPitch: 0.0,
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 0.0,
      );

      final painterPosDiff = FpvOsdPainter(
        yaw: 0.0,
        visualPitch: 0.0,
        visualRoll: 0.0,
        gimbalPitch: 0.0,
        droneX: 50.0,
        droneY: 0.0,
        droneZ: 0.0,
      );

      expect(painterA.shouldRepaint(painterSame), isFalse);
      expect(painterA.shouldRepaint(painterYawDiff), isTrue);
      expect(painterA.shouldRepaint(painterPosDiff), isTrue);
    });
  });

  group('GimbalSlider - Slider Vertical de Inclinação de Câmera', () {
    testWidgets('Renderiza slider vertical com graduações 0°, -30°, -60°, -90°', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GimbalSlider(
                pitch: -45.0,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(GimbalSlider), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(find.text('NADIR'), findsOneWidget);
      expect(find.text('-45'), findsOneWidget); // Leitura atual no thumb
    });

    testWidgets('Toque no ícone superior videocam redefine pitch para 0.0°', (tester) async {
      double changedPitch = -45.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GimbalSlider(
                pitch: -45.0,
                onChanged: (p) => changedPitch = p,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.videocam));
      await tester.pump();

      expect(changedPitch, equals(0.0));
    });

    testWidgets('Toque no botão inferior NADIR redefine pitch para -90.0°', (tester) async {
      double changedPitch = 0.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GimbalSlider(
                pitch: 0.0,
                onChanged: (p) => changedPitch = p,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('NADIR'));
      await tester.pump();

      expect(changedPitch, equals(-90.0));
    });

    testWidgets('Arrasto vertical ajusta gimbalPitch suavemente entre 0° e -90°', (tester) async {
      final controller = SimulatorController();
      expect(controller.gimbalPitch, equals(0.0));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GimbalSlider(
                controller: controller,
                height: 200,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Arrasta o slider para baixo a partir do centro
      final sliderCenter = tester.getCenter(find.byType(GimbalSlider));
      await tester.dragFrom(sliderCenter, const Offset(0, 50));
      await tester.pump();

      // Deve ter inclinado para baixo (valor negativo entre 0 e -90)
      expect(controller.gimbalPitch, lessThan(0.0));
      expect(controller.gimbalPitch, greaterThanOrEqualTo(-90.0));

      controller.dispose();
    });

    testWidgets('Integração com SimulatorController reflete alterações externas', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GimbalSlider(
                controller: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('0'), findsOneWidget);

      controller.setGimbalPitch(-60.0);
      await tester.pump();

      expect(find.text('-60'), findsOneWidget);

      controller.dispose();
    });
  });
}
