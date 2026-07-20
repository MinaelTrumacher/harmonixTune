import 'package:equatable/equatable.dart';

import '../../../../domain/entities/tuning_profile.dart';
import '../../../../domain/validators/tuning_profile_validation_issue.dart';

sealed class ProfileEditorState extends Equatable {
  const ProfileEditorState({required this.draft, required this.issues});

  final TuningProfile draft;
  final List<TuningProfileValidationIssue> issues;

  @override
  List<Object?> get props => [draft, issues];
}

// Brouillon en cours d'édition. `issues` n'est renseigné qu'après une
// tentative de sauvegarde refusée par le Domaine (pas de validation à
// chaque frappe, pour ne pas harceler l'utilisateur pendant la saisie).
final class ProfileEditorEditing extends ProfileEditorState {
  const ProfileEditorEditing({required super.draft, super.issues = const []});
}

// Sauvegarde réussie — le profil est immédiatement disponible hors-ligne.
final class ProfileEditorSaved extends ProfileEditorState {
  const ProfileEditorSaved({required super.draft}) : super(issues: const []);
}
