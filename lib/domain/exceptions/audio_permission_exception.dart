class AudioPermissionException implements Exception {
  const AudioPermissionException({this.isPermanent = false});

  final bool isPermanent;

  @override
  String toString() => isPermanent
      ? 'AudioPermissionException: permission microphone refusée définitivement'
      : 'AudioPermissionException: permission microphone refusée';
}
