/// Features planned to become part of a future CoPaw Plus tier.
///
/// Every one of them is fully available to everyone today. There is no billing,
/// no entitlement check, no usage cap, and nothing in the interface mentions
/// payment. The marker exists so the tier boundary is recorded in one place
/// while the features are built, instead of having to be rediscovered later.
enum PlusFeature {
  /// Search the household's full history instead of only the current day.
  longTermSearch,

  /// Choose the range and the sections a report contains.
  customReport,

  /// A source-attributed pack for a veterinarian visit or a caregiver handoff.
  vetVisitPack,

  /// A summary of where care coverage has gaps.
  careCoverageSummary,
}

/// Decides whether a [PlusFeature] is available.
///
/// The current implementation grants every feature to every household. It is a
/// seam, not a gate: introducing a paid tier means replacing this class, not
/// rewriting each feature.
final class PlusFeatureAccess {
  const PlusFeatureAccess();

  bool isAvailable(PlusFeature feature) => true;

  Set<PlusFeature> get availableFeatures => PlusFeature.values.toSet();
}
