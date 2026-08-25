import 'package:flutter/material.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';

class ProfileProviderIcon extends StatelessWidget {
  const ProfileProviderIcon({required this.toolKey, this.size = 20, super.key});

  final String toolKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final provider = profileProvider(toolKey);
    return Semantics(
      image: true,
      label: provider.productName,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * .22),
        child: Image.asset(
          provider.iconAssetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.smart_toy_outlined,
            size: size,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
