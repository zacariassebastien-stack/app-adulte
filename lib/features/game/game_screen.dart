import 'package:flutter/material.dart';

import '../../domain/game/game_screen_data.dart';

/// Game layout with local-only hand interactions. Selection and locking are
/// deliberately not connected to gameplay engines yet.
class GameScreen extends StatefulWidget {
  const GameScreen({
    required this.data,
    this.privacyTransition = false,
    this.temporarilyUnavailableCardIds = const {},
    this.onCardSelected,
    super.key,
  });

  final GameScreenData data;
  final bool privacyTransition;
  final Set<String> temporarilyUnavailableCardIds;
  final ValueChanged<GameCardView>? onCardSelected;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  String? _lockedCardId;
  String? _selectedCardId;
  bool _detailOpen = false;

  bool get _hidePrivateData =>
      widget.privacyTransition || widget.data.privateDataHidden;

  @override
  void initState() {
    super.initState();
    _lockedCardId = widget.data.hand
        .where((card) => card.locked)
        .firstOrNull
        ?.cardId;
  }

  @override
  void didUpdateWidget(covariant GameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hidePrivateData && _detailOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _detailOpen) Navigator.of(context).maybePop();
      });
    }
  }

  Future<void> _openCard(GameCardView card) async {
    if (_hidePrivateData) return;
    _detailOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final locked = _lockedCardId == card.cardId;
          final unavailable = widget.temporarilyUnavailableCardIds.contains(
            card.cardId,
          );
          return _CardDetail(
            card: card,
            locked: locked,
            unavailable: unavailable,
            selected: _selectedCardId == card.cardId,
            onToggleLock: () {
              if (_hidePrivateData) return;
              setState(() => _lockedCardId = locked ? null : card.cardId);
              setSheetState(() {});
            },
            onSelect: unavailable || _hidePrivateData
                ? null
                : () {
                    setState(() => _selectedCardId = card.cardId);
                    widget.onCardSelected?.call(card);
                    Navigator.of(sheetContext).pop();
                  },
          );
        },
      ),
    );
    _detailOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GameHeader(data: widget.data, hidePrivateData: _hidePrivateData),
              const SizedBox(height: 10),
              Expanded(
                child: _CentralArea(
                  action: widget.data.centralActions.firstOrNull,
                  hidePrivateData: _hidePrivateData,
                ),
              ),
              const SizedBox(height: 10),
              _DiscardAccess(count: widget.data.discard.length),
              const SizedBox(height: 10),
              SizedBox(
                height: 168,
                child: _hidePrivateData
                    ? const _PrivacyPlaceholder()
                    : _PlayerHand(
                        cards: widget.data.hand,
                        lockedCardId: _lockedCardId,
                        selectedCardId: _selectedCardId,
                        unavailableCardIds:
                            widget.temporarilyUnavailableCardIds,
                        onCardTap: _openCard,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameHeader extends StatelessWidget {
  const _GameHeader({required this.data, required this.hidePrivateData});

  final GameScreenData data;
  final bool hidePrivateData;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _HeaderMetric(
          key: const Key('action-points'),
          icon: Icons.bolt_rounded,
          label: 'PA',
          value: hidePrivateData ? '—' : '${data.actionPoints ?? '—'}',
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _HeaderMetric(
          key: const Key('session-timer'),
          icon: Icons.timer_outlined,
          label: 'Temps',
          value: _duration(data.elapsedSeconds),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _HeaderMetric(
          key: const Key('active-chili'),
          icon: Icons.local_fire_department_outlined,
          label: 'Niveau',
          value: '🌶️ ${data.chiliActive}',
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filledTonal(
        key: const Key('settings-button'),
        tooltip: 'Réglages',
        onPressed: () {},
        icon: const Icon(Icons.settings_outlined),
      ),
    ],
  );

  static String _duration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 80;
      return Container(
        height: 58,
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: compact
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, semanticLabel: label),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      );
    },
  );
}

class _CentralArea extends StatelessWidget {
  const _CentralArea({required this.action, required this.hidePrivateData});

  final GameCardView? action;
  final bool hidePrivateData;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: action == null
          ? const Center(child: Text('Action révélée'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: GameCard(
                  card: action!,
                  prominent: true,
                  hidePersonalValue: hidePrivateData,
                ),
              ),
            ),
    ),
  );
}

class _DiscardAccess extends StatelessWidget {
  const _DiscardAccess({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const Key('discard-button'),
    onPressed: () {},
    icon: const Icon(Icons.layers_outlined),
    label: Text('Défausse · $count carte${count > 1 ? 's' : ''}'),
  );
}

class _PlayerHand extends StatelessWidget {
  const _PlayerHand({
    required this.cards,
    required this.lockedCardId,
    required this.selectedCardId,
    required this.unavailableCardIds,
    required this.onCardTap,
  });

  final List<GameCardView> cards;
  final String? lockedCardId, selectedCardId;
  final Set<String> unavailableCardIds;
  final ValueChanged<GameCardView> onCardTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Ma main · ${cards.length}/4',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 6),
      Expanded(
        child: Row(
          key: const Key('player-hand'),
          children: [
            for (var index = 0; index < 4; index++) ...[
              if (index > 0) const SizedBox(width: 6),
              Expanded(
                child: index < cards.length
                    ? Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: Key('hand-card-$index'),
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => onCardTap(cards[index]),
                          child: GameCard(
                            card: cards[index],
                            compact: true,
                            locked: lockedCardId == cards[index].cardId,
                            selected: selectedCardId == cards[index].cardId,
                            unavailable: unavailableCardIds.contains(
                              cards[index].cardId,
                            ),
                          ),
                        ),
                      )
                    : const _EmptyHandSlot(),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _EmptyHandSlot extends StatelessWidget {
  const _EmptyHandSlot();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: const Center(child: Icon(Icons.add, size: 20)),
  );
}

class _PrivacyPlaceholder extends StatelessWidget {
  const _PrivacyPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('privacy-placeholder'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.phonelink_lock_outlined, size: 34),
        const SizedBox(height: 8),
        Text(
          'Passe le téléphone à ton partenaire',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text('Tes cartes et informations privées sont masquées.'),
      ],
    ),
  );
}

class _CardDetail extends StatelessWidget {
  const _CardDetail({
    required this.card,
    required this.locked,
    required this.unavailable,
    required this.selected,
    required this.onToggleLock,
    required this.onSelect,
  });

  final GameCardView card;
  final bool locked, unavailable, selected;
  final VoidCallback onToggleLock;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final description = card.descriptionKey ?? 'Description à venir';
    final chili = card.chiliLevels.isEmpty
        ? 'Non précisé'
        : card.chiliLevels.map((level) => '🌶️ $level').join('  ');
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: SingleChildScrollView(
        key: const Key('card-detail-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    card.category,
                    key: const Key('detail-category'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(
                  locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  key: const Key('detail-lock-status'),
                  semanticLabel: locked ? 'Verrouillée' : 'Déverrouillée',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              key: const Key('detail-illustration'),
              height: 220,
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.image_outlined,
                size: 68,
                color: colors.onSecondaryContainer.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              card.titleKey ?? 'Carte',
              key: const Key('detail-title'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              key: const Key('detail-description'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  key: const Key('detail-chili'),
                  avatar: const Icon(Icons.local_fire_department_outlined),
                  label: Text(chili),
                ),
                if (card.personalValue != null)
                  Chip(
                    key: const Key('detail-personal-value'),
                    avatar: const Icon(Icons.favorite_outline),
                    label: Text('${card.personalValue}/20'),
                  ),
                Chip(
                  key: const Key('detail-lock-label'),
                  avatar: Icon(
                    locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  ),
                  label: Text(locked ? 'Verrouillée' : 'Déverrouillée'),
                ),
              ],
            ),
            if (unavailable) ...[
              const SizedBox(height: 14),
              Container(
                key: const Key('unavailable-explanation'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Cette carte n'est pas disponible dans la situation actuelle.",
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (card.instructionKeys.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'En savoir plus',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              for (final information in card.instructionKeys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(information),
                ),
            ],
            const SizedBox(height: 22),
            OutlinedButton.icon(
              key: const Key('lock-card-button'),
              onPressed: onToggleLock,
              icon: Icon(locked ? Icons.lock_open_rounded : Icons.lock_rounded),
              label: Text(
                locked ? 'Déverrouiller la carte' : 'Verrouiller la carte',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('choose-card-button'),
              onPressed: onSelect,
              child: Text(
                selected ? 'Carte sélectionnée' : 'Choisir cette carte',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GameCard extends StatelessWidget {
  const GameCard({
    required this.card,
    this.compact = false,
    this.prominent = false,
    this.hidePersonalValue = false,
    this.locked,
    this.selected = false,
    this.unavailable = false,
    super.key,
  });

  final GameCardView card;
  final bool compact, prominent, hidePersonalValue;
  final bool? locked;
  final bool selected, unavailable;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = card.titleKey ?? 'Carte';
    final description =
        card.descriptionKey ??
        card.instructionKeys.firstOrNull ??
        'Description à venir';
    final chili = card.chiliLevels.isEmpty ? '—' : card.chiliLevels.join(' · ');
    final isLocked = locked ?? card.locked;
    return Opacity(
      opacity: unavailable ? 0.48 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(prominent ? 22 : 14),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 3 : 1,
          ),
          boxShadow: prominent
              ? [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.all(compact ? 7 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      card.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      key: Key('card-selected-${card.cardId}'),
                      size: compact ? 15 : 20,
                      color: colors.primary,
                      semanticLabel: 'Carte sélectionnée',
                    ),
                  if (isLocked)
                    Icon(
                      Icons.lock_rounded,
                      key: Key('card-lock-${card.cardId}'),
                      size: compact ? 15 : 20,
                      semanticLabel: 'Carte verrouillée',
                    ),
                ],
              ),
              SizedBox(height: compact ? 4 : 8),
              Expanded(
                flex: prominent ? 3 : 2,
                child: Container(
                  key: Key('illustration-${card.cardId}'),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(compact ? 8 : 14),
                  ),
                  child: Icon(
                    Icons.image_outlined,
                    size: compact ? 22 : 42,
                    color: colors.onSecondaryContainer.withValues(alpha: 0.55),
                  ),
                ),
              ),
              SizedBox(height: compact ? 4 : 8),
              Text(
                title,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style:
                    (compact
                            ? Theme.of(context).textTheme.labelMedium
                            : Theme.of(context).textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (!compact) ...[
                const SizedBox(height: 3),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              SizedBox(height: compact ? 3 : 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '🌶️ $chili',
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    if (!hidePersonalValue && card.personalValue != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${card.personalValue}/20',
                        key: Key('personal-value-${card.cardId}'),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
