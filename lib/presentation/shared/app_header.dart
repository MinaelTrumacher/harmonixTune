import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({super.key, this.title = 'harmonixTune', this.onSettingsTap});

  final String title;
  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.primary,
              letterSpacing: -0.5,
            ),
          ),
          IconButton(
            onPressed: onSettingsTap,
            icon: const Icon(Icons.settings_outlined),
            color: AppColors.textSecondary,
            iconSize: 22,
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}
