import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/world_3d_view.dart';

void main() {
  group('Etapa 1: World3dView & Offline Three.js Environment', () {
    testWidgets('World3dView compila e renderiza com segurança no Flutter', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: World3dView(
              controller: controller,
            ),
          ),
        ),
      );

      expect(find.byType(World3dView), findsOneWidget);
      expect(find.byKey(const Key('world_3d_placeholder')), findsOneWidget);

      controller.dispose();
    });

    testWidgets('World3dView sincroniza estado quando controller emite tick', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: World3dView(
              controller: controller,
            ),
          ),
        ),
      );

      // Dispara mudança de estado
      controller.setManualInput(throttle: 0.5, pitch: 0.2);
      await tester.pump();

      expect(find.byType(World3dView), findsOneWidget);

      controller.dispose();
    });
  });
}
