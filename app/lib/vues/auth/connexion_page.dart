import 'package:flutter/material.dart';

import '../../donnees/auth_depot.dart';
import '../../donnees/erreurs.dart';

/// Connexion et inscription. Aucune navigation ici : la PorteEntree change
/// d'écran toute seule dès que la session existe.
class ConnexionPage extends StatefulWidget {
  const ConnexionPage({super.key, required this.auth});

  final AuthDepot auth;

  @override
  State<ConnexionPage> createState() => _ConnexionPageState();
}

class _ConnexionPageState extends State<ConnexionPage> {
  final _formulaire = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _motDePasse = TextEditingController();
  final _pseudo = TextEditingController();

  bool _inscription = false;
  bool _envoi = false;
  bool _masquer = true;
  String? _erreur;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _motDePasse.dispose();
    _pseudo.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _erreur = null;
      _info = null;
    });
    if (!_formulaire.currentState!.validate()) return;

    setState(() => _envoi = true);
    try {
      if (_inscription) {
        final connecte = await widget.auth.inscrire(
          email: _email.text,
          motDePasse: _motDePasse.text,
          pseudo: _pseudo.text,
        );
        if (!connecte && mounted) {
          setState(() {
            _inscription = false;
            _info = 'Compte créé. Ouvrez le lien reçu par e-mail, puis connectez-vous.';
          });
        }
      } else {
        await widget.auth.connecter(
          email: _email.text,
          motDePasse: _motDePasse.text,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formulaire,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.home_work_outlined,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Colloc'",
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        'La vie en colocation, sans prise de tête',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Connexion')),
                          ButtonSegment(
                            value: true,
                            label: Text('Inscription'),
                          ),
                        ],
                        selected: {_inscription},
                        onSelectionChanged: _envoi
                            ? null
                            : (s) => setState(() {
                                _inscription = s.first;
                                _erreur = null;
                              }),
                      ),
                      const SizedBox(height: 24),
                      if (_inscription) ...[
                        TextFormField(
                          key: const Key('pseudo'),
                          controller: _pseudo,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.nickname],
                          decoration: const InputDecoration(
                            labelText: 'Pseudo',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (v) {
                            final texte = (v ?? '').trim();
                            if (texte.isEmpty) return 'Choisissez un pseudo';
                            if (texte.length > 30) {
                              return '30 caractères maximum';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        key: const Key('email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Adresse e-mail',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                        validator: (v) =>
                            RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch((v ?? '').trim())
                            ? null
                            : 'Adresse e-mail invalide',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('mot_de_passe'),
                        controller: _motDePasse,
                        obscureText: _masquer,
                        autofillHints: [
                          _inscription
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _masquer ? 'Afficher' : 'Masquer',
                            icon: Icon(
                              _masquer
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _masquer = !_masquer),
                          ),
                        ),
                        validator: (v) => (v ?? '').length < 6
                            ? 'Au moins 6 caractères'
                            : null,
                        onFieldSubmitted: (_) => _valider(),
                      ),
                      if (_erreur != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _erreur!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      if (_info != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _info!,
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('valider'),
                        onPressed: _envoi ? null : _valider,
                        child: _envoi
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _inscription
                                    ? 'Créer mon compte'
                                    : 'Se connecter',
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
