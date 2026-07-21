import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import '../../../domain/enums/instrument_type.dart';
import '../../../domain/repositories/tuning_profile_repository.dart';
import '../../../domain/validators/tuning_profile_validation_issue.dart';
import '../../../domain/validators/tuning_profile_validator.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'bloc/profile_editor_bloc.dart';
import 'bloc/profile_editor_event.dart';
import 'bloc/profile_editor_state.dart';

const Map<InstrumentType, String> _instrumentLabels = {
  InstrumentType.guitar: 'Guitare',
  InstrumentType.bass: 'Basse',
  InstrumentType.ukulele: 'Ukulélé',
  InstrumentType.custom: 'Personnalisé',
};

TuningProfileValidationIssue? _firstIssue(
  List<TuningProfileValidationIssue> issues,
  bool Function(TuningProfileValidationIssue) test,
) {
  for (final issue in issues) {
    if (test(issue)) return issue;
  }
  return null;
}

class ProfileEditorScreen extends StatelessWidget {
  const ProfileEditorScreen({super.key, required this.repository});

  final TuningProfileRepository repository;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ProfileEditorBloc(repository),
      child: const _ProfileEditorView(),
    );
  }
}

class _ProfileEditorView extends StatelessWidget {
  const _ProfileEditorView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Créer un profil', style: AppTextStyles.titleLarge),
      ),
      body: BlocConsumer<ProfileEditorBloc, ProfileEditorState>(
        listener: (context, state) {
          if (state is ProfileEditorSaved) {
            Navigator.of(context).pop();
          }
        },
        builder: (context, state) {
          final countIssue = _firstIssue(
            state.issues,
            (i) =>
                i.type == TuningProfileValidationErrorType.invalidStringCount,
          );

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _NameField(state: state),
                const Gap(16),
                _InstrumentTypeSelector(state: state),
                const Gap(24),
                Text(
                  'Cordes (référence + octave, ex: "E2")',
                  style: AppTextStyles.bodyLarge,
                ),
                const Gap(8),
                for (var i = 0; i < state.draft.stringNotes.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _StringNoteField(index: i, state: state),
                  ),
                if (countIssue != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      countIssue.message,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.tooHigh,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    if (state.draft.stringNotes.length <
                        TuningProfileValidator.maxStringCount)
                      TextButton.icon(
                        onPressed: () => context.read<ProfileEditorBloc>().add(
                          const StringAdded(),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Ajouter une corde'),
                      ),
                  ],
                ),
                const Gap(24),
                FilledButton(
                  onPressed: () => context.read<ProfileEditorBloc>().add(
                    const SaveProfile(),
                  ),
                  child: const Text('Enregistrer le profil'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.state});

  final ProfileEditorState state;

  @override
  Widget build(BuildContext context) {
    final issue = _firstIssue(
      state.issues,
      (i) =>
          i.type == TuningProfileValidationErrorType.invalidNameLength ||
          i.type == TuningProfileValidationErrorType.duplicateName,
    );

    return TextFormField(
      key: ValueKey('name-${state.draft.id}'),
      initialValue: state.draft.name,
      style: AppTextStyles.bodyLarge,
      decoration: InputDecoration(
        labelText: 'Nom du profil (ex: "Open G Keith Richards")',
        errorText: issue?.message,
      ),
      onChanged: (value) =>
          context.read<ProfileEditorBloc>().add(ProfileNameChanged(value)),
    );
  }
}

class _InstrumentTypeSelector extends StatelessWidget {
  const _InstrumentTypeSelector({required this.state});

  final ProfileEditorState state;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<InstrumentType>(
      initialValue: state.draft.instrumentType,
      dropdownColor: AppColors.surfaceHigh,
      style: AppTextStyles.bodyLarge,
      decoration: const InputDecoration(labelText: 'Instrument'),
      items: [
        for (final type in InstrumentType.values)
          DropdownMenuItem(value: type, child: Text(_instrumentLabels[type]!)),
      ],
      onChanged: (type) {
        if (type == null) return;
        context.read<ProfileEditorBloc>().add(
          ProfileInstrumentTypeChanged(type),
        );
      },
    );
  }
}

class _StringNoteField extends StatelessWidget {
  const _StringNoteField({required this.index, required this.state});

  final int index;
  final ProfileEditorState state;

  @override
  Widget build(BuildContext context) {
    final issue = _firstIssue(state.issues, (i) => i.stringIndex == index);
    final canRemove =
        state.draft.stringNotes.length > TuningProfileValidator.minStringCount;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            key: ValueKey('string-${state.draft.id}-$index'),
            initialValue: state.draft.stringNotes[index],
            style: AppTextStyles.mono,
            decoration: InputDecoration(
              labelText: 'Corde ${index + 1}',
              errorText: issue?.message,
            ),
            onChanged: (value) => context.read<ProfileEditorBloc>().add(
              StringNoteChanged(index: index, note: value),
            ),
          ),
        ),
        if (canRemove)
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            color: AppColors.textSecondary,
            onPressed: () =>
                context.read<ProfileEditorBloc>().add(StringRemoved(index)),
          ),
      ],
    );
  }
}
