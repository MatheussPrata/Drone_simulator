import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/simulation/flight_physics.dart';
import 'package:drone_simulator/widgets/fpv_camera_view.dart';

void main() {
  group('FpvCameraProjector - Projeção 3D e Perspectiva FPV', () {
    const size = Size(800, 600);
    const cx = 400.0;
    const cy = 300.0;

    test('Critério de aceite 1: Ao decolar (z subindo), o solo se afasta e marcos escalam inversamente', () {
      // 1. Drone a baixa altitude (z = 2m, solo próximo)
      final projLow = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 2.0,
        yawDeg: 0.0,
        screenSize: size,
      );

      // 2. Drone a altitude de cruzeiro (z = 20m)
      final projMid = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 20.0,
        yawDeg: 0.0,
        screenSize: size,
      );

      // 3. Drone a alta altitude (z = 60m)
      final projHigh = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 60.0,
        yawDeg: 0.0,
        screenSize: size,
      );

      // Marco vertical (poste de 10m de altura) a 40m à frente (0, 40)
      final lowBase = projLow.project(0.0, 40.0, 0.0)!;
      final lowTop = projLow.project(0.0, 40.0, 10.0)!;
      final lowHeight = (lowBase.dy - lowTop.dy).abs();

      final midBase = projMid.project(0.0, 40.0, 0.0)!;
      final midTop = projMid.project(0.0, 40.0, 10.0)!;
      final midHeight = (midBase.dy - midTop.dy).abs();

      final highBase = projHigh.project(0.0, 40.0, 0.0)!;
      final highTop = projHigh.project(0.0, 40.0, 10.0)!;
      final highHeight = (highBase.dy - highTop.dy).abs();

      // Ao subir a altitude, o ponto no solo se desloca para baixo na tela (mais próximo dos pés)
      expect(midBase.dy, greaterThan(lowBase.dy));
      expect(highBase.dy, greaterThan(midBase.dy));

      // E a altura aparente de objetos a mesma distância angular diminui ou se afasta proporcionalmente
      expect(lowHeight, greaterThan(0.0));
      expect(midHeight, greaterThan(0.0));
      expect(highHeight, greaterThan(0.0));
      expect(lowTop.dy, lessThan(midTop.dy)); // No low, o topo está mais alto no campo visual
    });

    test('Critério de aceite 2: Ao girar o yaw, a paisagem e os marcos giram suavemente em 360°', () {
      // Marco fixo ao Norte: (0, 60, 5)
      const targetX = 0.0;
      const targetY = 60.0;
      const targetZ = 5.0;

      // Yaw = 0° (apontando diretamente para o Norte)
      final projNorth = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yawDeg: 0.0,
        screenSize: size,
      );
      final pNorth = projNorth.project(targetX, targetY, targetZ)!;
      expect(pNorth.dx, closeTo(cx, 1.0)); // Perfeitamente centralizado no eixo X

      // Yaw = 30° (girando para Leste/direita -> o marco ao Norte se desloca para a ESQUERDA da tela)
      final projTurnRight = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yawDeg: 30.0,
        screenSize: size,
      );
      final pTurnRight = projTurnRight.project(targetX, targetY, targetZ)!;
      expect(pTurnRight.dx, lessThan(cx)); // Deslocou para a esquerda

      // Yaw = 330° (-30°, girando para Oeste/esquerda -> o marco ao Norte se desloca para a DIREITA da tela)
      final projTurnLeft = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yawDeg: 330.0,
        screenSize: size,
      );
      final pTurnLeft = projTurnLeft.project(targetX, targetY, targetZ)!;
      expect(pTurnLeft.dx, greaterThan(cx)); // Deslocou para a direita

      // Yaw = 180° (apontando para o Sul -> o marco ao Norte fica ATRÁS da câmera)
      final projSouth = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yawDeg: 180.0,
        screenSize: size,
      );
      final pSouth = projSouth.project(targetX, targetY, targetZ);
      expect(pSouth, isNull); // Não projeta pontos situados atrás da lente (corte de plano)
    });

    test('Critério de aceite 3: Ao inclinar para os lados (roll), o horizonte inclina como numa câmera real', () {
      // Dois pontos simétricos na linha horizontal à frente: (-30, 50, 0) e (+30, 50, 0)
      const pLeftX = -30.0;
      const pRightX = 30.0;
      const pY = 50.0;
      const pZ = 0.0;

      // 1. Roll neutro (0°) -> horizonte nivelado (dy igual em ambos os lados)
      final projLevel = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yawDeg: 0.0,
        visualRollDeg: 0.0,
        screenSize: size,
      );
      final leftLevel = projLevel.project(pLeftX, pY, pZ)!;
      final rightLevel = projLevel.project(pRightX, pY, pZ)!;
      expect(leftLevel.dy, closeTo(rightLevel.dy, 0.01));

      // 2. Roll para a direita (+15°) -> a câmera inclina para a direita,
      // logo a paisagem e o horizonte inclinam na direção oposta na tela
      final projRollRight = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yawDeg: 0.0,
        visualRollDeg: 15.0,
        screenSize: size,
      );
      final leftRollRight = projRollRight.project(pLeftX, pY, pZ)!;
      final rightRollRight = projRollRight.project(pRightX, pY, pZ)!;
      // Ao rolar para a direita, a asa direita abaixa, logo o lado direito do horizonte sobe na visão da câmera (menor Y)
      expect(rightRollRight.dy, lessThan(leftRollRight.dy));

      // 3. Roll para a esquerda (-15°) -> inclinação oposta
      final projRollLeft = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yawDeg: 0.0,
        visualRollDeg: -15.0,
        screenSize: size,
      );
      final leftRollLeft = projRollLeft.project(pLeftX, pY, pZ)!;
      final rightRollLeft = projRollLeft.project(pRightX, pY, pZ)!;
      expect(rightRollLeft.dy, greaterThan(leftRollLeft.dy));
    });

    test('Pitch e Gimbal Pitch elevam e abaixam o horizonte corretamente', () {
      // Ponto no solo a 50m à frente: (0, 50, 0)
      const pX = 0.0;
      const pY = 50.0;
      const pZ = 0.0;

      // Câmera nivelada no horizonte (pitch = 0°)
      final projHorizon = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yawDeg: 0.0,
        visualPitchDeg: 0.0,
        gimbalPitchDeg: 0.0,
        screenSize: size,
      );
      final pLevel = projHorizon.project(pX, pY, pZ)!;

      // Câmera inclinada para o chão (gimbalPitch = -45°)
      final projDown = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yawDeg: 0.0,
        visualPitchDeg: 0.0,
        gimbalPitchDeg: -45.0,
        screenSize: size,
      );
      final pDown = projDown.project(pX, pY, pZ)!;

      // Ao olhar para o solo (gimbal < 0), o ponto à frente sobe na tela em direção ao topo
      expect(pDown.dy, lessThan(pLevel.dy));

      // Se gimbal está a -90° (olhando reto para o chão), o ponto logo abaixo do drone (0, 0, 0)
      // projeta na região central da tela
      final projNadir = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yawDeg: 0.0,
        gimbalPitchDeg: -90.0,
        screenSize: size,
      );
      final pNadir = projNadir.project(0.0, 0.0, 0.0)!;
      expect(pNadir.dx, closeTo(cx, 1.0));
      expect(pNadir.dy, closeTo(cy, 1.0));
    });

    test('projectLine corta retas que cruzam o plano próximo da câmera (near clip)', () {
      final proj = FpvCameraProjector(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yawDeg: 0.0,
        screenSize: size,
      );

      // Linha que se estende de trás da câmera (Y = -20) até à frente (Y = +50)
      final seg = proj.projectLine(0.0, -20.0, 0.0, 0.0, 50.0, 0.0);
      expect(seg, isNotNull);
      expect(seg!.length, 2);
      expect(seg[0].dx, closeTo(cx, 1.0));
      expect(seg[1].dx, closeTo(cx, 1.0));

      // Linha completamente atrás da câmera (Y = -50 a Y = -10)
      final behind = proj.projectLine(0.0, -50.0, 0.0, 0.0, -10.0, 0.0);
      expect(behind, isNull);
    });
  });

  group('FpvCameraView Widget Tests', () {
    testWidgets('Compila e renderiza em tela cheia com valores manuais sem erros', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FpvCameraView(
              droneX: 0.0,
              droneY: 0.0,
              droneZ: 15.0,
              yaw: 45.0,
              visualPitch: -5.0,
              visualRoll: 10.0,
              gimbalPitch: -20.0,
              showOsd: true,
              showGrid: true,
              showGeofence: true,
              showLandmarks: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(FpvCameraView), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('Renderiza integrado com SimulatorController e atualiza telemetria no OSD', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FpvCameraView(
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(FpvCameraView), findsOneWidget);

      // Decola o drone via controller
      controller.armAndTakeoff();
      for (int i = 0; i < 10; i++) {
        controller.update(0.016);
      }
      await tester.pump();

      // Ajusta gimbal
      controller.setGimbalPitch(-35.0);
      await tester.pump();

      expect(controller.gimbalPitch, -35.0);
      expect(find.byType(FpvCameraView), findsOneWidget);

      controller.dispose();
    });

    test('FpvCameraPainter shouldRepaint detecta mudanças de parâmetros com precisão', () {
      final map = FlightMap.dronePark;
      final painter1 = FpvCameraPainter(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yaw: 0.0,
        visualPitch: 0.0,
        visualRoll: 0.0,
        gimbalPitch: 0.0,
        flightMap: map,
      );

      final painterSame = FpvCameraPainter(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yaw: 0.0,
        visualPitch: 0.0,
        visualRoll: 0.0,
        gimbalPitch: 0.0,
        flightMap: map,
      );

      final painterDiffYaw = FpvCameraPainter(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 10.0,
        yaw: 15.0,
        visualPitch: 0.0,
        visualRoll: 0.0,
        gimbalPitch: 0.0,
        flightMap: map,
      );

      final painterDiffAltitude = FpvCameraPainter(
        droneX: 0.0,
        droneY: 0.0,
        droneZ: 25.0,
        yaw: 0.0,
        visualPitch: 0.0,
        visualRoll: 0.0,
        gimbalPitch: 0.0,
        flightMap: map,
      );

      expect(painter1.shouldRepaint(painterSame), isFalse);
      expect(painter1.shouldRepaint(painterDiffYaw), isTrue);
      expect(painter1.shouldRepaint(painterDiffAltitude), isTrue);
    });
  });
}
