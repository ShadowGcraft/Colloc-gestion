import 'package:flutter/material.dart';

import '../../etat/services.dart';
import '../../widgets/avatar.dart';
import '../../widgets/etats.dart';
import '../../widgets/saisie.dart';

class ProfilPage extends StatefulWidget {
  const ProfilPage({super.key});

  @override
  State<ProfilPage> createState() => _ProfilPageState();
}

class _ProfilPageState extends State<ProfilPage> {
  bool _envoiPhoto = false;

  Future<void> _changerPhoto() async {
    final session = context.services.session;
    final photo = await choisirPhoto(context);
    if (photo == null || !mounted) return;
    setState(() => _envoiPhoto = true);
    final erreur = await session.changerAvatar(photo);
    if (!mounted) return;
    setState(() => _envoiPhoto = false);
    afficherErreur(context, erreur);
  }

  Future<void> _changerPseudo() async {
    final session = context.services.session;
    final pseudo = await demanderTexte(
      context,
      titre: 'Changer de pseudo',
      libelle: 'Pseudo',
      valeurInitiale: session.profil?.pseudo ?? '',
      valider: (t) => t.length > 30 ? '30 caractères maximum' : null,
    );
    if (pseudo != null && mounted) {
      await signalerResultat(context, session.modifierPseudo(pseudo));
    }
  }

  Future<void> _deconnecter() async {
    final services = context.services;
    final navigateur = Navigator.of(context);
    try {
      await services.depots.auth.deconnecter();
    } catch (e) {
      services.reseau.signalerErreur(e);
    }
    navigateur.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final profil = session.profil;
          if (profil == null) return const Chargement();
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    AvatarMembre(utilisateurId: profil.id, rayon: 56),
                    if (_envoiPhoto)
                      const Positioned.fill(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      IconButton.filled(
                        tooltip: 'Changer de photo',
                        onPressed: _changerPhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(profil.pseudo),
                subtitle: const Text('Pseudo'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _changerPseudo,
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: _deconnecter,
                icon: const Icon(Icons.logout),
                label: const Text('Se déconnecter'),
              ),
            ],
          );
        },
      ),
    );
  }
}
