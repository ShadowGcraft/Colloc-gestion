/// Répartition en parts égales, identique à celle de la RPC `creer_depense`
/// (sert à afficher l'aperçu des parts dans le formulaire avant l'envoi).
///
/// Les centimes restants vont, un par un, aux premiers participants triés par
/// identifiant : 1000 centimes entre 3 → 334, 333, 333.
Map<String, int> repartirEgalement(int totalCentimes, Iterable<String> participants) {
  final tries = participants.toSet().toList()..sort();
  if (tries.isEmpty) return {};

  final base = totalCentimes ~/ tries.length;
  final reste = totalCentimes % tries.length;
  return {
    for (var i = 0; i < tries.length; i++) tries[i]: base + (i < reste ? 1 : 0),
  };
}
