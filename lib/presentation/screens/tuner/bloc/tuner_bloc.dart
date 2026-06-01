import 'dart:async';
import 'dart:math';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/audio_constants.dart';
import '../../../../domain/entities/pitch_result.dart';
import '../../../../domain/entities/tuning_configuration.dart';
import '../../../../domain/enums/tuner_state.dart';
import 'tuner_event.dart';
import 'tuner_state.dart';

class TunerBloc extends Bloc<TunerEvent, TunerDisplayState>
    with WidgetsBindingObserver {
  TunerBloc() : super(const TunerInitial()) {
    WidgetsBinding.instance.addObserver(this);
    on<StartTuner>(_onStart);
    on<StopTuner>(_onStop);
    on<PitchReceived>(_onPitchReceived);
    // restartable() : si un nouveau ConfigChanged arrive pendant qu'un autre
    // est en cours de traitement (await cancel()), le précédent est annulé.
    // Rend l'intention explicite et protège contre tout refactoring futur
    // qui changerait le transformer par défaut.
    on<ConfigChanged>(_onConfigChanged, transformer: restartable());
    on<StringSelected>(_onStringSelected);
    on<IntelliTunerToggled>(_onIntelliTunerToggled);
    on<DebugCentsOverride>(_onDebugOverride);
  }

  StreamSubscription<_MockSample>? _subscription;
  TuningConfiguration _config = const TuningConfiguration();
  bool _intelliTunerEnabled = false;
  int _mockTick = 0;

  // ── Mock stream ──────────────────────────────────────────────────────────
  // Sera remplacé par AudioRepository.streamPitch() en Phase 9.
  Stream<_MockSample> _mockStream() {
    return Stream.periodic(
      const Duration(milliseconds: 16),
      (_) {
        final cents = sin(_mockTick++ * 0.04) * 35.0;
        return _MockSample(frequencyHz: 329.6 + cents * 0.19, centsDeviation: cents);
      },
    );
  }

  Future<void> _subscribe() async {
    await _subscription?.cancel();
    _subscription = null;
    _subscription = _mockStream().listen(
      (s) {
        if (!isClosed) add(PitchReceived(s.frequencyHz, s.centsDeviation, confidence: 0.95));
      },
      onError: (Object error, StackTrace stack) {
        if (!isClosed) add(const StopTuner());
      },
      cancelOnError: true,
    );
  }

  // ── Handlers ─────────────────────────────────────────────────────────────
  Future<void> _onStart(StartTuner _, Emitter<TunerDisplayState> emit) async {
    await _subscribe();
  }

  Future<void> _onStop(StopTuner _, Emitter<TunerDisplayState> emit) async {
    await _subscription?.cancel();
    _subscription = null;
    emit(const TunerInitial());
  }

  void _onPitchReceived(PitchReceived event, Emitter<TunerDisplayState> emit) {
    if (event.confidence < AudioConstants.minConfidence) return;
    emit(TunerListening(
      pitch: _pitchFromCents(event.frequencyHz, event.centsDeviation),
      config: _config,
      intelliTunerEnabled: _intelliTunerEnabled,
    ));
  }

  Future<void> _onConfigChanged(
    ConfigChanged event,
    Emitter<TunerDisplayState> emit,
  ) async {
    _config = event.config;
    await _subscribe();
  }

  void _onStringSelected(StringSelected event, Emitter<TunerDisplayState> emit) {
    _config = event.stringNote == null
        ? _config.copyWith(clearTargetString: true)
        : _config.copyWith(targetString: event.stringNote);
    if (state is TunerListening) {
      final s = state as TunerListening;
      emit(TunerListening(
        pitch: s.pitch,
        config: _config,
        intelliTunerEnabled: _intelliTunerEnabled,
      ));
    }
  }

  void _onIntelliTunerToggled(
    IntelliTunerToggled event,
    Emitter<TunerDisplayState> emit,
  ) {
    _intelliTunerEnabled = event.enabled;
    if (state is TunerListening) {
      final s = state as TunerListening;
      emit(TunerListening(
        pitch: s.pitch,
        config: _config,
        intelliTunerEnabled: _intelliTunerEnabled,
      ));
    }
  }

  // Suspend le mock et émet une valeur fixe pour le slider de debug.
  Future<void> _onDebugOverride(
    DebugCentsOverride event,
    Emitter<TunerDisplayState> emit,
  ) async {
    await _subscription?.cancel();
    _subscription = null;
    emit(TunerListening(
      pitch: _pitchFromCents(329.6, event.cents),
      config: _config,
      intelliTunerEnabled: _intelliTunerEnabled,
    ));
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  PitchResult _pitchFromCents(double hz, double cents) {
    final TunerState state;
    if (cents.abs() <= AudioConstants.inTuneThresholdCents) {
      state = TunerState.inTune;
    } else if (cents.abs() <= AudioConstants.nearTuneThresholdCents) {
      state = TunerState.nearTune;
    } else if (cents < 0) {
      state = TunerState.tooLow;
    } else {
      state = TunerState.tooHigh;
    }
    return PitchResult(
      frequencyHz: hz,
      noteName: 'E',
      octave: 4,
      centsDeviation: cents,
      confidence: 0.95,
      state: state,
    );
  }

  // ── Cycle de vie app ─────────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App en arrière-plan : couper le stream (Green IT + RGPD Phase 9).
      _subscription?.cancel();
      _subscription = null;
    } else if (state == AppLifecycleState.resumed &&
        this.state is TunerListening) {
      // this.state = état BLoC courant (TunerListening/TunerInitial)
      // state    = AppLifecycleState reçu en paramètre
      // Retour au premier plan : relancer uniquement si on était en écoute.
      _subscribe();
    }
  }

  @override
  Future<void> close() async {
    WidgetsBinding.instance.removeObserver(this);
    await _subscription?.cancel();
    return super.close();
  }
}

class _MockSample {
  const _MockSample({required this.frequencyHz, required this.centsDeviation});
  final double frequencyHz;
  final double centsDeviation;
}
