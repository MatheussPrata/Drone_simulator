import 'package:flutter/material.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';

/// Barra vertical discreta para controle de inclinação da câmera gimbal (0° a -90°).
///
/// Permite ao piloto inclinar suavemente o gimbal entre 0° (olhando para o horizonte)
/// e -90° (olhando reto para o chão) por arrasto vertical ou toque nas graduações.
class GimbalSlider extends StatefulWidget {
  final SimulatorController? controller;
  final double pitch;
  final ValueChanged<double>? onChanged;
  final double height;
  final double width;

  const GimbalSlider({
    super.key,
    this.controller,
    this.pitch = 0.0,
    this.onChanged,
    this.height = 180.0,
    this.width = 44.0,
  });

  @override
  State<GimbalSlider> createState() => _GimbalSliderState();
}

class _GimbalSliderState extends State<GimbalSlider> {
  double _internalPitch = 0.0;

  @override
  void initState() {
    super.initState();
    _internalPitch = widget.controller?.gimbalPitch ?? widget.pitch;
    widget.controller?.addListener(_onControllerUpdate);
  }

  @override
  void didUpdateWidget(GimbalSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerUpdate);
      widget.controller?.addListener(_onControllerUpdate);
      _internalPitch = widget.controller?.gimbalPitch ?? widget.pitch;
    } else if (widget.controller == null && oldWidget.pitch != widget.pitch) {
      _internalPitch = widget.pitch;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (widget.controller != null && mounted) {
      final current = widget.controller!.gimbalPitch;
      if (current != _internalPitch) {
        setState(() {
          _internalPitch = current;
        });
      }
    }
  }

  void _handleDrag(Offset localPos, double trackHeight) {
    // Topo (y = 0) -> 0.0° (horizonte)
    // Fundo (y = trackHeight) -> -90.0° (solo)
    final clampedY = localPos.dy.clamp(0.0, trackHeight);
    final frac = clampedY / trackHeight;
    final newPitch = (-frac * 90.0).clamp(-90.0, 0.0);

    setState(() {
      _internalPitch = newPitch;
    });

    widget.onChanged?.call(newPitch);
    widget.controller?.setGimbalPitch(newPitch);
  }

  @override
  Widget build(BuildContext context) {
    final curPitch = widget.controller != null
        ? widget.controller!.gimbalPitch
        : _internalPitch;

    // Fração de 0.0 (topo) a 1.0 (fundo)
    final frac = (-curPitch / 90.0).clamp(0.0, 1.0);
    const double headerHeight = 30.0;
    const double footerHeight = 24.0;

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Cabeçalho: Ícone de Câmera e Botão Rápido 0° (Horizonte) ──
          GestureDetector(
            onTap: () {
              setState(() => _internalPitch = 0.0);
              widget.onChanged?.call(0.0);
              widget.controller?.setGimbalPitch(0.0);
            },
            child: Container(
              height: headerHeight,
              alignment: Alignment.center,
              child: const Icon(
                Icons.videocam,
                size: 16,
                color: Colors.cyanAccent,
              ),
            ),
          ),

          // ── Trilha Vertical Interativa (Track) ──
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final h = constraints.maxHeight;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (details) => _handleDrag(details.localPosition, h),
                  onVerticalDragUpdate: (details) => _handleDrag(details.localPosition, h),
                  onTapDown: (details) => _handleDrag(details.localPosition, h),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Trilha de linha central
                      Container(
                        width: 2.0,
                        height: h,
                        color: Colors.cyanAccent.withOpacity(0.2),
                      ),

                      // Marcas de graduação discretas (0°, -30°, -60°, -90°)
                      _buildTick(0.0, h, '0°'),
                      _buildTick(1 / 3, h, '-30°'),
                      _buildTick(2 / 3, h, '-60°'),
                      _buildTick(1.0, h, '-90°'),

                      // Thumb / Cursor deslizante da câmera
                      Positioned(
                        top: (frac * h - 8.0).clamp(0.0, h - 16.0),
                        child: Container(
                          width: 28.0,
                          height: 16.0,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.cyanAccent.withOpacity(0.6),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            curPitch.toStringAsFixed(0),
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── Rodapé: Botão Rápido -90° (Solo) ──
          GestureDetector(
            onTap: () {
              setState(() => _internalPitch = -90.0);
              widget.onChanged?.call(-90.0);
              widget.controller?.setGimbalPitch(-90.0);
            },
            child: Container(
              height: footerHeight,
              alignment: Alignment.center,
              child: Text(
                'NADIR',
                style: TextStyle(
                  color: Colors.cyanAccent.withOpacity(0.8),
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTick(double factor, double totalHeight, String label) {
    final y = factor * totalHeight;

    return Positioned(
      top: y - 5.0,
      left: 4.0,
      right: 4.0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 4.0,
            height: 1.0,
            color: Colors.white38,
          ),
          Container(
            width: 4.0,
            height: 1.0,
            color: Colors.white38,
          ),
        ],
      ),
    );
  }
}
