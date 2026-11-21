import 'package:fl_clash/common/service_probe.dart';
import 'package:flutter/foundation.dart';

/// Built-in zero-key IP intelligence & risk evaluation sources.
enum IpInsightSource {
  ipPure('IPPure', 'ippure.com', 1.3),
  proxyCheck('ProxyCheck', 'proxycheck.io', 1.2),
  ipLocate('IPLocate', 'iplocate.io', 1.1),
  ipQuery('IPQuery', 'ipquery.io', 0.9),
  scamalytics('Scamalytics', 'scamalytics.com', 1.3),
  ipApiCom('IP-API', 'ip-api.com', 0.8),
  ipApiIs('ipapi.is', 'ipapi.is', 1.0);

  const IpInsightSource(this.label, this.domain, this.weight);

  final String label;
  final String domain;
  final double weight;
}

/// Network / ASN classification of an IP address.
enum IpNetworkKind {
  residential,
  mobile,
  business,
  education,
  hosting,
  unknown,
}

/// Whether the IP is natively registered to its physical country or announced
/// (broadcast) from another registration country.
enum IpBroadcastKind {
  nativeIp,
  broadcast,
  unknown,
}

/// Five-tier purity classification derived from the 0–100 composite score.
enum IpPurityGrade {
  /// 85–100: Minimal risk, ideal for strict AI / streaming / account workflows.
  pristine,

  /// 70–84: Low risk, stable for everyday AI and media usage.
  clean,

  /// 50–69: Typical datacenter or broadcast range; some strict sites may challenge.
  moderate,

  /// 30–49: Elevated risk / abuse / proxy signals; frequent CAPTCHAs or limits.
  polluted,

  /// 0–29: Severe risk / blocklist / Tor / abuser; switching node is recommended.
  severe,
}

enum IpSourceProbeStatus {
  ok,
  rateLimited,
  timeout,
  failed,
}

/// Grouping for tool & service unlock checks.
enum ToolCategory {
  ai([
    ServiceTarget.chatgpt,
    ServiceTarget.claude,
    ServiceTarget.gemini,
    ServiceTarget.perplexity,
    ServiceTarget.copilot,
    ServiceTarget.grok,
  ]),
  streaming([
    ServiceTarget.netflix,
    ServiceTarget.disneyPlus,
    ServiceTarget.youtube,
    ServiceTarget.tiktok,
    ServiceTarget.primeVideo,
    ServiceTarget.spotify,
  ]),
  general([
    ServiceTarget.google,
    ServiceTarget.github,
    ServiceTarget.discord,
    ServiceTarget.bilibili,
  ]);

  const ToolCategory(this.targets);

  final List<ServiceTarget> targets;

  static List<ServiceTarget> get allTargets => [
    for (final category in values) ...category.targets,
  ];
}

@immutable
class IpSourceVerdict {
  const IpSourceVerdict({
    required this.source,
    required this.status,
    this.latencyMs,
    this.networkKind = IpNetworkKind.unknown,
    this.inferredType = false,
    this.isBroadcast,
    this.riskScore,
    this.countryCode,
    this.countryName,
    this.asnCountryCode,
    this.city,
    this.asn,
    this.organization,
    this.isProxy = false,
    this.isVpn = false,
    this.isTor = false,
    this.isAbuser = false,
    this.isCompromised = false,
    this.isScraper = false,
    this.isHosting = false,
    this.isMobile = false,
    this.note,
  });

  final IpInsightSource source;
  final IpSourceProbeStatus status;
  final int? latencyMs;
  final IpNetworkKind networkKind;
  final bool inferredType;
  final bool? isBroadcast;

  /// Normalized 0–100 risk / fraud score where 0 is cleanest and 100 is highest risk.
  final int? riskScore;
  final String? countryCode;
  final String? countryName;
  final String? asnCountryCode;
  final String? city;
  final int? asn;
  final String? organization;
  final bool isProxy;
  final bool isVpn;
  final bool isTor;
  final bool isAbuser;
  final bool isCompromised;
  final bool isScraper;
  final bool isHosting;
  final bool isMobile;
  final String? note;

  bool get succeeded => status == IpSourceProbeStatus.ok;
}

@immutable
class IpScoreBreakdown {
  const IpScoreBreakdown({
    this.baseScore = 100,
    required this.networkAdjustment,
    required this.riskPenalty,
    required this.anonymityPenalty,
    required this.broadcastPenalty,
    required this.consensusBonus,
    required this.weightedRiskScore,
    required this.finalScore,
  });

  final int baseScore;
  final int networkAdjustment;
  final int riskPenalty;
  final int anonymityPenalty;
  final int broadcastPenalty;
  final int consensusBonus;
  final double weightedRiskScore;
  final int finalScore;
}

@immutable
class IpRiskFlags {
  const IpRiskFlags({
    this.isProxy = false,
    this.isVpn = false,
    this.isTor = false,
    this.isAbuser = false,
    this.isCompromised = false,
    this.isScraper = false,
  });

  final bool isProxy;
  final bool isVpn;
  final bool isTor;
  final bool isAbuser;
  final bool isCompromised;
  final bool isScraper;

  bool get hasAny =>
      isProxy || isVpn || isTor || isAbuser || isCompromised || isScraper;
}

@immutable
class IpInsightReport {
  const IpInsightReport({
    required this.ip,
    required this.isIpv6,
    required this.networkKind,
    required this.broadcastKind,
    required this.score,
    required this.grade,
    required this.breakdown,
    required this.flags,
    required this.verdicts,
    required this.checkedAt,
    this.countryCode,
    this.countryName,
    this.asnCountryCode,
    this.city,
    this.asn,
    this.organization,
    this.fromCache = false,
  });

  final String ip;
  final bool isIpv6;
  final String? countryCode;
  final String? countryName;
  final String? asnCountryCode;
  final String? city;
  final int? asn;
  final String? organization;
  final IpNetworkKind networkKind;
  final IpBroadcastKind broadcastKind;
  final int score;
  final IpPurityGrade grade;
  final IpScoreBreakdown breakdown;
  final IpRiskFlags flags;
  final List<IpSourceVerdict> verdicts;
  final DateTime checkedAt;
  final bool fromCache;

  int get succeededSourceCount => verdicts.where((v) => v.succeeded).length;

  IpInsightReport copyWith({bool? fromCache}) {
    return IpInsightReport(
      ip: ip,
      isIpv6: isIpv6,
      countryCode: countryCode,
      countryName: countryName,
      asnCountryCode: asnCountryCode,
      city: city,
      asn: asn,
      organization: organization,
      networkKind: networkKind,
      broadcastKind: broadcastKind,
      score: score,
      grade: grade,
      breakdown: breakdown,
      flags: flags,
      verdicts: verdicts,
      checkedAt: checkedAt,
      fromCache: fromCache ?? this.fromCache,
    );
  }
}
