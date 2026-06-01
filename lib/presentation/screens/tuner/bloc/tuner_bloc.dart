import 'dart:async';
import 'dart:math';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/audio_constants.dart';
import '../../../../domain/entities/pitch_result.dart';
import '../../../../domain/entities/tuning_configuration.dart';
import '../../../../domain/enums/tuner_state.dart';
import '../../../../domain/exceptions/audio_permission_exception.dart';
import '../../../../domain/repositories/audio_repository.dart';
import 'tuner_event.dart';
import 'tuner_state.dart';

class TunerBloc extends Bloc<TunerEvent, TunerDisplayState>
    with WidgetsBindingObserver {
  TunerBloc(this._audioRepository) : super(const TunerInitial()) {
    WidgetsBinding.instance.addObserver(this);
    on<StartTuner>(_onStart);
    on<StopTuner>(_onStop);
    on<PitchReceived>(_onPitchReceived);
    on<PermissionDenied>(_onPermissionDenied);
    on<ConfigChanged>(_onConfigChanged, transformer: restartable());
    on<StringSelected>(_onStringSelected);
    on<IntelliTunerToggled>(_onIntelliTunerToggled);
    on<DebugCentsOverride>(_onDebugOverride);
  }

  final AudioRepository _audioRepository;
  StreamSubscription<PitchResult>? _subscription;
  TuningConfiguration _config = const TuningConfiguration();
  bool _intelliTunerEnabled = false;

  // ── Souscription au repo audio ────────────────────────────────────────────

  Future<void> _subscribeToRepo() async {
    await _subscription?.cancel();
    _subscription = null;
    _subscription = _audioRepository.streamPitch(_config).listen(
      (result) {
        if (!isClosed) add(PitchReceived(result));
      },
      onError: (Object error, StackTrace stack) {
        if (isClosed) return;
        if (error is AudioPermissionException) {
          add(PermissionDenied(isPermanent: error.isPermanent));
        } else {
          add(const StopTuner());
        }
      },
      cancelOnError: true,
    );
  }

  // ── Handlers ─────────────────────────────────────────────────────────────

  Future<void> _onStart(StartTuner _, Emitter<TunerDisplayState> emit) async {
    await _subscribeToRepo();
  }

  Future<void> _onStop(StopTuner _, Emitter<TunerDisplayState> emit) async {
    await _subscription?.cancel();
    _subscription = null;
    await _audioRepository.stop();
    emit(const TunerInitial());
  }

  void _onPitchReceived(
    PitchReceived event,
    Emitter<TunerDisplayState> emit,
  ) {
    final result = event.result;

    // Scénario A2 — auto-activation Intelli-Tuner :
    // Mode MANUEL + confiance insuffisante → activer le filtre IIR.
    if (_config.targetString != null &&
        result.confidence < AudioConstants.minConfidence &&
        !_intelliTunerEnabled) {
      _intelliTunerEnabled = true;
      _audioRepository.updateConfig(
        _config.copyWith(intelliTunerActive: true),
      );
    }

    emit(TunerListening(
      pitch: result,
      config: _config,
      intelliTunerEnabled: _intelliTunerEnabled,
    ));
  }

  void _onPermissionDenied(
    PermissionDenied event,
    Emitter<TunerDisplayState> emit,
  ) {
    emit(TunerPermissionDeniedState(isPermanent: event.isPermanent));
  }

  Future<void> _onConfigChanged(
    ConfigChanged event,
    Emitter<TunerDisplayState> emit,
  ) async {
    _config = event.config;
    await _subscribeToRepo();
  }

  void _onStringSelected(
    StringSelected event,
    Emitter<TunerDisplayState> emit,
  ) {
    _config = event.stringNote == null
        ? _config.copyWith(clearTargetString: true, intelliTunerActive: false)
        : _config.copyWith(targetString: event.stringNote);
    if (event.stringNote == null) _intelliTunerEnabled = false;

    if (state is TunerListening) {
      emit(TunerListening(
        pitch: (state as TunerListening).pitch,
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
    _config = _config.copyWith(intelliTunerActive: event.enabled);
    _audioRepository.updateConfig(_config);

    if (state is TunerListening) {
      emit(TunerListening(
        pitch: (state as TunerListening).pitch,
        config: _config,
        intelliTunerEnabled: _intelliTunerEnabled,
      ));
    }
  }

  // Suspendu le stream et émet une valeur fixe (slider debug uniquement).
  Future<void> _onDebugOverride(
    DebugCentsOverride event,
    Emitter<TunerDisplayState> emit,
  ) async {
    await _subscription?.cancel();
    _subscription = null;
    await _audioRepository.stop();
    emit(TunerListening(
      pitch: _pitchFromCents(329.6, event.cents),
      config: _config,
      intelliTunerEnabled: _intelliTunerEnabled,
    ));
  }

  // ── Cycle de vie app (Scénario A3) ───────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `state` ici = AppLifecycleState (paramètre).
    // `this.state` = TunerDisplayState courant du BLoC.
    if (state == AppLifecycleState.paused) {
      if (!isClosed) add(const StopTuner());
    } else if (state == AppLifecycleState.resumed && this.state is TunerListening) {
      if (!isClosed) add(const StartTuner());
    }
  }

  @override
  Future<void> close() async {
    WidgetsBinding.instance.removeObserver(this);
    await _subscription?.cancel();
    await _audioRepository.stop();
    return super.close();
  }

  // ── Helper debug ──────────────────────────────────────────────────────────

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

  // ignore: unused_field — conservé pour la lisibilité de la formule debug
  static final double _unused = sin(0);
}
