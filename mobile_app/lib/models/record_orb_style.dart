enum RecordOrbStyle {
  radialBars(
    id: 'radial',
    label: 'A — Barre radiali',
    description: 'Onde concentriche + visualizer circolare. Attuale default.',
  ),
  organicBlob(
    id: 'blob',
    label: 'B — Blob organico',
    description: 'Forma liquida che si deforma con la voce.',
  ),
  gradientFluid(
    id: 'gradient',
    label: 'C — Gradiente fluido',
    description: 'Orb multicolore rotante, più vicino a Siri.',
  ),
  classicPulse(
    id: 'classic',
    label: 'Classico',
    description: 'Pulsazione semplice, stile precedente.',
  );

  const RecordOrbStyle({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;

  static RecordOrbStyle fromId(String? id) {
    if (id == null) return RecordOrbStyle.gradientFluid;
    return RecordOrbStyle.values.firstWhere(
      (s) => s.id == id,
      orElse: () => RecordOrbStyle.gradientFluid,
    );
  }
}
