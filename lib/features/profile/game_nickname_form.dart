import 'package:flutter/material.dart';
import '../../domain/profile/v4_profile.dart';

class GameNicknameForm extends StatefulWidget {
  const GameNicknameForm({
    required this.onSaved,
    this.initialValue,
    this.buttonText = 'Continuer',
    super.key,
  });
  final String? initialValue;
  final String buttonText;
  final Future<void> Function(String) onSaved;
  @override
  State<GameNicknameForm> createState() => _GameNicknameFormState();
}

class _GameNicknameFormState extends State<GameNicknameForm> {
  final _form = GlobalKey<FormState>();
  late final _input = TextEditingController(text: widget.initialValue);
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSaved(GameNickname.normalize(_input.text));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Enregistrement impossible. Réessaie.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Quel est ton pseudo de jeu ?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'C’est le nom utilisé pendant les parties, notamment pour indiquer qui réalise une action.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('game-nickname-input'),
          controller: _input,
          enabled: !_saving,
          validator: GameNickname.error,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Pseudo de jeu',
            hintText: 'Seb, Julie, Joueur 1…',
            helperText: '2 à 20 caractères',
          ),
          onFieldSubmitted: (_) => _save(),
        ),
        if (_error != null) Text(_error!),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('save-game-nickname'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Enregistrement…' : widget.buttonText),
        ),
      ],
    ),
  );
}
