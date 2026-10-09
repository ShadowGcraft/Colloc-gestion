import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../donnees/depense_depot.dart';
import '../../donnees/erreurs.dart';
import '../../etat/reseau.dart';
import '../../modeles/argent.dart';
import '../../modeles/coloc.dart';
import '../../outils/dates.dart';
import '../../outils/montants.dart';
import '../../outils/repartition.dart';
import '../../widgets/saisie.dart';

/// Formulaire d'ajout d'une dépense. Toutes ses dépendances sont passées au
/// constructeur : il peut ainsi être testé avec un faux dépôt (test/).
class NouvelleDepensePage extends StatefulWidget {
  const NouvelleDepensePage({
    super.key,
    required this.depot,
    required this.colocationId,
    required this.membres,
    required this.moi,
    this.reseau,
  });

  final DepenseDepot depot;
  final String colocationId;

  /// Membres actifs (seuls eux peuvent payer ou participer)
  final List<Membre> membres;
  final String moi;
  final EtatReseau? reseau;

  @override
  State<NouvelleDepensePage> createState() => _NouvelleDepensePageState();
}

class _NouvelleDepensePageState extends State<NouvelleDepensePage> {
  final _formulaire = GlobalKey<FormState>();
  final _montant = TextEditingController();
  final _description = TextEditingController();
  late final Map<String, TextEditingController> _parts = {
    for (final m in widget.membres) m.utilisateurId: TextEditingController(),
  };

  late String _payeur = widget.membres.any((m) => m.utilisateurId == widget.moi)
      ? widget.moi
      : widget.membres.first.utilisateurId;
  late final Set<String> _participants = widget.membres
      .map((m) => m.utilisateurId)
      .toSet();
  DateTime _date = aujourdhui();
  bool _personnalise = false;
  PhotoTicket? _ticket;
  bool _envoi = false;
  String? _erreurRepartition;
  String? _erreurServeur;

  @override
  void initState() {
    super.initState();
    // l'aperçu des parts et le « reste à répartir » se mettent à jour en direct
    _montant.addListener(_rafraichir);
    for (final c in _parts.values) {
      c.addListener(_rafraichir);
    }
  }

  void _rafraichir() => setState(() => _erreurRepartition = null);

  @override
  void dispose() {
    _montant.dispose();
    _description.dispose();
    for (final c in _parts.values) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _total => lireMontant(_montant.text);

  /// Participants dans l'ordre d'affichage
  List<String> get _ordre => widget.membres
      .map((m) => m.utilisateurId)
      .where(_participants.contains)
      .toList();

  int get _sommePersonnalisee => _ordre
      .map((id) => lireMontant(_parts[id]!.text) ?? 0)
      .fold(0, (a, b) => a + b);

  String? _verifierRepartition(int total) {
    if (_participants.isEmpty) return 'Choisissez au moins un participant.';
    if (!_personnalise) return null;
    for (final id in _ordre) {
      if (lireMontant(_parts[id]!.text) == null) {
        return 'Indiquez la part de chaque participant.';
      }
    }
    final somme = _sommePersonnalisee;
    if (somme != total) {
      return 'La somme des parts (${formaterEuros(somme)}) doit être égale au montant (${formaterEuros(total)}).';
    }
    return null;
  }

  Future<void> _choisirDate() async {
    final choix = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: aujourdhui().add(const Duration(days: 365)),
    );
    if (choix != null) setState(() => _date = choix);
  }

  Future<void> _choisirTicket() async {
    try {
      final photo = await choisirPhoto(context);
      if (photo != null) setState(() => _ticket = photo);
    } catch (e) {
      setState(() => _erreurServeur = "Impossible d'ouvrir les photos : $e");
    }
  }

  Future<void> _enregistrer() async {
    setState(() => _erreurServeur = null);
    final formulaireOk = _formulaire.currentState!.validate();
    final total = _total;
    if (!formulaireOk || total == null) return;

    final erreur = _verifierRepartition(total);
    if (erreur != null) {
      setState(() => _erreurRepartition = erreur);
      return;
    }

    setState(() => _envoi = true);
    try {
      await widget.depot.creer(
        NouvelleDepense(
          colocationId: widget.colocationId,
          payeurId: _payeur,
          montantCentimes: total,
          description: _description.text,
          date: _date,
          participants: _ordre,
          montantsPersonnalises: _personnalise
              ? [for (final id in _ordre) lireMontant(_parts[id]!.text)!]
              : null,
          ticket: _ticket,
        ),
      );
      widget.reseau?.signalerSucces();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      widget.reseau?.signalerErreur(e);
      if (mounted) {
        setState(() {
          _envoi = false;
          _erreurServeur = messageErreur(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _total;
    final apercu = !_personnalise && total != null
        ? repartirEgalement(total, _participants)
        : const <String, int>{};
    final reste = _personnalise && total != null
        ? total - _sommePersonnalisee
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle dépense')),
      body: Form(
        key: _formulaire,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('montant'),
              controller: _montant,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Montant',
                suffixText: '€',
              ),
              validator: (v) {
                final c = lireMontant(v ?? '');
                if (c == null) return 'Montant invalide (ex. 12,50)';
                if (c <= 0) return 'Le montant doit être positif';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('description'),
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Courses, loyer, électricité…',
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Décrivez la dépense' : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _payeur,
                    decoration: const InputDecoration(labelText: 'Payé par'),
                    items: [
                      for (final m in widget.membres)
                        DropdownMenuItem(
                          value: m.utilisateurId,
                          child: Text(m.pseudo),
                        ),
                    ],
                    onChanged: (v) => setState(() => _payeur = v!),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _choisirDate,
                  icon: const Icon(Icons.event),
                  label: Text(formaterDate(_date)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Répartition', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Parts égales'),
                  icon: Icon(Icons.drag_handle),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Personnalisée', key: Key('mode_personnalise')),
                  icon: Icon(Icons.tune),
                ),
              ],
              selected: {_personnalise},
              onSelectionChanged: (s) => setState(() {
                _personnalise = s.first;
                _erreurRepartition = null;
              }),
            ),
            const SizedBox(height: 8),
            for (final m in widget.membres)
              _LigneParticipant(
                membre: m,
                coche: _participants.contains(m.utilisateurId),
                personnalise: _personnalise,
                controleur: _parts[m.utilisateurId]!,
                apercu: apercu[m.utilisateurId],
                surCoche: (coche) => setState(() {
                  coche
                      ? _participants.add(m.utilisateurId)
                      : _participants.remove(m.utilisateurId);
                  _erreurRepartition = null;
                }),
              ),
            if (reste != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  reste == 0
                      ? 'Tout est réparti ✓'
                      : reste > 0
                      ? 'Reste à répartir : ${formaterEuros(reste)}'
                      : 'Trop réparti de ${formaterEuros(-reste)}',
                  style: TextStyle(
                    color: reste == 0
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                ),
              ),
            if (_erreurRepartition != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _erreurRepartition!,
                  key: const Key('erreur_repartition'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'Ticket de caisse (facultatif)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_ticket == null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _envoi ? null : _choisirTicket,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Ajouter une photo'),
                ),
              )
            else
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      Uint8List.fromList(_ticket!.octets),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _envoi
                        ? null
                        : () => setState(() => _ticket = null),
                    icon: const Icon(Icons.close),
                    label: const Text('Retirer'),
                  ),
                ],
              ),
            if (_erreurServeur != null) ...[
              const SizedBox(height: 16),
              Text(
                _erreurServeur!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('enregistrer'),
              onPressed: _envoi ? null : _enregistrer,
              icon: _envoi
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LigneParticipant extends StatelessWidget {
  const _LigneParticipant({
    required this.membre,
    required this.coche,
    required this.personnalise,
    required this.controleur,
    required this.apercu,
    required this.surCoche,
  });

  final Membre membre;
  final bool coche;
  final bool personnalise;
  final TextEditingController controleur;
  final int? apercu;
  final ValueChanged<bool> surCoche;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: CheckboxListTile(
          key: Key('participant_${membre.utilisateurId}'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: coche,
          title: Text(membre.pseudo),
          onChanged: (v) => surCoche(v ?? false),
        ),
      ),
      if (coche && personnalise)
        SizedBox(
          width: 110,
          child: TextField(
            key: Key('part_${membre.utilisateurId}'),
            controller: controleur,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(isDense: true, suffixText: '€'),
          ),
        )
      else if (coche && apercu != null)
        Text(formaterEuros(apercu!)),
    ],
  );
}
