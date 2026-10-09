import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../etat/services.dart';
import '../../modeles/coloc.dart';
import '../../outils/dates.dart';
import '../../widgets/avatar.dart';
import '../../widgets/etats.dart';
import '../../widgets/saisie.dart';

/// Nom, code d'invitation et membres de la colocation.
/// Les boutons réservés à l'admin sont masqués pour les autres, mais c'est la
/// base (RPC + RLS) qui refuse réellement l'action : l'interface n'est qu'un confort.
class ParametresColocPage extends StatefulWidget {
  const ParametresColocPage({super.key});

  @override
  State<ParametresColocPage> createState() => _ParametresColocPageState();
}

class _ParametresColocPageState extends State<ParametresColocPage> {
  @override
  void initState() {
    super.initState();
    unawaited(context.services.session.rechargerMembres());
  }

  Future<void> _renommer() async {
    final session = context.services.session;
    final nom = await demanderTexte(
      context,
      titre: 'Renommer la colocation',
      libelle: 'Nom',
      valeurInitiale: session.courante!.nom,
      valider: (t) => t.length > 60 ? '60 caractères maximum' : null,
    );
    if (nom != null && mounted) {
      await signalerResultat(context, session.renommer(nom));
    }
  }

  Future<void> _regenerer() async {
    final session = context.services.session;
    final ok = await confirmer(
      context,
      titre: 'Nouveau code ?',
      message: "L'ancien code ne fonctionnera plus. Les membres actuels restent dans la colocation.",
      action: 'Régénérer',
    );
    if (ok && mounted) await signalerResultat(context, session.regenererCode());
  }

  Future<void> _retirer(Membre membre) async {
    final session = context.services.session;
    final ok = await confirmer(
      context,
      titre: 'Retirer ${membre.pseudo} ?',
      message:
          'Ses dépenses restent dans l\'historique et dans les soldes. '
          'Pensez à régénérer le code pour l\'empêcher de revenir.',
      action: 'Retirer',
    );
    if (ok && mounted) await signalerResultat(context, session.retirer(membre));
  }

  Future<void> _quitter() async {
    final session = context.services.session;
    final dernier = session.membresActifs.length == 1;
    final ok = await confirmer(
      context,
      titre: 'Quitter la colocation ?',
      message: dernier
          ? 'Vous êtes le dernier membre : la colocation et toutes ses données seront supprimées.'
          : session.suisAdmin
          ? 'Le plus ancien membre deviendra administrateur. Vos dépenses restent dans les soldes.'
          : 'Vos dépenses restent dans l\'historique et dans les soldes.',
      action: 'Quitter',
    );
    if (!ok || !mounted) return;
    final navigateur = Navigator.of(context);
    final erreur = await session.quitter();
    if (!mounted) return;
    if (erreur != null) {
      afficherErreur(context, erreur);
    } else {
      navigateur.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres de la coloc')),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final coloc = session.courante;
          if (coloc == null) return const Chargement();
          final anciens = session.membres.where((m) => !m.estActif).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: Text(coloc.nom, style: theme.textTheme.titleMedium),
                subtitle: const Text('Nom de la colocation'),
                trailing: coloc.suisAdmin
                    ? IconButton(
                        tooltip: 'Renommer',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: _renommer,
                      )
                    : null,
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Code d'invitation",
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              coloc.codeLisible,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                // chiffres à chasse fixe, sans dépendre d'une police « monospace »
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copier',
                            icon: const Icon(Icons.copy),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: coloc.codeInvitation),
                              );
                              if (context.mounted) {
                                afficherInfo(context, 'Code copié');
                              }
                            },
                          ),
                          if (coloc.suisAdmin)
                            IconButton(
                              tooltip: 'Générer un nouveau code',
                              icon: const Icon(Icons.autorenew),
                              onPressed: _regenerer,
                            ),
                        ],
                      ),
                      Text(
                        'Partagez ce code : vos colocataires le saisissent dans « Rejoindre avec un code ».',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              _Titre('Membres (${session.membresActifs.length})'),
              for (final membre in session.membresActifs)
                ListTile(
                  leading: AvatarMembre(utilisateurId: membre.utilisateurId),
                  title: Text(
                    membre.utilisateurId == session.moi
                        ? '${membre.pseudo} (vous)'
                        : membre.pseudo,
                  ),
                  subtitle: Text(
                    'Arrivé ${formaterDate(membre.rejointLe).toLowerCase()}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (membre.estAdmin) const Chip(label: Text('Admin')),
                      if (coloc.suisAdmin &&
                          membre.utilisateurId != session.moi)
                        IconButton(
                          tooltip: 'Retirer de la colocation',
                          icon: Icon(
                            Icons.person_remove_outlined,
                            color: theme.colorScheme.error,
                          ),
                          onPressed: () => _retirer(membre),
                        ),
                    ],
                  ),
                ),
              if (anciens.isNotEmpty) ...[
                const _Titre('Anciens membres'),
                for (final membre in anciens)
                  ListTile(
                    enabled: false,
                    leading: AvatarMembre(utilisateurId: membre.utilisateurId),
                    title: Text(membre.pseudo),
                    subtitle: Text(
                      'Parti ${formaterDate(membre.partiLe!).toLowerCase()}',
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: _quitter,
                  icon: const Icon(Icons.logout),
                  label: const Text('Quitter la colocation'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
    child: Text(texte, style: Theme.of(context).textTheme.titleSmall),
  );
}
