import 'package:flutter_test/flutter_test.dart';
import 'package:couple_cards/domain/profile/v4_profile.dart';
import 'package:couple_cards/engines/profile/card_personalization_engine.dart';
import 'package:couple_cards/engines/profile/v4_card_rating_engine.dart';

void main() {
  const engine = CardPersonalizationEngine();
  CardRatingKey key(int n) => CardRatingKey(
    profileId: 'p',
    cardId: '$n',
    variantId: '$n.action',
    role: ProfilePreferenceRole.faire,
  );
  double internal(CardSpecificLearningStore s, int n) =>
      (s.read(key(n))!.personalization['internal']! as num).toDouble();
  for (final tags in <Map<String, double>>[
    {'a': 1},
    {'a': 1, 'b': 1},
    {'a': 1, 'b': .5},
    {'a': 1, 'b': 1, 'c': .5, 'd': .5},
    {'c': .5, 'd': .5},
  ]) {
    for (final signal in [
      PersonalizationSignal.chosen,
      PersonalizationSignal.resisted,
    ]) {
      test('signed tag budget conserved for $tags $signal', () {
        final store = CardSpecificLearningStore();
        engine.observe(
          store: store,
          key: key(0),
          prior: 10,
          tags: tags,
          eventId: 'e',
          signal: signal,
          enabled: true,
        );
        final delta = internal(store, 0) - 10;
        final evidence =
            store.read(key(0))!.personalization['tag_evidence']! as Map;
        expect(
          evidence.values.cast<num>().fold<double>(0, (a, b) => a + b),
          closeTo(delta * .5, 1e-10),
        );
        expect(
          delta.abs(),
          closeTo(signal == PersonalizationSignal.chosen ? .05 : .1, 1e-10),
        );
        final restored = CardSpecificLearningStore()..restore(store.toJson());
        expect(
          engine.observe(
            store: restored,
            key: key(0),
            prior: 10,
            tags: tags,
            eventId: 'e',
            signal: signal,
            enabled: true,
          ),
          false,
        );
        expect(restored.toJson(), store.toJson());
      });
    }
  }
  for (final n in [1, 2, 3, 5]) {
    for (final signal in [
      PersonalizationSignal.offered,
      PersonalizationSignal.strongAccepted,
      PersonalizationSignal.resisted,
    ]) {
      test('package $signal budget independent of N=$n', () {
        final store = CardSpecificLearningStore();
        var total = 0.0;
        for (var i = 0; i < n; i++) {
          engine.observe(
            store: store,
            key: key(i),
            prior: 10,
            tags: const {'a': 1, 'b': .5},
            eventId: 'package/$i',
            signal: signal,
            enabled: true,
            scale: 1 / n,
          );
          total += internal(store, i) - 10;
        }
        expect(
          total,
          closeTo(
            signal == PersonalizationSignal.offered
                ? -.025
                : signal == PersonalizationSignal.resisted
                ? .1
                : -.05,
            1e-10,
          ),
        );
      });
    }
  }
  test('recovery is a single capped modulated event', () {
    for (final sacrifice in [0.0, .5, 1.0]) {
      final store = CardSpecificLearningStore();
      final amount = .075 + (.30 - .075) * sacrifice;
      engine.observe(
        store: store,
        key: key(0),
        prior: 10,
        tags: const {'a': 1},
        eventId: 'recovery',
        signal: PersonalizationSignal.recovery,
        enabled: true,
        scale: amount / .075,
      );
      expect(internal(store, 0), closeTo(10 - amount, 1e-10));
      expect(store.read(key(0))!.observationCount, 1);
    }
  });
  test('accepted tier and propagation do not generate new tag evidence', () {
    final store = CardSpecificLearningStore();
    for (var i = 0; i < 40; i++) {
      engine.observe(
        store: store,
        key: key(0),
        prior: 7.5,
        tags: const {'a': 1},
        eventId: 'e$i',
        signal: PersonalizationSignal.chosen,
        enabled: true,
      );
    }
    final evidence = Map<String, Object?>.from(
      store.read(key(0))!.personalization['tag_evidence']! as Map,
    );
    engine.decide(store, key(0), accept: true);
    engine.drawWeight(store, key(1), 12, const {'a': 1});
    expect(store.read(key(0))!.personalization['tag_evidence'], evidence);
    expect(store.read(key(1)), isNull);
  });
  test(
    'direct observations can oppose a negative tag hypothesis without changing official tier',
    () {
      final store = CardSpecificLearningStore();
      for (var i = 0; i < 100; i++) {
        engine.observe(
          store: store,
          key: key(0),
          prior: 10,
          tags: const {'a': 1},
          eventId: 'bad$i',
          signal: PersonalizationSignal.resisted,
          enabled: true,
        );
      }
      final before = engine.drawWeight(store, key(1), 10, const {'a': 1});
      for (var i = 0; i < 40; i++) {
        engine.observe(
          store: store,
          key: key(1),
          prior: 10,
          tags: const {'a': 1},
          eventId: 'good$i',
          signal: PersonalizationSignal.chosen,
          enabled: true,
        );
      }
      expect(
        engine.drawWeight(store, key(1), 10, const {'a': 1}),
        greaterThan(before),
      );
      expect(store.referenceEstimate(key(1)), 10);
    },
  );
  test('persistent positive choices survive forty game boundaries', () {
    var store = CardSpecificLearningStore();
    for (var game = 0; game < 40; game++) {
      for (var choice = 0; choice < 2; choice++) {
        engine.observe(
          store: store,
          key: key(0),
          prior: 7.5,
          tags: const {'a': 1},
          eventId: '$game/$choice',
          signal: PersonalizationSignal.chosen,
          enabled: true,
        );
      }
      // Persistence between games never quantizes or resets the private value.
      store = CardSpecificLearningStore()..restore(store.toJson());
    }
    expect(internal(store, 0), closeTo(3.5, 1e-10));
    expect(store.read(key(0))!.personalization['pending'], isNotNull);
    expect(store.read(key(0))!.observationCount, 80);
    expect(store.referenceEstimate(key(0)), 7.5);
  });
  test(
    'production repeat floor survives retry and resets with exposure episode',
    () {
      var store = CardSpecificLearningStore();
      var expected = 10.0;
      for (var i = 0; i < 20; i++) {
        final decay = [1.0, .9, .81, .729, .6561, .59049, .531441];
        expected += .025 * (i < decay.length ? decay[i] : .5);
        engine.observe(
          store: store,
          key: key(0),
          prior: 10,
          tags: const {'a': 1},
          eventId: 'e$i',
          signal: PersonalizationSignal.nonChoice,
          enabled: true,
          exposureEpisode: 'held',
        );
        expect(internal(store, 0), closeTo(expected, 1e-10));
        store = CardSpecificLearningStore()..restore(store.toJson());
      }
      final before = store.toJson();
      expect(
        engine.observe(
          store: store,
          key: key(0),
          prior: 10,
          tags: const {'a': 1},
          eventId: 'e19',
          signal: PersonalizationSignal.nonChoice,
          enabled: true,
          exposureEpisode: 'held',
        ),
        false,
      );
      expect(store.toJson(), before);
      engine.observe(
        store: store,
        key: key(0),
        prior: 10,
        tags: const {'a': 1},
        eventId: 'fresh',
        signal: PersonalizationSignal.nonChoice,
        enabled: true,
        exposureEpisode: 'new',
      );
      expect(internal(store, 0), closeTo(expected + .025, 1e-10));
    },
  );
}
