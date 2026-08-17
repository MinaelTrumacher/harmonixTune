import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../domain/entities/tuning_profile.dart';
import '../../../domain/repositories/tuning_profile_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'profile_editor_screen.dart';

const Map<String, String> _instrumentLabels = {
  'guitar': 'Guitare',
  'bass': 'Basse',
  'ukulele': 'Ukulélé',
  'custom': 'Personnalisé',
};

class PresetsScreen extends StatelessWidget {
  const PresetsScreen({super.key, required this.repository});

  final TuningProfileRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder<List<TuningProfile>>(
          stream: repository.watchAll(),
          builder: (context, snapshot) {
            final profiles = snapshot.data ?? const [];
            if (profiles.isEmpty) {
              return _EmptyState(repository: repository);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: profiles.length,
              separatorBuilder: (_, _) => const Gap(8),
              itemBuilder: (context, index) => _ProfileTile(
                profile: profiles[index],
                repository: repository,
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProfileEditorScreen(repository: repository),
          ),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.repository});

  final TuningProfileRepository repository;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.library_music_outlined,
              size: 64,
              color: AppColors.textDisabled,
            ),
            const Gap(16),
            Text(
              'Aucun profil d\'accordage',
              style: AppTextStyles.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              'Créez votre premier profil personnalisé — il reste disponible '
              'même sans connexion Internet.',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.profile, required this.repository});

  final TuningProfile profile;
  final TuningProfileRepository repository;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.name, style: AppTextStyles.bodyLarge),
                const Gap(4),
                Text(
                  '${_instrumentLabels[profile.instrumentType.name] ?? profile.instrumentType.name} · '
                  '${profile.stringNotes.join(' - ')}',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: AppColors.textSecondary,
            onPressed: () => repository.delete(profile.id),
          ),
        ],
      ),
    );
  }
}
