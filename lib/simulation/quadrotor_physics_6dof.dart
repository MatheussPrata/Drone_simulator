import 'dart:math' as math;

/// Modos de voo reais suportados pelo controlador em cascata.
enum FlightControlMode {
  /// Estabilizado (estilo DJI Normal): auto-nivelamento + Altitude Hold.
  stabilized,

  /// Esportivo: maior inclinação máxima (45°), aceleração agressiva, menor amortecimento.
  sport,

  /// Acro / FPV Manual: controle direto de taxas angulares (deg/s) e empuxo manual.
  acro,
}

/// Vetor 3D imutável para cálculos de física em ENU (X=Leste/Direita, Y=Norte/Frente, Z=Cima).
class Vec3 {
  final double x;
  final double y;
  final double z;

  const Vec3(this.x, this.y, this.z);
  static const Vec3 zero = Vec3(0.0, 0.0, 0.0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator /(double s) => Vec3(x / s, y / s, z / s);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get lengthSquared => x * x + y * y + z * z;
  double get length => math.sqrt(lengthSquared);

  Vec3 normalized() {
    final len = length;
    if (len < 1e-9) return Vec3.zero;
    return this / len;
  }
}

/// Quatérnio unitário para orientação 3D livre de Gimbal Lock.
class Quat {
  final double w;
  final double x;
  final double y;
  final double z;

  const Quat(this.w, this.x, this.y, this.z);
  static const Quat identity = Quat(1.0, 0.0, 0.0, 0.0);

  Quat normalized() {
    final n = math.sqrt(w * w + x * x + y * y + z * z);
    if (n < 1e-9) return Quat.identity;
    return Quat(w / n, x / n, y / n, z / n);
  }

  Quat get conjugate => Quat(w, -x, -y, -z);

  /// Rotaciona um vetor do referencial do corpo (Body) para o mundo (World ENU).
  Vec3 rotateBodyToWorld(Vec3 v) {
    final qv = Vec3(x, y, z);
    final t = qv.cross(v) * 2.0;
    return v + (t * w) + qv.cross(t);
  }

  /// Rotaciona um vetor do referencial do mundo (World ENU) para o corpo (Body).
  Vec3 rotateWorldToBody(Vec3 v) => conjugate.rotateBodyToWorld(v);

  /// Integra a orientação dada uma velocidade angular no referencial do corpo (rad/s).
  Quat integrate(Vec3 omegaBody, double dt) {
    final dw = 0.5 * (-x * omegaBody.x - y * omegaBody.y - z * omegaBody.z);
    final dx = 0.5 * (w * omegaBody.x + y * omegaBody.z - z * omegaBody.y);
    final dy = 0.5 * (w * omegaBody.y - x * omegaBody.z + z * omegaBody.x);
    final dz = 0.5 * (w * omegaBody.z + x * omegaBody.y - y * omegaBody.x);
    return Quat(w + dw * dt, x + dx * dt, y + dy * dt, z + dz * dt)
        .normalized();
  }

  /// Extrai ângulos de Euler (radianos):
  /// - pitch: positivo = nariz para cima (+Y em direção a +Z)
  /// - roll: positivo = inclinação para direita (+X em direção a -Z)
  /// - yaw: positivo = giro anti-horário (+Y em direção a -X)
  ({double pitch, double roll, double yaw}) toEulerRadians() {
    final forward = rotateBodyToWorld(const Vec3(0.0, 1.0, 0.0));
    final right = rotateBodyToWorld(const Vec3(1.0, 0.0, 0.0));
    final up = rotateBodyToWorld(const Vec3(0.0, 0.0, 1.0));

    final pitch = math.asin(forward.z.clamp(-1.0, 1.0));
    final roll = math.atan2(-right.z, up.z);
    final yaw = math.atan2(-forward.x, forward.y);
    return (pitch: pitch, roll: roll, yaw: yaw);
  }

  /// Cria quatérnio a partir de yaw (radianos, CCW a partir do Norte).
  static Quat fromYaw(double yawRad) {
    final half = yawRad * 0.5;
    return Quat(math.cos(half), 0.0, 0.0, math.sin(half));
  }
}

/// Parâmetros físicos calibrados para um quadricóptero profissional (~1.2 kg).
class DronePhysicsParams {
  final double massKg;
  final double gravity;
  final double armLengthM;
  final double rotorRadiusM;
  final Vec3 inertia; // Momentos de inércia (Ixx, Iyy, Izz) em kg*m^2
  final double rotorInertia; // Inércia do rotor para precessão giroscópica
  final double maxMotorRadPerSec;
  final double maxTotalThrustN;
  final double torqueToThrustRatio;
  final double motorTimeConstantSec; // Lag real dos motores (ESC + hélice)
  final Vec3 dragAreaCdA; // Área de arrasto efetiva (Cd * A) no corpo (X, Y, Z)
  final double bladeFlappingDrag; // Arrasto induzido linear pelas hélices
  final double angularDamping;
  final double airDensitySeaLevel;
  final double batteryCapacityWh;

  const DronePhysicsParams({
    this.massKg = 1.2,
    this.gravity = 9.80665,
    this.armLengthM = 0.22,
    this.rotorRadiusM = 0.11,
    this.inertia = const Vec3(0.014, 0.014, 0.025),
    this.rotorInertia = 3.5e-5,
    this.maxMotorRadPerSec = 1100.0,
    this.maxTotalThrustN = 34.0,
    this.torqueToThrustRatio = 0.018,
    this.motorTimeConstantSec = 0.030,
    this.dragAreaCdA = const Vec3(0.055, 0.055, 0.125),
    this.bladeFlappingDrag = 0.00022,
    this.angularDamping = 0.012,
    this.airDensitySeaLevel = 1.225,
    this.batteryCapacityWh = 45.0,
  });

  /// Coeficiente de empuxo kT (N / (rad/s)^2) por motor.
  double get kT =>
      (maxTotalThrustN / 4.0) / (maxMotorRadPerSec * maxMotorRadPerSec);

  /// Coeficiente de torque de reação kQ (N*m / (rad/s)^2) por motor.
  double get kQ => kT * torqueToThrustRatio;

  /// Distância projetada no eixo X/Y para frame em X (45°).
  double get armOffsetXY => armLengthM * 0.7071067811865476;
}

/// Comandos normalizados dos joysticks (-1.0 a 1.0).
class PilotStickInput {
  /// Esquerda vertical: -1 (descer/mínimo) a +1 (subir/máximo).
  final double throttle;

  /// Esquerda horizontal: -1 (girar esquerda/CCW) a +1 (girar direita/CW).
  final double yaw;

  /// Direita vertical: +1 (inclinar frente / acelerar) a -1 (ré).
  final double pitch;

  /// Direita horizontal: +1 (inclinar direita) a -1 (esquerda).
  final double roll;

  const PilotStickInput({
    this.throttle = 0.0,
    this.yaw = 0.0,
    this.pitch = 0.0,
    this.roll = 0.0,
  });

  static const PilotStickInput neutral = PilotStickInput();
}

/// Estado instantâneo exportado para o HUD, minimapa e cena 3D.
class PhysicsSnapshot {
  final Vec3 position;
  final Vec3 velocity;
  final Quat orientation;
  final Vec3 angularVelocityBody;
  final double pitchRad;
  final double rollRad;
  final double yawRad;
  final double speedMps;
  final double verticalSpeedMps;
  final List<double> motorNormalizedRpm; // 4 motores [0.0..1.0]
  final Vec3 windVelocityWorld;
  final double batteryPercent;
  final double groundEffectFactor;
  final bool inVortexRingState;
  final bool isGrounded;

  const PhysicsSnapshot({
    required this.position,
    required this.velocity,
    required this.orientation,
    required this.angularVelocityBody,
    required this.pitchRad,
    required this.rollRad,
    required this.yawRad,
    required this.speedMps,
    required this.verticalSpeedMps,
    required this.motorNormalizedRpm,
    required this.windVelocityWorld,
    required this.batteryPercent,
    required this.groundEffectFactor,
    required this.inVortexRingState,
    required this.isGrounded,
  });

  double get speedKmh => speedMps * 3.6;

  /// Bússola em graus [0, 360): 0° = Norte, 90° = Leste, 180° = Sul, 270° = Oeste.
  double get headingDegrees {
    final deg = (-yawRad * 180.0 / math.pi) % 360.0;
    return deg < 0 ? deg + 360.0 : deg;
  }
}

/// Controlador PID com filtro derivativo e anti-windup.
class _PidController {
  final double kp;
  final double ki;
  final double kd;
  final double integralLimit;
  final double outputLimit;

  double _integral = 0.0;
  double _prevError = 0.0;
  double _filteredDerivative = 0.0;
  bool _initialized = false;

  _PidController({
    required this.kp,
    required this.ki,
    required this.kd,
    required this.integralLimit,
    required this.outputLimit,
  });

  double update(double error, double dt) {
    if (dt <= 0.0) return 0.0;

    _integral = (_integral + error * dt).clamp(-integralLimit, integralLimit);

    double rawDeriv = 0.0;
    if (_initialized) {
      rawDeriv = (error - _prevError) / dt;
    } else {
      _initialized = true;
    }
    _prevError = error;

    // Filtro passa-baixa na derivada para evitar ruído em alta frequência.
    const alpha = 0.25;
    _filteredDerivative =
        _filteredDerivative * (1.0 - alpha) + rawDeriv * alpha;

    final out = kp * error + ki * _integral + kd * _filteredDerivative;
    return out.clamp(-outputLimit, outputLimit);
  }

  void reset() {
    _integral = 0.0;
    _prevError = 0.0;
    _filteredDerivative = 0.0;
    _initialized = false;
  }
}

/// Motor de Física 6-DOF profissional com sub-stepping a 240 Hz.
class QuadrotorPhysicsEngine {
  final DronePhysicsParams params;

  /// Passo fixo interno (240 Hz) para garantir estabilidade numérica dos PIDs.
  static const double _fixedSubstepDt = 1.0 / 240.0;

  Vec3 _position = Vec3.zero;
  Vec3 _velocity = Vec3.zero;
  Quat _orientation = Quat.identity;
  Vec3 _omegaBody = Vec3.zero;

  /// Velocidade angular atual de cada motor (rad/s): [FR, RL, FL, RR].
  final List<double> _motorOmega = <double>[0.0, 0.0, 0.0, 0.0];

  double _batteryPercent = 100.0;
  double _simTime = 0.0;
  double _accumulator = 0.0;
  bool _armed = false;
  bool _isGrounded = true;
  double _lastGroundEffect = 1.0;
  bool _inVrs = false;

  /// Vento base (m/s) + rajadas dinâmicas.
  Vec3 baseWindWorld;
  double turbulenceIntensity;

  // Controladores internos de taxa angular (Body frame: Pitch=X, Roll=Y, Yaw=Z).
  final _PidController _pitchRatePid = _PidController(
    kp: 0.22,
    ki: 0.14,
    kd: 0.016,
    integralLimit: 0.25,
    outputLimit: 0.45,
  );
  final _PidController _rollRatePid = _PidController(
    kp: 0.22,
    ki: 0.14,
    kd: 0.016,
    integralLimit: 0.25,
    outputLimit: 0.45,
  );
  final _PidController _yawRatePid = _PidController(
    kp: 0.55,
    ki: 0.15,
    kd: 0.015,
    integralLimit: 0.30,
    outputLimit: 0.40,
  );
  final _PidController _vzPid = _PidController(
    kp: 0.18,
    ki: 0.08,
    kd: 0.025,
    integralLimit: 0.25,
    outputLimit: 0.55,
  );

  QuadrotorPhysicsEngine({
    this.params = const DronePhysicsParams(),
    this.baseWindWorld = const Vec3(1.8, -0.9, 0.0),
    this.turbulenceIntensity = 1.0,
  });

  bool get isArmed => _armed;

  void setArmed(bool armed) {
    _armed = armed;
    if (!armed) {
      _resetControllers();
    }
  }

  void reset({
    Vec3 position = Vec3.zero,
    double yawRad = 0.0,
    double batteryPercent = 100.0,
  }) {
    _position = position;
    _velocity = Vec3.zero;
    _orientation = Quat.fromYaw(yawRad);
    _omegaBody = Vec3.zero;
    for (int i = 0; i < 4; i++) {
      _motorOmega[i] = 0.0;
    }
    _batteryPercent = batteryPercent.clamp(0.0, 100.0);
    _simTime = 0.0;
    _accumulator = 0.0;
    _isGrounded = position.z <= 0.02;
    _lastGroundEffect = 1.0;
    _inVrs = false;
    _resetControllers();
  }

  /// Permite que o sistema de colisões externo corrija posição/velocidade após impacto.
  void applyExternalCollisionCorrection({
    required Vec3 correctedPosition,
    required Vec3 correctedVelocity,
    Vec3? angularImpulseBody,
  }) {
    _position = correctedPosition;
    _velocity = correctedVelocity;
    if (angularImpulseBody != null) {
      _omegaBody = _omegaBody + angularImpulseBody;
    }
  }

  /// Avança a simulação usando o delta time do frame (com sub-stepping a 240 Hz).
  PhysicsSnapshot step({
    required PilotStickInput input,
    required double dt,
    FlightControlMode mode = FlightControlMode.stabilized,
    double groundHeightM = 0.0,
  }) {
    final clampedDt = dt.clamp(0.0, 0.05);
    _accumulator += clampedDt;

    while (_accumulator >= _fixedSubstepDt) {
      _stepSubstep(
        input: input,
        dt: _fixedSubstepDt,
        mode: mode,
        groundHeightM: groundHeightM,
      );
      _accumulator -= _fixedSubstepDt;
    }

    return snapshot;
  }

  PhysicsSnapshot get snapshot {
    final euler = _orientation.toEulerRadians();
    final wind = _computeWindWorld(_simTime, _position.z);
    return PhysicsSnapshot(
      position: _position,
      velocity: _velocity,
      orientation: _orientation,
      angularVelocityBody: _omegaBody,
      pitchRad: euler.pitch,
      rollRad: euler.roll,
      yawRad: euler.yaw,
      speedMps: _velocity.length,
      verticalSpeedMps: _velocity.z,
      motorNormalizedRpm: List<double>.unmodifiable(
        _motorOmega
            .map((w) => (w / params.maxMotorRadPerSec).clamp(0.0, 1.0)),
      ),
      windVelocityWorld: wind,
      batteryPercent: _batteryPercent,
      groundEffectFactor: _lastGroundEffect,
      inVortexRingState: _inVrs,
      isGrounded: _isGrounded,
    );
  }

  void _stepSubstep({
    required PilotStickInput input,
    required double dt,
    required FlightControlMode mode,
    required double groundHeightM,
  }) {
    _simTime += dt;

    // 1. Densidade do ar (ISA) e vento 3D com rajadas suaves.
    final altitudeM = math.max(0.0, _position.z);
    final densityRatio = math
        .pow((1.0 - 2.25577e-5 * altitudeM).clamp(0.2, 1.0), 4.25588)
        .toDouble();
    final airDensity = params.airDensitySeaLevel * densityRatio;
    final windWorld = _computeWindWorld(_simTime, altitudeM);

    // 2. Controlador de Voo -> comandos normalizados [0..1] para os 4 motores.
    final motorCmdNormalized = _computeFlightController(
      input: input,
      dt: dt,
      mode: mode,
      densityRatio: densityRatio,
    );

    // 3. Dinâmica de 1ª ordem dos motores (ESC + inércia das hélices) + queda de tensão.
    final voltageSagFactor = 0.86 + 0.14 * (_batteryPercent / 100.0);
    final effectiveMaxOmega = params.maxMotorRadPerSec * voltageSagFactor;

    for (int i = 0; i < 4; i++) {
      final targetOmega = _armed
          ? effectiveMaxOmega * math.sqrt(motorCmdNormalized[i].clamp(0.0, 1.0))
          : 0.0;
      final dOmega = (targetOmega - _motorOmega[i]) / params.motorTimeConstantSec;
      _motorOmega[i] = math.max(0.0, _motorOmega[i] + dOmega * dt);
    }

    // 4. Efeito Solo (Cheeseman-Bennett) e Vortex Ring State (VRS).
    final heightAboveGround = math.max(0.05, _position.z - groundHeightM);
    final ratioR4z = params.rotorRadiusM / (4.0 * heightAboveGround);
    _lastGroundEffect = (1.0 / (1.0 - math.min(0.32, ratioR4z * ratioR4z)))
        .clamp(1.0, 1.38);

    final horizSpeed =
        math.sqrt(_velocity.x * _velocity.x + _velocity.y * _velocity.y);
    double vrsFactor = 1.0;
    _inVrs = false;
    if (_velocity.z < -2.2 && horizSpeed < 3.0 && heightAboveGround > 1.5) {
      _inVrs = true;
      final severity = ((-_velocity.z - 2.2) / 4.5).clamp(0.0, 1.0);
      vrsFactor = 1.0 - 0.22 * severity;
    }

    // 5. Empuxos individuais e torques aerodinâmicos dos 4 rotores.
    final thrustScale = densityRatio * _lastGroundEffect * vrsFactor;
    final t0 = params.kT * _motorOmega[0] * _motorOmega[0] * thrustScale; // FR (CCW)
    final t1 = params.kT * _motorOmega[1] * _motorOmega[1] * thrustScale; // RL (CCW)
    final t2 = params.kT * _motorOmega[2] * _motorOmega[2] * thrustScale; // FL (CW)
    final t3 = params.kT * _motorOmega[3] * _motorOmega[3] * thrustScale; // RR (CW)

    final totalThrust = t0 + t1 + t2 + t3;
    final d = params.armOffsetXY;

    // Torques no referencial do corpo (X=Pitch, Y=Roll, Z=Yaw).
    final tauPitch = d * (t0 + t2 - t1 - t3);
    final tauRoll = d * (t1 + t2 - t0 - t3);
    final tauYaw = params.kQ *
        densityRatio *
        (_motorOmega[2] * _motorOmega[2] +
            _motorOmega[3] * _motorOmega[3] -
            _motorOmega[0] * _motorOmega[0] -
            _motorOmega[1] * _motorOmega[1]);

    // Precessão giroscópica dos rotores.
    final omegaNet =
        (_motorOmega[2] + _motorOmega[3]) - (_motorOmega[0] + _motorOmega[1]);
    final gyroTorque = Vec3(
      -_omegaBody.y * params.rotorInertia * omegaNet,
      _omegaBody.x * params.rotorInertia * omegaNet,
      0.0,
    );

    // Buffet turbulento no VRS.
    final vrsBuffet = _inVrs
        ? Vec3(
            0.09 * math.sin(_simTime * 19.3),
            0.09 * math.cos(_simTime * 23.1),
            0.03 * math.sin(_simTime * 13.7),
          )
        : Vec3.zero;

    // 6. Forças no referencial do mundo (Empuxo + Gravidade + Arrasto + Blade Flapping).
    final thrustWorld =
        _orientation.rotateBodyToWorld(Vec3(0.0, 0.0, totalThrust));
    final gravityWorld = Vec3(0.0, 0.0, -params.massKg * params.gravity);

    final vRelWorld = _velocity - windWorld;
    final vRelBody = _orientation.rotateWorldToBody(vRelWorld);

    // Arrasto parasita quadrático anisotrópico no corpo.
    final parasiticDragBody = Vec3(
      -0.5 * airDensity * params.dragAreaCdA.x * vRelBody.x * vRelBody.x.abs(),
      -0.5 * airDensity * params.dragAreaCdA.y * vRelBody.y * vRelBody.y.abs(),
      -0.5 * airDensity * params.dragAreaCdA.z * vRelBody.z * vRelBody.z.abs(),
    );

    // Arrasto induzido nas pás (Blade Flapping) no plano XY do corpo.
    final sumOmega =
        _motorOmega[0] + _motorOmega[1] + _motorOmega[2] + _motorOmega[3];
    final bladeDragBody = Vec3(
      -params.bladeFlappingDrag * sumOmega * vRelBody.x,
      -params.bladeFlappingDrag * sumOmega * vRelBody.y,
      0.0,
    );

    final aeroDragWorld =
        _orientation.rotateBodyToWorld(parasiticDragBody + bladeDragBody);

    final netForceWorld = thrustWorld + gravityWorld + aeroDragWorld;
    final accelWorld = netForceWorld / params.massKg;

    // 7. Dinâmica rotacional (Equação de Euler para corpo rígido):
    // I * dw/dt = tau - w x (I * w) - damping
    final iOmega = Vec3(
      params.inertia.x * _omegaBody.x,
      params.inertia.y * _omegaBody.y,
      params.inertia.z * _omegaBody.z,
    );
    final coriolis = _omegaBody.cross(iOmega);
    final dampingTorque = _omegaBody * (-params.angularDamping);
    final totalTorque =
        Vec3(tauPitch, tauRoll, tauYaw) + gyroTorque + dampingTorque + vrsBuffet - coriolis;

    final angularAccelBody = Vec3(
      totalTorque.x / params.inertia.x,
      totalTorque.y / params.inertia.y,
      totalTorque.z / params.inertia.z,
    );

    // 8. Integração Semi-Implícita de Euler (estável em 240 Hz).
    _velocity = _velocity + accelWorld * dt;
    _position = _position + _velocity * dt;

    _omegaBody = _omegaBody + angularAccelBody * dt;
    _orientation = _orientation.integrate(_omegaBody, dt);

    // 9. Contato com o solo (atrito, amortecimento e nivelamento dos skids).
    if (_position.z <= groundHeightM) {
      _position = Vec3(_position.x, _position.y, groundHeightM);
      if (_velocity.z < 0.0) {
        _velocity = Vec3(_velocity.x * 0.85, _velocity.y * 0.85, 0.0);
      }
      _omegaBody = _omegaBody * 0.7;
      // Nivela suavemente sobre o trem de pouso.
      final euler = _orientation.toEulerRadians();
      _orientation = Quat.fromYaw(euler.yaw);
      _isGrounded = true;
    } else {
      _isGrounded = false;
    }

    // 10. Descarga realista de bateria (Potência ~ soma(omega^3) + aviônica).
    if (_armed) {
      double mechPowerW = 0.0;
      for (int i = 0; i < 4; i++) {
        final norm = _motorOmega[i] / params.maxMotorRadPerSec;
        mechPowerW += 165.0 * norm * norm * norm;
      }
      const avionicsW = 12.0;
      final totalPowerW = mechPowerW + avionicsW;
      final whUsed = totalPowerW * (dt / 3600.0);
      _batteryPercent =
          (_batteryPercent - (whUsed / params.batteryCapacityWh) * 100.0)
              .clamp(0.0, 100.0);
      if (_batteryPercent <= 0.0) {
        _armed = false;
      }
    }
  }

  List<double> _computeFlightController({
    required PilotStickInput input,
    required double dt,
    required FlightControlMode mode,
    required double densityRatio,
  }) {
    if (!_armed) {
      return const <double>[0.0, 0.0, 0.0, 0.0];
    }

    final euler = _orientation.toEulerRadians();

    // Deadzone limpa nos sticks para evitar drift involuntário.
    double dz(double v) => v.abs() < 0.04 ? 0.0 : v.clamp(-1.0, 1.0);

    final stickThrottle = dz(input.throttle);
    final stickPitch = dz(input.pitch);
    final stickRoll = dz(input.roll);
    final stickYaw = dz(input.yaw);

    // Taxas angulares desejadas (rad/s) e empuxo coletivo normalizado (0..1).
    double targetPitchRate;
    double targetRollRate;
    double targetYawRate;
    double collectiveNormalized;

    switch (mode) {
      case FlightControlMode.stabilized:
      case FlightControlMode.sport:
        // Cascata de ângulo: stick define inclinação alvo, P converte em taxa.
        final maxTilt = mode == FlightControlMode.sport
            ? 45.0 * math.pi / 180.0
            : 30.0 * math.pi / 180.0;
        const angleGain = 3.4; // 1/s

        final targetPitch = -stickPitch * maxTilt; // +stick = nariz para baixo
        final targetRoll = stickRoll * maxTilt;

        targetPitchRate = (targetPitch - euler.pitch) * angleGain;
        targetRollRate = (targetRoll - euler.roll) * angleGain;
        targetYawRate = -stickYaw * 1.8;

        // Altitude Hold: throttle comanda razão de subida (neutro = manter).
        final targetVz = stickThrottle * 2.6;
        final vzCmd = _vzPid.update(targetVz - _velocity.z, dt);
        collectiveNormalized =
            (params.massKg * params.gravity / params.maxTotalThrustN) *
                (1.0 + vzCmd);
        break;

      case FlightControlMode.acro:
        // Taxas diretas: sem auto-nivelamento (permite flips completos).
        targetPitchRate = -stickPitch * 5.5;
        targetRollRate = stickRoll * 5.5;
        targetYawRate = -stickYaw * 3.0;

        // Throttle manual: -1 = motores em marcha lenta (gravidade domina).
        collectiveNormalized = (stickThrottle + 1.0) * 0.5;
        break;
    }

    // PIDs de taxa angular -> deltas normalizados do mixer.
    final pitchCmd = _pitchRatePid.update(targetPitchRate - _omegaBody.x, dt);
    final rollCmd = _rollRatePid.update(targetRollRate - _omegaBody.y, dt);
    final yawCmd = _yawRatePid.update(targetYawRate - _omegaBody.z, dt);

    final base = collectiveNormalized.clamp(0.0, 1.0);

    // Mixer em X (FR, RL, FL, RR) — consistente com os torques calculados:
    // tauPitch ∝ (t0+t2)-(t1+t3); tauRoll ∝ (t1+t2)-(t0+t3); tauYaw ∝ (t2+t3)-(t0+t1).
    final m0 = (base + pitchCmd - rollCmd - yawCmd).clamp(0.0, 1.0); // FR
    final m1 = (base - pitchCmd + rollCmd - yawCmd).clamp(0.0, 1.0); // RL
    final m2 = (base + pitchCmd + rollCmd + yawCmd).clamp(0.0, 1.0); // FL
    final m3 = (base - pitchCmd - rollCmd + yawCmd).clamp(0.0, 1.0); // RR

    return <double>[m0, m1, m2, m3];
  }

  void _resetControllers() {
    _pitchRatePid.reset();
    _rollRatePid.reset();
    _yawRatePid.reset();
    _vzPid.reset();
  }

  /// Vento 3D com rajadas suaves proporcionais à turbulência configurada.
  Vec3 _computeWindWorld(double t, double altitudeM) {
    final gust =
        turbulenceIntensity * (0.55 + 0.45 * math.sin(t * 0.37 + 0.6));
    return Vec3(
      baseWindWorld.x + gust * 0.55 * math.sin(t * 1.7),
      baseWindWorld.y + gust * 0.50 * math.cos(t * 1.3 + 0.4),
      baseWindWorld.z + gust * 0.18 * math.sin(t * 2.1),
    );
  }
}
