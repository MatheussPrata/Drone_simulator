import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/main.dart';
import 'package:drone_simulator/widgets/map_canvas.dart';
import 'package:drone_simulator/widgets/telemetry_hud.dart';
import 'package:drone_simulator/widgets/virtual_joystick.dart';

void main() {
  testWidgets('DroneSimulatorApp inicializa e renderiza tela principal com Stack', (tester) async {
    await tester.pumpWidget(const DroneSimulatorApp());
    await tester.pump();

    expect(find.byType(FlightSimulatorScreen), findsOneWidget);
    expect(find.byType(MapCanvas), findsOneWidget);
    expect(find.byType(TelemetryHud), findsOneWidget);
    expect(find.byType(VirtualJoystick), findsNWidgets(2));
    expect(find.text('THROTTLE / YAW'), findsOneWidget);
    expect(find.text('PITCH / ROLL'), findsOneWidget);
  });
}
