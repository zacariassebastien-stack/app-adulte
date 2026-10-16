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
    !RegExp("'occurrence_id'", caseSensitive: false).hasMatch(sql),
    'Native action payload has no occurrence identity alias',
  );
  final definitions = RegExp(
    r'create(?: or replace)? function public\.(\w+)\([\s\S]*?\$\$;',
    caseSensitive: false,
  ).allMatches(sql).toList();
  check(
    definitions.length == 24,
    '24 native definitions cover stabilized V4 action boundaries',
  );
  const modified = {
    'resolve_network_initial_private',
    'respond_network_negotiation',
    'respond_network_corruption',
    'publish_v4_action_projection',
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
          "historical.usage->>'usage_id'=v_usage->>'source_usage_id'",
        ) &&
        sql.contains("historical.usage->>'concept_id'=v_usage->>'concept_id'"),
    'Corruption provenance joins a source usage and its concept, never concept alone',
  );
  check(
    sql.contains("coalesce(previous.final_resolution->'compromise'") &&
        sql.contains("coalesce(previous.corruption->'actions'") &&
        sql.contains("coalesce(previous.recovery_history,'[]'::jsonb)"),
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

  // The second parent is pinned: no network or mutable remote state is consulted.
  final historicalPaths = Process.runSync('git', ['-c', 'safe.directory=${Directory.current.path.replaceAll('\\', '/')}', 'ls-tree','-r','--name-only','e35cf6e470b8891cdb3f1de392af59f0375ef0a9','--','supabase/migrations']).stdout.toString().trim().split('\n');
  var remoteHistorical = 0;
  for(final raw in historicalPaths){
    final path=raw.trim(); if(!path.endsWith('.sql')) continue;
    final baseArgs=['-c','safe.directory=${Directory.current.path.replaceAll('\\','/')}'];
    final expected=Process.runSync('git',[...baseArgs,'rev-parse','e35cf6e470b8891cdb3f1de392af59f0375ef0a9:$path']);
    final actual=Process.runSync('git',[...baseArgs,'hash-object','--path=$path',path]);
    check(expected.exitCode==0 && actual.exitCode==0 && expected.stdout.toString().trim()==actual.stdout.toString().trim(), 'Remote historical migration unchanged Git blob: $path');
    remoteHistorical++;
  }
  check(remoteHistorical==30,'All 30 remote historical migrations are preserved');
  String body(String name)=>definitions.singleWhere((m)=>m.group(1)==name).group(0)!;
  check(!sql.contains('network_v4_persistent_effect_definitions') && !sql.contains("'{parameters,effective_spice}'"),'Native execution never reconstructs resolved action from a current catalogue');
  check(body('v4_corruption_compromise').contains('previous.round_number<p_round_number') && body('v4_corruption_compromise').contains("v_source->'resolved_action' is distinct from v_usage->'resolved_action'"),'Discard provenance preserves frozen source action and excludes current round');
  check(body('respond_network_negotiation').contains("'accepted'") && !body('respond_network_negotiation').contains("phase='NEGOTIATION_ADAPTATION'"),'Compromise retains the single final decision flow');
  check(body('respond_network_corruption').contains("phase='FINAL_RESOLVED'") && body('respond_network_corruption').contains("'{compromise}',v_compromise"),'Accepted corruption replaces the normal executable action');
  check(body('route_network_post_duel').contains("old.phase in ('FINAL_RESOLVED','RECOVERY')") && body('route_network_post_duel').contains("new.phase='WAITING_NEXT'"),'Recovery exit preserves the canonical close hooks');
  check(body('resolve_network_recovery').contains("v_existing->>'usage_id' is distinct from p_recovery->>'usage_id'") && body('resolve_network_recovery').contains("p_recovery-array['gain','completed','response']"),'Recovery completion compares the same immutable reserved action');
  check(body('v4_advance_persistent_effects').contains("'{resolved_action,parameters,duration_actions}'") && body('v4_advance_persistent_effects').contains("'{resolved_action,target_player_ids}'"),'Persistent effects use frozen duration and targets');

  stdout.writeln(
    '$checked structural checks passed; PostgreSQL execution is a separate check',
  );
}
