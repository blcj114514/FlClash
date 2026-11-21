import 'dart:math' as math;

import 'models.dart';

/// Aggregates multi-source verdicts into a deterministic 0–100 purity score,
/// consensus IP classification, native/broadcast status, and detailed breakdown.
IpInsightReport evaluateIpInsight({
  required String ip,
  required List<IpSourceVerdict> verdicts,
  DateTime? checkedAt,
  bool fromCache = false,
}) {
  final ok = verdicts.where((v) => v.succeeded).toList();
  final networkKind = _resolveNetworkKind(ok);
  final countryCode = _pickMostFrequent(
    ok.map((v) => v.countryCode?.toUpperCase()),
  );
  final countryName = _pickFirstNonEmpty(ok.map((v) => v.countryName));
  final city = _pickFirstNonEmpty(ok.map((v) => v.city));
  final asnCountryCode = _pickFirstNonEmpty(
    ok.map((v) => v.asnCountryCode?.toUpperCase()),
  );
  final asn = _pickFirstInt(ok.map((v) => v.asn));
  final organization = _pickFirstNonEmpty(ok.map((v) => v.organization));
  final broadcastKind = _resolveBroadcastKind(
    ok,
    countryCode: countryCode,
    asnCountryCode: asnCountryCode,
  );
  final flags = _resolveFlags(ok);
  final weightedRisk = _computeWeightedRiskScore(ok, networkKind, flags);

  final networkAdjustment = switch (networkKind) {
    IpNetworkKind.residential => 0,
    IpNetworkKind.mobile => -2,
    IpNetworkKind.education => -4,
    IpNetworkKind.business => -6,
    IpNetworkKind.hosting => -18,
    IpNetworkKind.unknown => -8,
  };

  final riskPenalty = -(weightedRisk * 0.48).round().clamp(0, 48);

  var rawAnonymityPenalty = 0;
  if (flags.isTor) rawAnonymityPenalty += 28;
  if (flags.isAbuser) rawAnonymityPenalty += 25;
  if (flags.isCompromised || flags.isScraper) rawAnonymityPenalty += 20;
  if (flags.isProxy) rawAnonymityPenalty += 12;
  if (flags.isVpn) rawAnonymityPenalty += 10;
  final anonymityPenalty = -math.min(rawAnonymityPenalty, 40);

  final broadcastPenalty = switch (broadcastKind) {
    IpBroadcastKind.broadcast => -7,
    IpBroadcastKind.nativeIp || IpBroadcastKind.unknown => 0,
  };

  var consensusBonus = 0;
  if (ok.length >= 4 && weightedRisk <= 15 && !flags.hasAny) {
    consensusBonus = 4;
  } else if (ok.length >= 3 && weightedRisk <= 25 && !flags.hasAny) {
    consensusBonus = 2;
  }

  final rawScore =
      100 +
      networkAdjustment +
      riskPenalty +
      anonymityPenalty +
      broadcastPenalty +
      consensusBonus;
  final finalScore = ok.isEmpty ? 0 : rawScore.clamp(0, 100);
  final grade = gradeForScore(finalScore);

  return IpInsightReport(
    ip: ip,
    isIpv6: ip.contains(':'),
    countryCode: countryCode,
    countryName: countryName,
    asnCountryCode: asnCountryCode,
    city: city,
    asn: asn,
    organization: organization,
    networkKind: networkKind,
    broadcastKind: broadcastKind,
    score: finalScore,
    grade: grade,
    breakdown: IpScoreBreakdown(
      networkAdjustment: networkAdjustment,
      riskPenalty: riskPenalty,
      anonymityPenalty: anonymityPenalty,
      broadcastPenalty: broadcastPenalty,
      consensusBonus: consensusBonus,
      weightedRiskScore: weightedRisk,
      finalScore: finalScore,
    ),
    flags: flags,
    verdicts: List.unmodifiable(verdicts),
    checkedAt: checkedAt ?? DateTime.now(),
    fromCache: fromCache,
  );
}

IpPurityGrade gradeForScore(int score) {
  if (score >= 85) return IpPurityGrade.pristine;
  if (score >= 70) return IpPurityGrade.clean;
  if (score >= 50) return IpPurityGrade.moderate;
  if (score >= 30) return IpPurityGrade.polluted;
  return IpPurityGrade.severe;
}

IpNetworkKind _resolveNetworkKind(List<IpSourceVerdict> ok) {
  if (ok.isEmpty) return IpNetworkKind.unknown;

  final weights = <IpNetworkKind, double>{};
  for (final verdict in ok) {
    if (verdict.networkKind == IpNetworkKind.unknown) continue;
    final factor = verdict.inferredType ? 0.55 : 1.0;
    final weight = verdict.source.weight * factor;
    weights.update(
      verdict.networkKind,
      (value) => value + weight,
      ifAbsent: () => weight,
    );
  }
  if (weights.isEmpty) {
    if (ok.any((v) => v.isHosting)) return IpNetworkKind.hosting;
    if (ok.any((v) => v.isMobile)) return IpNetworkKind.mobile;
    return IpNetworkKind.unknown;
  }

  // Prefer explicit hosting classification when multiple independent sources
  // agree on datacenter/hosting, preventing inferred residential fallbacks from
  // masking IDC subnets.
  final hostingVotes = ok
      .where((v) => v.networkKind == IpNetworkKind.hosting || v.isHosting)
      .length;
  final residentialExplicit = ok
      .where(
        (v) => v.networkKind == IpNetworkKind.residential && !v.inferredType,
      )
      .length;
  if (hostingVotes >= 2 && residentialExplicit == 0) {
    return IpNetworkKind.hosting;
  }

  IpNetworkKind best = IpNetworkKind.unknown;
  var bestScore = -1.0;
  for (final entry in weights.entries) {
    if (entry.value > bestScore) {
      bestScore = entry.value;
      best = entry.key;
    }
  }
  return best;
}

IpBroadcastKind _resolveBroadcastKind(
  List<IpSourceVerdict> ok, {
  required String? countryCode,
  required String? asnCountryCode,
}) {
  var broadcastVotes = 0;
  var nativeVotes = 0;

  for (final verdict in ok) {
    if (verdict.isBroadcast == true) {
      broadcastVotes += 2;
    } else if (verdict.isBroadcast == false) {
      nativeVotes += 2;
    }
  }

  if (countryCode != null &&
      countryCode.isNotEmpty &&
      asnCountryCode != null &&
      asnCountryCode.isNotEmpty) {
    if (countryCode != asnCountryCode) {
      broadcastVotes += 1;
    } else {
      nativeVotes += 1;
    }
  }

  if (broadcastVotes == 0 && nativeVotes == 0) {
    return IpBroadcastKind.unknown;
  }
  return broadcastVotes >= nativeVotes
      ? IpBroadcastKind.broadcast
      : IpBroadcastKind.nativeIp;
}

IpRiskFlags _resolveFlags(List<IpSourceVerdict> ok) {
  return IpRiskFlags(
    isProxy: ok.any((v) => v.isProxy),
    isVpn: ok.any((v) => v.isVpn),
    isTor: ok.any((v) => v.isTor),
    isAbuser: ok.any((v) => v.isAbuser),
    isCompromised: ok.any((v) => v.isCompromised),
    isScraper: ok.any((v) => v.isScraper),
  );
}

double _computeWeightedRiskScore(
  List<IpSourceVerdict> ok,
  IpNetworkKind kind,
  IpRiskFlags flags,
) {
  var totalWeight = 0.0;
  var weightedSum = 0.0;
  for (final verdict in ok) {
    final score = verdict.riskScore;
    if (score == null) continue;
    final clamped = score.clamp(0, 100);
    weightedSum += clamped * verdict.source.weight;
    totalWeight += verdict.source.weight;
  }
  if (totalWeight > 0) {
    return weightedSum / totalWeight;
  }

  // Fallback inference when no numeric risk-scoring endpoint responded.
  var fallback = kind == IpNetworkKind.hosting ? 28.0 : 8.0;
  if (flags.isTor) fallback += 45;
  if (flags.isAbuser) fallback += 40;
  if (flags.isCompromised || flags.isScraper) fallback += 30;
  if (flags.isProxy) fallback += 18;
  if (flags.isVpn) fallback += 14;
  return fallback.clamp(0, 100);
}

String? _pickMostFrequent(Iterable<String?> values) {
  final counts = <String, int>{};
  for (final raw in values) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) continue;
    counts.update(value, (c) => c + 1, ifAbsent: () => 1);
  }
  if (counts.isEmpty) return null;
  String? best;
  var bestCount = -1;
  for (final entry in counts.entries) {
    if (entry.value > bestCount) {
      bestCount = entry.value;
      best = entry.key;
    }
  }
  return best;
}

String? _pickFirstNonEmpty(Iterable<String?> values) {
  for (final raw in values) {
    final value = raw?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

int? _pickFirstInt(Iterable<int?> values) {
  for (final value in values) {
    if (value != null && value > 0) return value;
  }
  return null;
}
