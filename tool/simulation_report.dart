import 'dart:convert';
import 'dart:io';

/// Render measured values only. Design interpretation lives in phase4_simulation.md.
void main(List<String> args) {
  final input = args.isEmpty ? 'docs/simulation_baseline.json' : args[0];
  final output = args.length < 2 ? 'docs/simulation_baseline.md' : args[1];
  final report =
      jsonDecode(File(input).readAsStringSync()) as Map<String, Object?>;
  final m = report['metrics'] as Map<String, Object?>;
  final c = m['counters'] as Map<String, Object?>;
  final d = m['distributions'] as Map<String, Object?>;
  final f = m['frequencies'] as Map<String, Object?>;
  num n(String k) => c[k] as num? ?? 0;
  String fmt(Object? v) => v == null
      ? '—'
      : v is double
      ? v.toStringAsFixed(3)
      : '$v';
  String stat(String k, [String field = 'mean']) =>
      fmt((d[k] as Map<String, Object?>?)?[field]);
  String pct(Object? numerator, Object? denominator) {
    final a = numerator as num? ?? 0, b = denominator as num? ?? 0;
    return b == 0 ? '—' : '${(100 * a / b).toStringAsFixed(2)} %';
  }

  final out = StringBuffer('# Phase 4 — rapport BASELINE\n\n');
  out.writeln('## MESURE\n');
  out.writeln(
    '${report['sessions']} sessions synthétiques ; seeds ${report['seedStart']}–${report['seedEndInclusive']}. '
    '${(report['scenarios'] as List).length} scénarios, allocation cyclique. Moteur `${report['engineCommit']}`.',
  );
  out.writeln(
    '\nDurée : ${((report['execution']['elapsedMilliseconds'] as num) / 1000).toStringAsFixed(3)} s '
    '(exécutable Dart, ${report['execution']['os']}, hors compilation et écriture JSON).',
  );
  out.writeln(
    '\nLimites : `${jsonEncode(report['limits'])}`. ${n('duels')} duels résolus ; '
    '${n('round.renounced')} rounds renoncés. Arrêts techniques : `${jsonEncode(f['termination'])}`.',
  );
  out.writeln(
    '\nParamètres, probabilités, profils synthétiques et toutes les distributions : '
    '[JSON complet](simulation_baseline.json). Protocole, dénominateurs et limites : '
    '[documentation Phase 4](phase4_simulation.md).',
  );
  out.writeln(
    '\n### PA\n\n| Joueur | PA initial | PA final moyen / médian | Minimum / maximum observés | Duels avant 50 % (moyenne / médiane ; n) | Avant 20 % | Avant 0 |\n|---|---:|---:|---:|---:|---:|---:|',
  );
  for (final id in ['a', 'b']) {
    String threshold(int v) =>
        '${stat('pa.$id.duelsTo$v')} / ${stat('pa.$id.duelsTo$v', 'median')} ; ${stat('pa.$id.duelsTo$v', 'count')}';
    out.writeln(
      '| $id | ${stat('pa.$id.initial')} | ${stat('pa.$id.final')} / ${stat('pa.$id.final', 'median')} | '
      '${stat('pa.$id.allRounds', 'min')} / ${stat('pa.$id.allRounds', 'max')} | ${threshold(50)} | ${threshold(20)} | ${threshold(0)} |',
    );
  }
  out.writeln(
    '\nLes seuils sont conditionnels aux joueurs qui les atteignent. Les autres sont censurés, jamais comptés comme zéro. '
    'Les moyennes par round ci-dessous ne portent que sur les sessions encore observables.',
  );
  out.writeln(
    '\n| Round | PA A moyen / médian | PA B moyen / médian | n A | 🌶️ moyen |\n|---:|---:|---:|---:|---:|',
  );
  for (var r = 1; r <= (report['limits']['maxRounds'] as int); r++) {
    out.writeln(
      '| $r | ${stat('pa.a.afterRound.$r')} / ${stat('pa.a.afterRound.$r', 'median')} | '
      '${stat('pa.b.afterRound.$r')} / ${stat('pa.b.afterRound.$r', 'median')} | ${stat('pa.a.afterRound.$r', 'count')} | ${stat('chili.afterRound.$r')} |',
    );
  }
  out.writeln('\n| Dépenses / gains totaux | A | B |\n|---|---:|---:|');
  for (final key in [
    'duelSpent',
    'duelPayments',
    'auctionSpent',
    'chiliSpent',
    'recoveryGain',
    'extensionGain',
  ]) {
    out.writeln('| $key | ${n('pa.a.$key')} | ${n('pa.b.$key')} |');
  }
  out.writeln('\nExtensions mutuelles : ${n('extensions')}.');
  out.writeln('\n### Duels et enchères\n');
  out.writeln(
    'Écart moyen / médian : ${stat('duel.gap')} / ${stat('duel.gap', 'median')}. '
    'Coût moyen / maximal : ${stat('duel.cost')} / ${stat('duel.cost', 'max')}. '
    'Cap théorique atteint : ${pct(n('duel.cap'), n('duels'))}. '
    'Égalités : ${pct(n('duel.ties'), n('duels'))}. Gagnant à zéro après le duel : ${pct(n('duel.winnerAtZero'), n('duels'))}.',
  );
  out.writeln('\n| Écart | Nombre |\n|---:|---:|');
  for (var g = 0; g < 20; g++) {
    out.writeln('| $g | ${d['duel.gap']?['distribution']?['$g'] ?? 0} |');
  }
  out.writeln(
    '\nContre-enchère : ${pct(n('auction.counter'), n('duels'))} des duels. '
    'Défense finale : ${pct(n('auction.defense'), n('duels'))} des duels. '
    'Renversement : ${pct(n('auction.reversal'), n('auction.counter'))} des enchères ; '
    'échec de l’initiateur : ${pct(n('auction.initiatorFailed'), n('auction.counter'))}. '
    'PA totaux par enchère, moyenne / médiane : ${stat('auction.totalSpent')} / ${stat('auction.totalSpent', 'median')}. '
    'Mise maximale : ${stat('auction.bid', 'max')}. Inversions effectivement retenues : ${n('auction.inversion')}.',
  );
  final auctionSpent = n('pa.a.auctionSpent') + n('pa.b.auctionSpent');
  final spending =
      auctionSpent +
      n('pa.a.duelSpent') +
      n('pa.b.duelSpent') +
      n('chili.spent');
  out.writeln(
    '\nPart des enchères dans les dépenses : ${pct(auctionSpent, spending)}. '
    'Repères descriptifs, sans jugement : quasi inexistante < 5 % des duels ; quasi systématique > 90 % ; '
    'majoritaire économiquement > 50 % des dépenses. Comparer les scénarios ci-dessous.',
  );
  out.writeln(
    '\n### Recovery\n\n| Mesure | Moyenne | Médiane | Maximum |\n|---|---:|---:|---:|',
  );
  for (final k in ['perSession', 'firstRound', 'before', 'gain', 'after']) {
    out.writeln(
      '| $k | ${stat('recovery.$k')} | ${stat('recovery.$k', 'median')} | ${stat('recovery.$k', 'max')} |',
    );
  }
  final recoveries = (d['recovery.gain']?['count'] ?? 0) as num;
  out.writeln(
    '\n${fmt(recoveries)} tentatives, refus ${pct(n('recovery.refused'), recoveries)}, '
    'conditions ${pct(n('recovery.conditions'), recoveries)}, dépassement PA initiaux ${pct(n('recovery.aboveInitial'), recoveries)}. '
    '${n('recovery.exhausted')} actions du discard épuisées. '
    '${n('recovery.higherChiliCompleted')} actions principales réalisées au-dessus du niveau actif '
    'sur ${n('recovery.higherChiliProposed')} proposées. '
    '${n('signal.recoveryOffsetsAllSpending')} sessions avec au moins 10 Recovery et gains Recovery couvrant toutes les dépenses. '
    'Ce signal ne prouve pas une boucle exploitable.',
  );
  out.writeln(
    '\n### Intensité\n\nPropositions de montée : ${n('chili.proposals')} ; acceptées et payables : ${n('chili.accepted')} ; '
    'refusées : ${n('chili.refused')} ; inabordables : ${n('chili.unaffordable')}. '
    'Coût total : ${n('chili.spent')} PA. Baisses mutuellement convenues : ${n('chili.lowered')} ; remontées gratuites : ${n('chili.freeReturn')}.',
  );
  out.writeln(
    '\n| Niveau | Sessions ayant accédé | Part | Premier round moyen |\n|---:|---:|---:|---:|',
  );
  for (var l = 1; l <= 5; l++) {
    final count = (d['chili.firstAt$l']?['count'] ?? 0) as num;
    out.writeln(
      '| $l | $count | ${pct(count, report['sessions'] as num)} | ${stat('chili.firstAt$l')} |',
    );
  }
  final diversity = m['diversity'] as Map<String, Object?>;
  final draws = diversity['draws'] as num;
  out.writeln(
    '\n### Tirage, diversité et main\n\n${fmt(draws)} cartes proposées ; ${diversity['uniqueCards']} distinctes au niveau campagne. '
    '${n('draw.repetitions')} répétitions dans la même main de joueur au fil de la session, '
    '${fmt(draws == 0 ? null : 10 * n('draw.repetitions') / draws)} par dix tirages. '
    'Délai moyen avant répétition : ${stat('draw.repeatDelayDraws')} tirages des deux joueurs. '
    'Concentration top 10 : ${pct(diversity['top10Share'] as num? ?? 0, 1)}. '
    'Ratio uniques/tirages par joueur-session : ${fmt((d['draw.uniqueRatioBasisPoints']?['mean'] as num? ?? 0) / 100)} %.',
  );
  out.writeln(
    '\nPool commun moyen : ${stat('pool.common')} ; pool joueur A / B : ${stat('pool.player1')} / ${stat('pool.player2')}. '
    '${n('pool.small')} observations de pool < 4 ; ${n('pool.empty')} à zéro.',
  );
  out.writeln(
    '\n| Cartes | Mains détenues | Mains jouables avec une valeur de commit |\n|---:|---:|---:|',
  );
  for (var h = 0; h <= 4; h++) {
    out.writeln(
      '| $h | ${d['hand.size']?['distribution']?['$h'] ?? 0} | ${d['hand.playableSize']?['distribution']?['$h'] ?? 0} |',
    );
  }
  out.writeln(
    '\nDiversité moyenne par main : ${stat('hand.uniqueTags')} tags, ${stat('hand.uniquePrecisions')} précisions, '
    '${stat('hand.uniqueChili')} niveaux. Répétitions de tags : ${stat('hand.repeatedTags')}. '
    'Valeur personnelle moyenne / médiane : ${stat('hand.personalValues')} / ${stat('hand.personalValues', 'median')}.',
  );
  for (final key in [
    'draw.chili',
    'draw.precision',
    'draw.frequency',
    'hand.chili',
  ]) {
    out.writeln('\n`$key` : `${jsonEncode(f[key])}`.');
  }
  out.writeln(
    '\nVerrous utilisés : ${n('lock.used')} ; conservation moyenne des verrous joués : ${stat('lock.retentionRounds')} rounds '
    '(verrous restants censurés dans le JSON). Renouvellement avec / sans verrou : ${stat('hand.newCardsLocked')} / '
    '${stat('hand.newCardsUnlocked')} cartes ; ${n('lock.blocked')} mains verrouillées sans choix jouable. '
    'Comparaison observationnelle, pas un effet causal.',
  );
  out.writeln(
    '\n### Scénarios\n\n| Scénario | Sessions | Duels | PA A : médiane duels à 50 % | PA B : médiane duels à 50 % | Contre-enchères / duels | Recovery / session | Main complète |\n|---|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final e in (report['byScenario'] as Map<String, Object?>).entries) {
    final g = e.value as Map<String, Object?>,
        gc = g['counters'] as Map<String, Object?>,
        gd = g['distributions'] as Map<String, Object?>;
    out.writeln(
      '| ${e.key} | ${gc['sessions']} | ${gc['duels'] ?? 0} | ${fmt(gd['pa.a.duelsTo50']?['median'])} | '
      '${fmt(gd['pa.b.duelsTo50']?['median'])} | ${pct(gc['auction.counter'] ?? 0, gc['duels'] ?? 0)} | '
      '${fmt(gd['recovery.perSession']?['mean'])} | ${pct(gd['hand.size']?['distribution']?['4'] ?? 0, gd['hand.size']?['count'] ?? 0)} |',
    );
  }
  out.writeln(
    '\nStyles initiaux : les nombres ci-dessous sont des tirages par niveau de variante. '
    'Les détails de précision, fréquence et tags figurent dans chaque scénario JSON.\n\n'
    '| Style initial | 🌶️1 | 🌶️2 | 🌶️3 | 🌶️4 | 🌶️5 |\n|---|---:|---:|---:|---:|---:|',
  );
  for (final style in ['SOFT', 'EPICE', 'INTENABLE']) {
    final counts =
        report['byScenario']['style_$style']['frequencies']['draw.chili'];
    out.writeln(
      '| $style | ${[for (var level = 1; level <= 5; level++) counts['$level'] ?? 0].join(' | ')} |',
    );
  }
  out.writeln('\n### Catalogue et anomalies\n');
  for (final e in (report['catalogCoverage'] as Map<String, Object?>).entries) {
    out.writeln('- ${e.key} : `${jsonEncode(e.value)}`.');
  }
  out.writeln(
    '\n« Jamais éligible » signifie dans les contextes normaux effectivement visités, pas une preuve universelle '
    'd’incohérence du catalogue. Les refus structurés figurent dans `frequencies.ineligibility`.',
  );
  out.writeln(
    '\nViolations d’invariants : ${n('invariantViolations')} ; rounds sans choix jouable : ${n('round.unresolvable')} ; '
    'actions revalidées puis ignorées après changement contextuel : ${n('execution.contextChanged')}. '
    'Transitions STOP/refus vérifiées neutres : ${n('technicalNeutralTransitions')} ; STOP : ${n('technicalStop')}.',
  );
  out.writeln(
    '\nFréquences par carte (éligibilité = observations joueur/round, tirage = nouvelles entrées en main) :\n\n'
    '| Carte | Éligible | Tirée | Part des tirages |\n|---|---:|---:|---:|',
  );
  final cardFreq = (f['draw.card'] as Map<String, Object?>?) ?? {};
  final elig = (f['eligible.card'] as Map<String, Object?>?) ?? {};
  final ids = {...cardFreq.keys, ...elig.keys}.map((e) => e.toString()).toList()
    ..sort();
  for (final id in ids) {
    out.writeln(
      '| $id | ${elig[id] ?? 0} | ${cardFreq[id] ?? 0} | ${pct(cardFreq[id] ?? 0, draws)} |',
    );
  }
  out.writeln(
    '\nRepères descriptifs : carte extrêmement rare < 0,1 % des tirages ; omniprésente > 5 %. '
    'Ces seuils ne sont ni des règles ni des objectifs. Les fréquences de tous les tags sont dans le JSON.',
  );
  final rare =
      cardFreq.entries
          .where((e) => (e.value as num) / draws < .001)
          .map((e) => e.key)
          .toList()
        ..sort();
  final ubiquitous =
      cardFreq.entries
          .where((e) => (e.value as num) / draws > .05)
          .map((e) => e.key)
          .toList()
        ..sort();
  out.writeln(
    '\nCartes extrêmement rares : `${jsonEncode(rare)}`. Cartes omniprésentes : `${jsonEncode(ubiquitous)}`.',
  );
  final tags = ((f['draw.tag'] as Map<String, Object?>?) ?? {}).entries.toList()
    ..sort((a, b) => (b.value as num).compareTo(a.value as num));
  final tagTotal = tags.fold<num>(0, (n, e) => n + (e.value as num));
  out.writeln(
    '\nTags sous-représentés (< 0,1 % des occurrences de tags) : '
    '`${jsonEncode(tags.where((e) => (e.value as num) / tagTotal < .001).map((e) => e.key).toList())}`. '
    'Tags surreprésentés (> 5 %) : '
    '`${jsonEncode(tags.where((e) => (e.value as num) / tagTotal > .05).map((e) => e.key).toList())}`. '
    'Ce sont des seuils descriptifs, sans objectif de fréquence éditoriale.',
  );
  out.writeln('\n| Tag (20 plus fréquents) | Présences |\n|---|---:|');
  for (final tag in tags.take(20)) {
    out.writeln('| ${tag.key} | ${tag.value} |');
  }
  out.writeln(
    '\n## INTERPRÉTATION\n\nCes données caractérisent les décisions artificielles documentées, pas les comportements de couples réels. '
    'Les différences de scénarios et la censure interdisent de résumer tout l’équilibrage par une moyenne globale. '
    'Voir l’analyse explicitement séparée dans [la documentation Phase 4](phase4_simulation.md).',
  );
  out.writeln(
    '\n## RECOMMANDATION D’ÉQUILIBRAGE\n\nAucune modification automatique de BASELINE. '
    'La décision concernant un éventuel candidat et les essais complémentaires sont consignés dans '
    '[la documentation Phase 4](phase4_simulation.md). Aucun consentement ne doit être élargi pour augmenter la variété.',
  );
  File(output).writeAsStringSync(out.toString());
}

// Typed access to the versioned generated JSON report.
extension _JsonObject on Object? {
  Object? operator [](String key) =>
      this is Map<String, Object?> ? (this as Map<String, Object?>)[key] : null;
}
