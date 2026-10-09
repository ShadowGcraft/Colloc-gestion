import 'package:flutter/material.dart';

import '../../etat/services.dart';
import '../../modeles/coloc.dart';
import '../../widgets/etats.dart';
import '../../widgets/saisie.dart';
import '../profil/profil_page.dart';

/// Liste de mes colocations : créer, rejoindre avec un code, basculer de l'une à l'autre.
/// [racine] : affichée directement par la PorteEntree (l'utilisateur n'a aucune coloc).
class MesColocsPage extends StatelessWidget {
  const MesColocsPage({super.key, this.racine = false});

  final bool racine;

  Future<void> _creer(BuildContext context) async {
    final session = context.services.session;
    final nom = await demanderTexte(
      context,
      titre: 'Nouvelle colocation',
      libelle: 'Nom de la colocation',
      action: 'Créer',
      valider: (t) => t.length > 60 ? '60 caractères maximum' : null,
    );
    if (nom == null || !context.mounted) return;
    final erreur = await session.creer(nom);
    if (!context.mounted) return;
    afficherErreur(context, erreur);
    if (erreur == null && !racine) Navigator.pop(context);
  }

  Future<void> _rejoindre(BuildContext context) async {
    final session = context.services.session;
    final code = await demanderTexte(
      context,
      titre: 'Rejoindre une colocation',
      libelle: "Code d'invitation",
      aide: 'Demandez-le à un membre (Paramètres de la coloc)',
      action: 'Rejoindre',
      majuscules: TextCapitalization.characters,
      valider: (t) => t.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length != 10
          ? 'Le code contient 10 caractères'
          : null,
    );
    if (code == null || !context.mounted) return;
    final erreur = await session.rejoindre(code);
    if (!context.mounted) return;
    afficherErreur(context, erreur);
    if (erreur == null && !racine) Navigator.pop(context);
  }

  Future<void> _choisir(BuildContext context, Colocation coloc) async {
    final session = context.services.session;
    final erreur = await session.choisir(coloc);
    if (!context.mounted) return;
    afficherErreur(context, erreur);
    if (erreur == null && !racine) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes colocations'),
        actions: [
          if (racine)
            IconButton(
              tooltip: 'Mon profil',
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const ProfilPage()),
              ),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final colocs = session.colocs;
          if (colocs.isEmpty) {
            return EtatVide(
              icone: Icons.holiday_village_outlined,
              titre: "Vous n'avez pas encore de colocation",
              explication: 'Créez-en une et partagez son code, ou rejoignez celle de vos colocataires.',
              action: _Boutons(
                creer: () => _creer(context),
                rejoindre: () => _rejoindre(context),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final coloc in colocs)
                ListTile(
                  leading: CircleAvatar(
                    child: Text(coloc.nom.characters.first.toUpperCase()),
                  ),
                  title: Text(coloc.nom),
                  subtitle: Text(coloc.suisAdmin ? 'Administrateur' : 'Membre'),
                  trailing: coloc.id == session.courante?.id
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () => _choisir(context, coloc),
                ),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _Boutons(
                  creer: () => _creer(context),
                  rejoindre: () => _rejoindre(context),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Boutons extends StatelessWidget {
  const _Boutons({required this.creer, required this.rejoindre});

  final VoidCallback creer;
  final VoidCallback rejoindre;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 12,
    runSpacing: 12,
    children: [
      FilledButton.icon(
        onPressed: creer,
        icon: const Icon(Icons.add),
        label: const Text('Créer'),
      ),
      OutlinedButton.icon(
        onPressed: rejoindre,
        icon: const Icon(Icons.vpn_key_outlined),
        label: const Text('Rejoindre avec un code'),
      ),
    ],
  );
}
