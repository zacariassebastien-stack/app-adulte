# Personalisation: decision-level learning

This document supersedes the historical learning prescriptions only for the
rules implemented here. Consent, anatomy, PA settlement, stock and Recovery's
canonical spice range keep their existing contracts.

## State and privacy

The existing `card_learning_v4.<player>` store retains one official reference
per profile/concept/action/direction. Its optional `personalization` metadata
holds a separate continuous estimate, observed exposures, event receipts,
pending tier and refusal cooldown. Historical records remain readable and
their counters are not fabricated into new events.

The existing private game checkpoint carries an event outbox. A decision and
its pending event are persisted before delivery. Applying an event and its
receipt is serialized in the card store. Replaying the checkpoint cannot count
the event twice. No learning metadata enters the public round protocol.

`Personnaliser soi-même` disables behavioral updates. Manual precise values
remain authoritative. `Faire confiance au jeu` enables decision-level updates.
Legacy aggregates remain readable; selected modes no longer feed that former
round-end inference pipeline. Deferred legacy sessions retain their former
aggregate compatibility path, not automatic adoption of its proposals.

## Decisions and official tiers

Confirmed commit, voluntary lock, canonical compromise/corruption/Recovery
offers and responses, and retained/accepted actions have separate receipts.
Consultation and reservation are not play events. Actual frozen actor/target
roles determine each participant's learning presentation.

Non-choice is evaluated only after the player's confirmed commit, only for
playable presentations previously exposed in that round, and not for locked
cards. The same presentation's negative evidence decays within its session and
cycle, including across reconstruction.

Continuous changes do not modify official PA. A crossed category is proposed
in the private profile settings. Accepting uses that category's official PA
centre; refusing retains the reference and starts a configurable cooldown.
The current round's ratings and every engaged usage remain frozen.

## Roles and explicit consent

021 uses autonomous MUTUEL. Only its initial questionnaire prior combines SOLO
and OBSERVER: either veto excludes, otherwise the arithmetic mean seeds MUTUEL.
The profile loader persists this bootstrap once. Existing precise MUTUEL card
ratings are retained. Later MUTUEL learning does not write SOLO or OBSERVER.

039 RECEVOIR uses `regarder/recevoir`; FAIRE keeps `etre_regarde/faire`.
013 retains its existing SOI learning role; historical SOLO presentation rating
keys are read as aliases of that same private identity, without changing play.

A new voluntary ordinary precise rating records an exact presentation allowance.
It can override broad personal exclusions for that action/direction only, never
an exact veto, a partner veto, anatomy or context. Legacy CARD_ESTIMATE records
are not converted into allowances: some originated from exclusions. New
exclusion markers explicitly carry EXCLUSION_MARKER provenance.

## Discovery and tuning

Class probabilities remain those of the existing style. Within a class,
concepts and zone choices receive bounded preference weights. Equal weights
preserve the previous RNG path. Already exposed precise states are autonomous;
unexposed presentations can borrow shared-tag hypotheses, with roles separate.

`PersonalizationConfig` centralizes signal sizes, repeat decay, draw amplitude,
minimum draw weight, minimum evidence and refusal cooldown. Defaults are tuning
starting points, not statistically calibrated outcomes. Lower PA means stronger
preference. Weighting never creates consent or bypasses eligibility.

No Supabase migration is required: the new fields are private local data and
the shared permission key and RPC contracts are unchanged.
