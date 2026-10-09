import 'package:flutter/material.dart';

import '../../donnees/erreurs.dart';
import '../../etat/services.dart';
import '../../modeles/argent.dart';
import '../../outils/dates.dart';
import '../../outils/montants.dart';
import '../../widgets/avatar.dart';
import '../../widgets/etats.dart';

class DetailDepensePage extends StatefulWidget {
  const DetailDepensePage({super.key, required this.depense});

  final Depense depense;

  @override
  State<DetailDepensePage> createState() => _DetailDepensePageState();
}

class _DetailDepensePageState extends State<DetailDepensePage> {
  Future<String>? _urlTicket;
  bool _suppression = false;

  @override
  void initState() {
    super.initState();
    final chemin = widget.depense.ticketChemin;
    if (chemin != null) {
      _urlTicket = context.services.depots.depenses.urlTicket(chemin);
    }
  }

  Future<void> _supprimer() async {
    final services = context.services;
    final ok = await confirmer(
      context,
      titre: 'Supprimer la dépense ?',
      message:
          'Les soldes seront recalculés sans « ${widget.depense.description} ».',
    );
    if (!ok || !mounted) return;
    setState(() => _suppression = true);
    try {
      await services.depots.depenses.supprimer(widget.depense);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      services.reseau.signalerErreur(e);
      if (!mounted) return;
      setState(() => _suppression = false);
      afficherErreur(context, messageErreur(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    final d = widget.depense;
    final theme = Theme.of(context);
    final peutSupprimer = d.creePar == session.moi || session.suisAdmin;
    final parts = d.parts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dépense'),
        actions: [
          if (peutSupprimer)
            IconButton(
              tooltip: 'Supprimer',
              onPressed: _suppression ? null : _supprimer,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(d.description, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            formaterEuros(d.montantCentimes),
            style: theme.textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Payé par ${session.pseudo(d.payeurId)}, ${formaterDate(d.date).toLowerCase()}',
          ),
          const SizedBox(height: 24),
          Text('Répartition', style: theme.textTheme.titleMedium),
          for (final part in parts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AvatarMembre(utilisateurId: part.key),
              title: Text(session.pseudo(part.key)),
              trailing: Text(
                formaterEuros(part.value),
                style: theme.textTheme.bodyLarge,
              ),
            ),
          if (_urlTicket != null) ...[
            const SizedBox(height: 16),
            Text('Ticket', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FutureBuilder<String>(
                future: _urlTicket,
                builder: (context, url) {
                  if (url.hasError) return const _TicketIndisponible();
                  if (!url.hasData) {
                    return const SizedBox(height: 200, child: Chargement());
                  }
                  return InteractiveViewer(
                    child: Image.network(
                      url.data!,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, image, progression) =>
                          progression == null
                          ? image
                          : const SizedBox(height: 200, child: Chargement()),
                      errorBuilder: (_, _, _) => const _TicketIndisponible(),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TicketIndisponible extends StatelessWidget {
  const _TicketIndisponible();

  @override
  Widget build(BuildContext context) => Container(
    height: 120,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    alignment: Alignment.center,
    child: const Text('Photo indisponible (hors connexion ?)'),
  );
}
