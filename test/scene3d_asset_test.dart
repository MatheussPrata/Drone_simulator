import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Etapa 3 — Câmera cinemática no cenário Three.js', () {
    final html = File('assets/scene3d/index.html').readAsStringSync();

    test('Transição FPV ↔ 3ª pessoa é interpolada em ~0.45s (sem teleporte)',
        () {
      expect(html.contains('cameraTransition'), true);
      expect(html.contains('1.0 / 0.45'), true);
      expect(html.contains('smoothstep') || html.contains('3.0 - 2.0'),
          true);
      expect(html.contains('droneGroup.visible = cameraTransition > 0.02'), true);
    });

    test('Chase cam usa amortecimento exponencial independente por eixo', () {
      expect(html.contains('Math.exp(-3.2 * dt)'), true,
          reason: 'Curvas de yaw devem ser elásticas (horizontal)');
      expect(html.contains('Math.exp(-8.0 * dt)'), true,
          reason: 'Eixo vertical deve responder mais rápido');
      expect(html.contains('chaseSpringPos'), true);
      expect(html.contains('chaseSpringLook'), true);
    });

    test('Horizonte inclina apenas roll * 0.25 na 3ª pessoa', () {
      expect(html.contains('rollRad * 0.25 * blend'), true);
    });

    test('Cena carrega Three.js local, sem CDN', () {
      expect(html.contains('three.min.js'), true);
      expect(html.contains('cdn.jsdelivr.net'), false);
      expect(html.contains('unpkg.com'), false);
      expect(html.contains('cdnjs.cloudflare.com'), false);
    });

    test('Cena recebe planta de obstáculos e estado do drone do Flutter', () {
      expect(html.contains('window.loadWorldObstacles'), true);
      expect(html.contains('window.updateDroneState'), true);
    });
  });
}
