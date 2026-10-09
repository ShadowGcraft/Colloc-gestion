import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../modeles/argent.dart';

/// Boîte de dialogue avec un champ texte. Renvoie null si l'utilisateur annule.
Future<String?> demanderTexte(
  BuildContext context, {
  required String titre,
  required String libelle,
  String valeurInitiale = '',
  String action = 'Valider',
  String? aide,
  String? Function(String)? valider,
  TextCapitalization majuscules = TextCapitalization.sentences,
}) => showDialog<String>(
  context: context,
  builder: (context) => _DialogueTexte(
    titre: titre,
    libelle: libelle,
    valeurInitiale: valeurInitiale,
    action: action,
    aide: aide,
    valider: valider,
    majuscules: majuscules,
  ),
);

class _DialogueTexte extends StatefulWidget {
  const _DialogueTexte({
    required this.titre,
    required this.libelle,
    required this.valeurInitiale,
    required this.action,
    required this.aide,
    required this.valider,
    required this.majuscules,
  });

  final String titre;
  final String libelle;
  final String valeurInitiale;
  final String action;
  final String? aide;
  final String? Function(String)? valider;
  final TextCapitalization majuscules;

  @override
  State<_DialogueTexte> createState() => _DialogueTexteState();
}

class _DialogueTexteState extends State<_DialogueTexte> {
  late final _controleur = TextEditingController(text: widget.valeurInitiale);
  final _formulaire = GlobalKey<FormState>();

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _valider() {
    if (_formulaire.currentState!.validate()) {
      Navigator.pop(context, _controleur.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.titre),
    content: Form(
      key: _formulaire,
      child: TextFormField(
        controller: _controleur,
        autofocus: true,
        textCapitalization: widget.majuscules,
        decoration: InputDecoration(
          labelText: widget.libelle,
          helperText: widget.aide,
        ),
        validator: (v) {
          final texte = (v ?? '').trim();
          if (texte.isEmpty) return 'Ce champ est obligatoire';
          return widget.valider?.call(texte);
        },
        onFieldSubmitted: (_) => _valider(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _valider, child: Text(widget.action)),
    ],
  );
}

/// Propose l'appareil photo (si disponible) ou la galerie, et renvoie l'image choisie.
Future<PhotoTicket?> choisirPhoto(BuildContext context) async {
  final selecteur = ImagePicker();
  final sources = [
    if (selecteur.supportsImageSource(ImageSource.camera)) ImageSource.camera,
    ImageSource.gallery,
  ];

  final source = sources.length == 1
      ? sources.first
      : await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Prendre une photo'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choisir dans la galerie'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
  if (source == null) return null;

  // image réduite et recompressée : plus légère à envoyer et à stocker
  final fichier = await selecteur.pickImage(
    source: source,
    maxWidth: 1600,
    imageQuality: 80,
  );
  if (fichier == null) return null;

  final nom = fichier.name.toLowerCase();
  final typeMime =
      fichier.mimeType ??
      (nom.endsWith('.png')
          ? 'image/png'
          : nom.endsWith('.webp')
          ? 'image/webp'
          : 'image/jpeg');
  return PhotoTicket(octets: await fichier.readAsBytes(), typeMime: typeMime);
}
