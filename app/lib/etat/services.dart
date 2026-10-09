import 'package:flutter/widgets.dart';

import '../donnees/depots.dart';
import 'reseau.dart';
import 'session.dart';

/// Ce dont les écrans ont besoin, fourni une seule fois en haut de l'arbre
/// (InheritedWidget, inclus dans Flutter : pas de package de gestion d'état).
class Services {
  const Services({
    required this.depots,
    required this.session,
    required this.reseau,
  });

  final Depots depots;
  final Session session;
  final EtatReseau reseau;
}

class ServicesScope extends InheritedWidget {
  const ServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final Services services;

  static Services of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ServicesScope>();
    assert(scope != null, 'ServicesScope absent de l\'arbre des widgets');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(ServicesScope oldWidget) =>
      services != oldWidget.services;
}

extension AccesServices on BuildContext {
  Services get services => ServicesScope.of(this);
}
