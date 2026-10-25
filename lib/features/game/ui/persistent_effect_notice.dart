import 'package:flutter/material.dart';
import '../../../engines/runtime/v4_runtime_engine.dart';
import 'resolution_wording.dart';

/// Presentation of the existing effect counter; it never ticks or stores it.
class PersistentEffectNotice extends StatelessWidget {
  const PersistentEffectNotice({
    required this.effect,
    required this.title,
    required this.duration,
    required this.wording,
    super.key,
  });
  final V4PersistentEffect effect;
  final String title;
  final int duration;
  final ResolutionWording wording;

  @override
  Widget build(BuildContext context) {
    final local = wording.localPlayerId;
    final period = effect.unit == 'turns' ? 'ce tour' : 'cette action';
    final String message;
    if (effect.cardId == '061') {
      message = effect.targetPlayerId == local
          ? 'Pendant $period, garde le silence.'
          : 'Pendant $period, ${wording.name(effect.targetPlayerId)} garde le silence.';
    } else if (effect.actorPlayerIds.contains(local)) {
      message = 'Pendant $period, continue « $title ».';
    } else if (effect.targetPlayerId == local) {
      message = 'Pendant $period, tu es toujours sous l’effet de « $title ».';
    } else {
      message =
          'Pendant $period, ${wording.name(effect.targetPlayerId)} reste sous l’effet de « $title ».';
    }
    final total = duration < 1 ? 1 : duration;
    final progress = (total - effect.remainingActions + 1).clamp(1, total);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Effet actif', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(message),
            const SizedBox(height: 4),
            Text('$progress/$total', textAlign: TextAlign.end),
          ],
        ),
      ),
    );
  }
}
