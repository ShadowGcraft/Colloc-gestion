import 'package:flutter/material.dart';

/// Les trois états communs à tous les écrans : chargement, vide, erreur.

class Chargement extends StatelessWidget {
  const Chargement({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        if (message != null) ...[const SizedBox(height: 16), Text(message!)],
      ],
    ),
  );
}

class EtatVide extends StatelessWidget {
  const EtatVide({
    super.key,
    required this.icone,
    required this.titre,
    this.explication,
    this.action,
  });

  final IconData icone;
  final String titre;
  final String? explication;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Centre(
      children: [
        Icon(
          icone,
          size: 72,
          color: theme.colorScheme.primary.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 16),
        Text(
          titre,
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        if (explication != null) ...[
          const SizedBox(height: 8),
          Text(
            explication!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (action != null) ...[const SizedBox(height: 24), action!],
      ],
    );
  }
}

class EtatErreur extends StatelessWidget {
  const EtatErreur({super.key, required this.message, required this.reessayer});

  final String message;
  final VoidCallback reessayer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Centre(
      children: [
        Icon(
          Icons.cloud_off_outlined,
          size: 72,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          onPressed: reessayer,
          icon: const Icon(Icons.refresh),
          label: const Text('Réessayer'),
        ),
      ],
    );
  }
}

/// Choisit quoi afficher selon l'état d'un écran de liste.
class VueListe extends StatelessWidget {
  const VueListe({
    super.key,
    required this.chargement,
    required this.erreur,
    required this.estVide,
    required this.vide,
    required this.reessayer,
    required this.contenu,
  });

  final bool chargement;
  final String? erreur;

  /// null tant que rien n'a jamais été chargé
  final bool? estVide;
  final Widget vide;
  final VoidCallback reessayer;
  final Widget Function() contenu;

  @override
  Widget build(BuildContext context) {
    if (estVide == null) {
      return erreur != null
          ? EtatErreur(message: erreur!, reessayer: reessayer)
          : const Chargement();
    }
    // données déjà affichées : en cas d'erreur de rechargement, on les garde (SnackBar ou bandeau)
    return estVide! ? vide : contenu();
  }
}

class _Centre extends StatelessWidget {
  const _Centre({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

/// Affiche une erreur d'action (null = rien à afficher).
void afficherErreur(BuildContext context, String? message) {
  if (message == null || !context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
        showCloseIcon: true,
        closeIconColor: Theme.of(context).colorScheme.onErrorContainer,
      ),
    );
}

/// Attend le résultat d'une action (message d'erreur ou null) et l'affiche si besoin.
Future<void> signalerResultat(
  BuildContext context,
  Future<String?> action,
) async {
  final erreur = await action;
  if (context.mounted) afficherErreur(context, erreur);
}

void afficherInfo(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Boîte de confirmation pour les actions destructives.
Future<bool> confirmer(
  BuildContext context, {
  required String titre,
  required String message,
  String action = 'Supprimer',
}) async {
  final reponse = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titre),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return reponse ?? false;
}
