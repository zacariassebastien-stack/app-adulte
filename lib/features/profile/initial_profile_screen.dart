import 'package:flutter/material.dart';

import '../../domain/catalog/v4_catalog.dart';
import '../../engines/profile/initial_questionnaire_engine.dart';
import '../game/network_profile_learning.dart';

class InitialProfileScreen extends StatefulWidget {
  const InitialProfileScreen({
    required this.playerId,
    required this.questionnaire,
    required this.adaptiveStore,
    required this.profileStore,
    required this.onCompleted,
    super.key,
  });

  final String playerId;
  final ProfileQuestionnaire questionnaire;
  final NetworkProfileLearningStore adaptiveStore;
  final V4ProfileStore profileStore;
  final VoidCallback onCompleted;

  @override
  State<InitialProfileScreen> createState() => _InitialProfileScreenState();
}

class _InitialProfileScreenState extends State<InitialProfileScreen> {
  final Map<String, InitialQuestionResponse> _responses = {};
  var _index = 0;
  var _saving = false;

  ProfileQuestion get _question => widget.questionnaire.questions[_index];
  String _key(ProfileQuestionAxis axis) =>
      QuestionAxisKey(_question.stableId, axis.axisId).storageKey;
  bool get _complete =>
      _question.axes.every((axis) => _responses.containsKey(_key(axis)));

  Future<void> _continue() async {
    if (_saving || !_complete) return;
    if (_index < widget.questionnaire.questions.length - 1) {
      setState(() => _index++);
      return;
    }
    setState(() => _saving = true);
    final profile = const InitialQuestionnaireEngine().initialize(
      profileId: widget.playerId,
      questionnaire: widget.questionnaire,
      responses: _responses,
    );
    await widget.profileStore.save(profile);
    await widget.adaptiveStore.save(adaptiveProfileFromV4Profile(profile));
    if (mounted) widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final question = _question;
    return Scaffold(
      appBar: AppBar(title: const Text('Créer mon profil')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(
                    value: (_index + 1) / widget.questionnaire.questions.length,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_index + 1} / ${widget.questionnaire.questions.length}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            question.label,
                            key: const Key('initial-profile-question'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          if (question.helpText != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              question.helpText!,
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 18),
                          for (final axis in question.axes) ...[
                            Text(
                              axis.label ?? axis.role.wireName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _choice(
                                  axis,
                                  'J’adore',
                                  InitialQuestionResponse.love,
                                ),
                                _choice(
                                  axis,
                                  'Ça me plaît',
                                  InitialQuestionResponse.like,
                                ),
                                _choice(
                                  axis,
                                  'Je ne sais pas',
                                  InitialQuestionResponse.unsure,
                                ),
                                _choice(
                                  axis,
                                  'Exclu',
                                  InitialQuestionResponse.excluded,
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('initial-profile-continue'),
                    onPressed: _complete && !_saving ? _continue : null,
                    child: Text(
                      _index == widget.questionnaire.questions.length - 1
                          ? 'Enregistrer mon profil'
                          : 'Question suivante',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tes préférences restent privées. Elles ne valent jamais consentement explicite.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _choice(
    ProfileQuestionAxis axis,
    String label,
    InitialQuestionResponse response,
  ) => ChoiceChip(
    label: Text(label),
    selected: _responses[_key(axis)] == response,
    onSelected: _saving
        ? null
        : (_) => setState(() => _responses[_key(axis)] = response),
  );
}
