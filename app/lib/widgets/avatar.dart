import 'package:flutter/material.dart';

import '../etat/services.dart';

/// Avatar d'un membre : sa photo (URL signée) ou, à défaut, son initiale.
class AvatarMembre extends StatefulWidget {
  const AvatarMembre({super.key, required this.utilisateurId, this.rayon = 20});

  final String utilisateurId;
  final double rayon;

  @override
  State<AvatarMembre> createState() => _AvatarMembreState();
}

class _AvatarMembreState extends State<AvatarMembre> {
  Future<String>? _url;
  String? _chemin;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mettreAJour();
  }

  @override
  void didUpdateWidget(AvatarMembre ancien) {
    super.didUpdateWidget(ancien);
    _mettreAJour();
  }

  void _mettreAJour() {
    final session = context.services.session;
    final chemin = widget.utilisateurId == session.moi
        ? session.profil?.avatarChemin
        : session.membre(widget.utilisateurId)?.avatarChemin;
    if (chemin != _chemin) {
      _chemin = chemin;
      _url = chemin == null ? null : session.urlAvatar(chemin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    final pseudo = session.pseudo(widget.utilisateurId);
    final couleurs = Theme.of(context).colorScheme;
    final initiale = CircleAvatar(
      radius: widget.rayon,
      backgroundColor: couleurs.primaryContainer,
      child: Text(
        pseudo.isEmpty ? '?' : pseudo.characters.first.toUpperCase(),
        style: TextStyle(
          color: couleurs.onPrimaryContainer,
          fontSize: widget.rayon * 0.8,
        ),
      ),
    );

    final url = _url;
    if (url == null) return initiale;
    return FutureBuilder<String>(
      future: url,
      builder: (context, instantane) {
        if (!instantane.hasData) return initiale;
        return CircleAvatar(
          radius: widget.rayon,
          backgroundColor: couleurs.primaryContainer,
          foregroundImage: NetworkImage(instantane.data!),
          onForegroundImageError: (_, _) {},
          child: initiale.child,
        );
      },
    );
  }
}
