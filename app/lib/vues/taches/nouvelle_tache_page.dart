import 'package:flutter/material.dart';

import '../../donnees/erreurs.dart';
import '../../etat/services.dart';
import '../../modeles/vie_commune.dart';
import '../../outils/dates.dart';

class NouvelleTachePage extends StatefulWidget {
  const NouvelleTachePage({super.key, required this.colocationId});

  final String colocationId;

  @override
  State<NouvelleTachePage> createState() => _NouvelleTachePageState();
}

class _NouvelleTachePageState extends State<NouvelleTachePage> {
  final _formulaire = GlobalKey<FormState>();
  final _titre = TextEditingController();
  Frequence _frequence = Frequence.hebdomadaire;
  DateTime _echeance = aujourdhui();
  late String _responsable = context.services.session.moi!;
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _titre.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final choix = await showDatePicker(
      context: context,
      initialDate: _echeance,
      firstDate: aujourdhui().subtract(const Duration(days: 30)),
      lastDate: aujourdhui().add(const Duration(days: 365)),
    );
    if (choix != null) setState(() => _echeance = choix);
  }

  Future<void> _enregistrer() async {
    if (!_formulaire.currentState!.validate()) return;
    final services = context.services;
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await services.depots.taches.creer(
        colocationId: widget.colocationId,
        titre: _titre.text,
        frequence: _frequence,
        responsableId: _responsable,
        premiereEcheance: _echeance,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      services.reseau.signalerErreur(e);
      if (mounted) {
        setState(() {
          _envoi = false;
          _erreur = messageErreur(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle tâche')),
      body: Form(
        key: _formulaire,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titre,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Tâche',
                hintText: 'Sortir les poubelles, vaisselle…',
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Nommez la tâche' : null,
            ),
            const SizedBox(height: 8),
            SegmentedButton<Frequence>(
              segments: [
                for (final f in Frequence.values)
                  ButtonSegment(value: f, label: Text(f.libelle)),
              ],
              selected: {_frequence},
              onSelectionChanged: (s) => setState(() => _frequence = s.first),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Première échéance'),
              subtitle: Text(formaterDate(_echeance)),
              onTap: _choisirDate,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _responsable,
              decoration: const InputDecoration(
                labelText: 'Commence par',
                helperText:
                    'Ensuite, chacun son tour (ordre d\'arrivée dans la coloc)',
              ),
              items: [
                for (final m in session.membresActifs)
                  DropdownMenuItem(
                    value: m.utilisateurId,
                    child: Text(m.pseudo),
                  ),
              ],
              onChanged: (v) => setState(() => _responsable = v!),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 16),
              Text(
                _erreur!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _envoi ? null : _enregistrer,
              child: _envoi
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Créer la tâche'),
            ),
          ],
        ),
      ),
    );
  }
}
