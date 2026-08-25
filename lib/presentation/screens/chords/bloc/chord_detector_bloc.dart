import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/chord_result.dart';
import '../../../../domain/exceptions/audio_permission_exception.dart';
import '../../../../domain/repositories/chord_repository.dart';
import 'chord_event.dart';
import 'chord_smoother.dart';
import 'chord_state.dart';

/// Miroir de `TunerBloc` : mêmes garde-fous de cycle de vie app (BUG-02) et
/// de sérialisation start/stop (BUG-03), branchés dès le premier commit —
/// cf. § 3.7 de `docs/STRATEGIE_DETECTION_ACCORDS.md`, contrairement au
/// Tuner où ces deux bugs ont dû être corrigés après coup.
class ChordDetectorBloc extends Bloc<ChordEvent, ChordDisplayState>
    with WidgetsBindingObserver {
  ChordDetectorBloc(this._chordRepository, {ChordSmoother? smoother})
    : _smoother = smoother ?? ChordSmoother(),
      super(const ChordInitial()) {
    WidgetsBinding.instance.addObserver(this);
    on<StartChordDetection>(_onStart);
    on<StopChordDetection>(_onStop);
    on<ChordReceived>(_onChordReceived);
    on<ChordPermissionDenied>(_onPermissionDenied);
  }

  final ChordRepository _chordRepository;
  final ChordSmoother _smoother;
  StreamSubscription<ChordResult>? _subscription;
  bool _wasListeningBeforePause = false;

  // Cf. TunerBloc._lifecycleLock : sérialise Start/Stop entre eux pour
  // éviter deux souscriptions actives en parallèle sur un changement
  // d'onglet rapide (isolate + capture micro orphelins).
  Future<void> _lifecycleLock = Future.value();

  Future<void> _guarded(Future<void> Function() action) {
    final result = _lifecycleLock.then<void>((_) async {
      if (isClosed) return;
      await action();
    });
    _lifecycleLock = result.catchError((_) {});
    return result;
  }

  Future<void> _subscribeToRepo() async {
    await _subscription?.cancel();
    _subscription = null;
    _subscription = _chordRepository
        .streamChord()
        .listen(
          (result) {
            if (!isClosed) add(ChordReceived(result));
          },
          onError: (Object error, StackTrace stack) {
            if (isClosed) return;
            if (error is AudioPermissionException) {
              add(ChordPermissionDenied(isPermanent: error.isPermanent));
            } else {
              add(const StopChordDetection());
            }
          },
          cancelOnError: true,
        );
  }

  // ── Handlers ─────────────────────────────────────────────────────────────

  Future<void> _onStart(
    StartChordDetection _,
    Emitter<ChordDisplayState> emit,
  ) => _guarded(_subscribeToRepo);

  Future<void> _onStop(
    StopChordDetection _,
    Emitter<ChordDisplayState> emit,
  ) => _guarded(() async {
    await _subscription?.cancel();
    _subscription = null;
    await _chordRepository.stop();
    if (!isClosed) emit(const ChordInitial());
  });

  void _onChordReceived(
    ChordReceived event,
    Emitter<ChordDisplayState> emit,
  ) {
    final smoothed = _smoother.push(event.result);
    emit(ChordListening(smoothed: smoothed));
  }

  void _onPermissionDenied(
    ChordPermissionDenied event,
    Emitter<ChordDisplayState> emit,
  ) {
    emit(ChordPermissionDeniedState(isPermanent: event.isPermanent));
  }

  // ── Cycle de vie app (miroir BUG-02) ─────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasListeningBeforePause = this.state is ChordListening;
      if (!isClosed) add(const StopChordDetection());
    } else if (state == AppLifecycleState.resumed &&
        _wasListeningBeforePause) {
      _wasListeningBeforePause = false;
      if (!isClosed) add(const StartChordDetection());
    }
  }

  @override
  Future<void> close() async {
    WidgetsBinding.instance.removeObserver(this);
    await _subscription?.cancel();
    await _chordRepository.stop();
    return super.close();
  }
}
