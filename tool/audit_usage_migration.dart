import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Static audit only. This does NOT compile or execute PostgreSQL/PLpgSQL.
void main() {
  const path = 'supabase/migrations/202610150001_concept_usage_contract.sql';
  final sql = File(path).readAsStringSync();
  final baseline =
      jsonDecode(
            File('docs/concept_transition_baseline.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  var checked = 0;
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
    checked++;
    stdout.writeln('PASS $message');
  }

  check(
    !RegExp(
      r'\b(create\s+table|alter\s+table|drop\s+table)\b',
      caseSensitive: false,
    ).hasMatch(sql),
    'No table or column changes',
  );
  check(
    !RegExp("'(occurrence_id|card_id)'", caseSensitive: false).hasMatch(sql),
    'Native payload has no legacy identity aliases',
  );
  final definitions = RegExp(
    r'create(?: or replace)? function public\.(\w+)\([\s\S]*?\$\$;',
    caseSensitive: false,
  ).allMatches(sql).toList();
  check(
    definitions.length == 14,
    '14 definitions: 11 existing functions and 3 JSON helpers',
  );
  const modified = {
    'continue_network_deck_cycle',
    'network_round_json',
    'submit_network_round_reveal',
    'network_final_choice',
    'submit_network_negotiation_proposal',
    'adapt_network_negotiation',
    'validate_network_negotiation',
    'submit_network_corruption_offer',
    'resolve_network_corruption',
    'submit_network_recovery',
    'resolve_network_recovery',
  };
  final names = definitions.map((m) => m.group(1)!).toSet();
  check(
    names.containsAll(modified),
    'All inspected RPC/helper definitions are present',
  );
  for (final match in definitions) {
    final name = match.group(1)!;
    if (!modified.contains(name) ||
        {'network_round_json', 'network_final_choice'}.contains(name)) {
      continue;
    }
    final body = match.group(0)!;
    check(
      body.contains('auth.uid()') &&
          body.contains('is_session_member') &&
          body.contains('ROUND_COMMAND_CONFLICT') &&
          body.contains('network_round_commands'),
      '$name preserves authentication membership and command replay boundary',
    );
  }
  for (final helper in [
    'network_usage_action(jsonb)',
    'network_usage_projection(jsonb,boolean)',
    'network_usage_resolution(jsonb,boolean)',
  ]) {
    check(
      sql.contains(
        'revoke all on function public.$helper from public,anon,authenticated;',
      ),
      '$helper is internal',
    );
  }
  check(
    sql.contains(
          "historical.usage->>'usage_id'=proposed->>'source_usage_id'",
        ) &&
        sql.contains("historical.usage->>'concept_id'=proposed->>'concept_id'"),
    'Corruption provenance joins a source usage and its concept, never concept alone',
  );
  check(
    sql.contains("coalesce(previous.final_resolution->'compromise'") &&
        sql.contains("coalesce(previous.corruption->'actions'") &&
        sql.contains('jsonb_array_elements(previous.recovery_history)'),
    'Canonical source history includes duel compromise corruption and Recovery usages',
  );
  final cycle = definitions
      .singleWhere((m) => m.group(1) == 'continue_network_deck_cycle')
      .group(0)!;
  check(
    cycle.contains('v_expected<v_cycle') &&
        cycle.contains('pg_advisory_xact_lock') &&
        cycle.contains("p_adjustment->>'expected_cycle'"),
    'Shared continuation serializes and ignores a second renewal of the same cycle',
  );
  check(
    !cycle.contains("role='PLAYER_1'") && cycle.contains('is_session_member'),
    'Continuation has no permanent first-player privilege',
  );
  var historical = 0;
  for (final entry
      in baseline['historical_supabase_migrations'] as List<dynamic>) {
    final row = entry as Map<String, dynamic>;
    if (sha256
            .convert(File(row['path'] as String).readAsBytesSync())
            .toString() !=
        row['sha256']) {
      throw StateError('Historical migration changed: ${row['path']}');
    }
    historical++;
  }
  check(historical == 11, 'All 11 historical migrations remain byte-identical');
  stdout.writeln(
    '$checked structural checks passed; PostgreSQL execution is a separate check',
  );
}
