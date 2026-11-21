import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'models.dart';
import 'scoring.dart';

/// Parallel zero-key multi-source IP quality evaluator with in-memory TTL cache.
class IpInsightEvaluator {
  IpInsightEvaluator({
    this.timeout = const Duration(seconds: 8),
    this.cacheTtl = const Duration(minutes: 15),
  });

  final Duration timeout;
  final Duration cacheTtl;

  final _cache = <String, IpInsightReport>{};

  IpInsightReport? cached(String ip) {
    final existing = _cache[ip];
    if (existing == null) return null;
    if (DateTime.now().difference(existing.checkedAt) > cacheTtl) {
      _cache.remove(ip);
      return null;
    }
    return existing.copyWith(fromCache: true);
  }

  void clearCache([String? ip]) {
    if (ip == null) {
      _cache.clear();
    } else {
      _cache.remove(ip);
    }
  }

  /// Queries all built-in zero-key sources in parallel and aggregates them.
  Future<IpInsightReport> evaluate(
    Dio dio,
    String ip, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
    if (!forceRefresh) {
      final hit = cached(ip);
      if (hit != null) return hit;
    }

    final verdicts = await Future.wait([
      for (final source in IpInsightSource.values)
        _probeSource(dio, source, ip, cancelToken: cancelToken),
    ]);

    final report = evaluateIpInsight(
      ip: ip,
      verdicts: verdicts,
      checkedAt: DateTime.now(),
    );
    if (report.succeededSourceCount > 0) {
      _cache[ip] = report;
    }
    return report;
  }

  Future<IpSourceVerdict> _probeSource(
    Dio dio,
    IpInsightSource source,
    String ip, {
    CancelToken? cancelToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await dio
          .get<String>(
            _urlFor(source, ip),
            cancelToken: cancelToken,
            options: Options(
              responseType: ResponseType.plain,
              validateStatus: (_) => true,
            ),
          )
          .timeout(timeout);
      stopwatch.stop();

      if (response.statusCode == HttpStatus.tooManyRequests) {
        return IpSourceVerdict(
          source: source,
          status: IpSourceProbeStatus.rateLimited,
          latencyMs: stopwatch.elapsedMilliseconds,
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        return IpSourceVerdict(
          source: source,
          status: IpSourceProbeStatus.failed,
          latencyMs: stopwatch.elapsedMilliseconds,
        );
      }
      final body = response.data ?? '';
      return _parseResponse(
        source,
        ip,
        body,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } on TimeoutException {
      stopwatch.stop();
      return IpSourceVerdict(
        source: source,
        status: IpSourceProbeStatus.timeout,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } on DioException catch (error) {
      stopwatch.stop();
      final isTimeout =
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout;
      return IpSourceVerdict(
        source: source,
        status: isTimeout
            ? IpSourceProbeStatus.timeout
            : IpSourceProbeStatus.failed,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (_) {
      stopwatch.stop();
      return IpSourceVerdict(
        source: source,
        status: IpSourceProbeStatus.failed,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }
}

String _urlFor(IpInsightSource source, String ip) {
  final encodedIp = Uri.encodeComponent(ip);
  return switch (source) {
    IpInsightSource.ipPure => 'https://my.ippure.com/v1/info',
    IpInsightSource.proxyCheck => 'https://proxycheck.io/v3/$encodedIp',
    IpInsightSource.ipLocate => 'https://iplocate.io/api/lookup/$encodedIp',
    IpInsightSource.ipQuery => 'https://api.ipquery.io/$encodedIp',
    IpInsightSource.scamalytics => 'https://scamalytics.com/ip/$encodedIp',
    IpInsightSource.ipApiCom =>
      'http://ip-api.com/json/$encodedIp?fields=status,country,countryCode,city,isp,org,as,mobile,proxy,hosting,query',
    IpInsightSource.ipApiIs => 'https://api.ipapi.is/?q=$encodedIp',
  };
}

IpSourceVerdict _parseResponse(
  IpInsightSource source,
  String ip,
  String body, {
  required int latencyMs,
}) {
  if (source == IpInsightSource.scamalytics) {
    return _parseScamalyticsHtml(body, latencyMs: latencyMs);
  }
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    return IpSourceVerdict(
      source: source,
      status: IpSourceProbeStatus.failed,
      latencyMs: latencyMs,
    );
  }
  return switch (source) {
    IpInsightSource.ipPure => _parseIpPure(ip, decoded, latencyMs: latencyMs),
    IpInsightSource.proxyCheck => _parseProxyCheck(
      ip,
      decoded,
      latencyMs: latencyMs,
    ),
    IpInsightSource.ipLocate => _parseIpLocate(decoded, latencyMs: latencyMs),
    IpInsightSource.ipQuery => _parseIpQuery(decoded, latencyMs: latencyMs),
    IpInsightSource.ipApiCom => _parseIpApiCom(decoded, latencyMs: latencyMs),
    IpInsightSource.ipApiIs => _parseIpApiIs(decoded, latencyMs: latencyMs),
    IpInsightSource.scamalytics => _parseScamalyticsHtml(
      body,
      latencyMs: latencyMs,
    ),
  };
}

IpSourceVerdict _parseIpPure(
  String expectedIp,
  Map<String, dynamic> json, {
  required int latencyMs,
}) {
  final seenIp = _str(json['ip']);
  if (seenIp != null && seenIp != expectedIp) {
    return IpSourceVerdict(
      source: IpInsightSource.ipPure,
      status: IpSourceProbeStatus.failed,
      latencyMs: latencyMs,
      note: 'IP mismatch ($seenIp)',
    );
  }
  final isResidential = json['isResidential'] == true;
  final isBroadcast = json['isBroadcast'] is bool
      ? json['isBroadcast'] as bool
      : null;
  final fraudScore = _int(json['fraudScore'])?.clamp(0, 100);
  return IpSourceVerdict(
    source: IpInsightSource.ipPure,
    status: IpSourceProbeStatus.ok,
    latencyMs: latencyMs,
    networkKind: isResidential
        ? IpNetworkKind.residential
        : IpNetworkKind.hosting,
    isBroadcast: isBroadcast,
    riskScore: fraudScore,
    countryCode: _str(json['countryCode']),
    countryName: _str(json['country']),
    city: _str(json['city']),
    asn: _asn(json['asn']),
    organization: _str(json['asOrganization']),
    isHosting: !isResidential,
    note: fraudScore != null ? 'Fraud $fraudScore' : null,
  );
}

IpSourceVerdict _parseProxyCheck(
  String ip,
  Map<String, dynamic> json, {
  required int latencyMs,
}) {
  final status = _str(json['status']);
  if (status == 'denied') {
    return IpSourceVerdict(
      source: IpInsightSource.proxyCheck,
      status: IpSourceProbeStatus.rateLimited,
      latencyMs: latencyMs,
    );
  }
  if (status != 'ok' && status != 'warning') {
    return IpSourceVerdict(
      source: IpInsightSource.proxyCheck,
      status: IpSourceProbeStatus.failed,
      latencyMs: latencyMs,
    );
  }
  final entry = _map(json[ip]);
  final network = _map(entry['network']);
  final location = _map(entry['location']);
  final detections = _map(entry['detections']);
  final rawType = _str(network['type']);
  final isHosting = _bool(detections['hosting']) || rawType == 'Hosting';
  final isMobile = rawType == 'Wireless';
  final kind = _pickNetworkKind(
    isHosting: isHosting,
    isMobile: isMobile,
    declared: switch (rawType) {
      'Residential' => IpNetworkKind.residential,
      'Business' => IpNetworkKind.business,
      'Education' => IpNetworkKind.education,
      'Hosting' => IpNetworkKind.hosting,
      _ => null,
    },
  );
  final risk = _int(detections['risk'])?.clamp(0, 100);
  return IpSourceVerdict(
    source: IpInsightSource.proxyCheck,
    status: IpSourceProbeStatus.ok,
    latencyMs: latencyMs,
    networkKind: kind,
    riskScore: risk,
    countryCode: _str(location['country_code']),
    countryName: _str(location['country_name']),
    city: _str(location['city_name']),
    asn: _asn(network['asn']),
    organization: _str(network['organisation']) ?? _str(network['provider']),
    isProxy: _bool(detections['proxy']),
    isVpn: _bool(detections['vpn']),
    isTor: _bool(detections['tor']),
    isCompromised: _bool(detections['compromised']),
    isScraper: _bool(detections['scraper']),
    isHosting: isHosting,
    isMobile: isMobile,
    note: risk != null ? 'Risk $risk' : rawType,
  );
}

IpSourceVerdict _parseIpLocate(
  Map<String, dynamic> json, {
  required int latencyMs,
}) {
  final privacy = _map(json['privacy']);
  final company = _map(json['company']);
  final asnObj = _map(json['asn']);
  final isHosting = _bool(privacy['is_hosting']);
  final declared =
      _declaredKind(_str(company['type'])) ??
      _declaredKind(_str(asnObj['type']));
  final kind = _pickNetworkKind(isHosting: isHosting, declared: declared);
  final geoCc = _str(json['country_code'])?.toUpperCase();
  final asnCc = _str(asnObj['country_code'])?.toUpperCase();
  final isBroadcast = geoCc != null && asnCc != null ? geoCc != asnCc : null;
  return IpSourceVerdict(
    source: IpInsightSource.ipLocate,
    status: IpSourceProbeStatus.ok,
    latencyMs: latencyMs,
    networkKind: kind,
    isBroadcast: isBroadcast,
    countryCode: geoCc,
    countryName: _str(json['country']),
    asnCountryCode: asnCc,
    city: _str(json['city']),
    asn: _asn(asnObj['asn']),
    organization: _str(company['name']) ?? _str(asnObj['name']),
    isProxy: _bool(privacy['is_proxy']),
    isVpn: _bool(privacy['is_vpn']),
    isTor: _bool(privacy['is_tor']),
    isAbuser: _bool(privacy['is_abuser']),
    isHosting: isHosting,
    note: asnCc != null && geoCc != null && asnCc != geoCc
        ? 'ASN $asnCc -> $geoCc'
        : _str(company['type']),
  );
}

IpSourceVerdict _parseIpQuery(
  Map<String, dynamic> json, {
  required int latencyMs,
}) {
  final risk = _map(json['risk']);
  final isp = _map(json['isp']);
  final location = _map(json['location']);
  final isHosting = _bool(risk['is_datacenter']);
  final isMobile = _bool(risk['is_mobile']);
  final explicit = _pickNetworkKind(isHosting: isHosting, isMobile: isMobile);
  final inferred = explicit == IpNetworkKind.unknown;
  final riskScore = _int(risk['risk_score'])?.clamp(0, 100);
  return IpSourceVerdict(
    source: IpInsightSource.ipQuery,
    status: IpSourceProbeStatus.ok,
    latencyMs: latencyMs,
    networkKind: inferred ? IpNetworkKind.residential : explicit,
    inferredType: inferred,
    riskScore: riskScore,
    countryCode: _str(location['country_code']),
    countryName: _str(location['country']),
    city: _str(location['city']),
    asn: _asn(isp['asn']),
    organization: _str(isp['org']) ?? _str(isp['isp']),
    isProxy: _bool(risk['is_proxy']),
    isVpn: _bool(risk['is_vpn']),
    isTor: _bool(risk['is_tor']),
    isHosting: isHosting,
    isMobile: isMobile,
    note: riskScore != null ? 'Risk $riskScore' : null,
  );
}

IpSourceVerdict _parseIpApiCom(
  Map<String, dynamic> json, {
  required int latencyMs,
}) {
  if (_str(json['status']) != 'success') {
    return IpSourceVerdict(
      source: IpInsightSource.ipApiCom,
      status: IpSourceProbeStatus.failed,
      latencyMs: latencyMs,
    );
  }
  final isHosting = _bool(json['hosting']);
  final isMobile = _bool(json['mobile']);
  final explicit = _pickNetworkKind(isHosting: isHosting, isMobile: isMobile);
  final inferred = explicit == IpNetworkKind.unknown;
  return IpSourceVerdict(
    source: IpInsightSource.ipApiCom,
    status: IpSourceProbeStatus.ok,
    latencyMs: latencyMs,
    networkKind: inferred ? IpNetworkKind.residential : explicit,
    inferredType: inferred,
    countryCode: _str(json['countryCode']),
    countryName: _str(json['country']),
    city: _str(json['city']),
    asn: _asn(json['as']),
    organization: _str(json['org']) ?? _str(json['isp']),
    isProxy: _bool(json['proxy']),
    isHosting: isHosting,
    isMobile: isMobile,
  );
}

IpSourceVerdict _parseIpApiIs(
  Map<String, dynamic> json, {
  required int latencyMs,
}) {
  final companyRaw = json['company'];
  final asnRaw = json['asn'];
  final company = _map(companyRaw);
  final asnObj = _map(asnRaw);
  final isHosting = _bool(json['is_datacenter']);
  final isMobile = _bool(json['is_mobile']);
  final declared =
      _declaredKind(_str(company['type'])) ??
      _declaredKind(_str(asnObj['type']));
  final kind = _pickNetworkKind(
    isHosting: isHosting,
    isMobile: isMobile,
    declared: declared,
  );

  // ipapi.is full responses include "abuser_score": "0.1234 (High)".
  final abuserRatio =
      _parseAbuserScore(_str(company['abuser_score'])) ??
      _parseAbuserScore(_str(asnObj['abuser_score']));
  final riskScore = abuserRatio != null
      ? (abuserRatio * 100).round().clamp(0, 100)
      : null;

  final organization = companyRaw is String
      ? _str(companyRaw)
      : _str(company['name']) ?? _str(asnObj['org']);

  return IpSourceVerdict(
    source: IpInsightSource.ipApiIs,
    status: IpSourceProbeStatus.ok,
    latencyMs: latencyMs,
    networkKind: kind,
    riskScore: riskScore,
    countryName: _str(json['country']),
    city: _str(json['city']),
    asn: _asn(asnRaw is Map ? asnObj['asn'] : asnRaw),
    organization: organization,
    isProxy: _bool(json['is_proxy']),
    isVpn: _bool(json['is_vpn']),
    isTor: _bool(json['is_tor']),
    isAbuser: _bool(json['is_abuser']),
    isHosting: isHosting,
    isMobile: isMobile,
    note: _str(company['abuser_score']) ?? (organization != null ? 'Basic' : null),
  );
}

IpSourceVerdict _parseScamalyticsHtml(String html, {required int latencyMs}) {
  final scoreMatch =
      RegExp(r'"score"\s*:\s*"?(\d{1,3})"?').firstMatch(html) ??
      RegExp(r'Fraud Score:\s*(\d{1,3})', caseSensitive: false).firstMatch(html);
  if (scoreMatch == null) {
    return IpSourceVerdict(
      source: IpInsightSource.scamalytics,
      status: IpSourceProbeStatus.failed,
      latencyMs: latencyMs,
    );
  }
  final score = int.tryParse(scoreMatch.group(1) ?? '')?.clamp(0, 100);
  final riskLabel = RegExp(r'"risk"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1);
  final isProxy = RegExp(
    r'Anonymizing VPN.*?yes|Public Proxy.*?yes',
    caseSensitive: false,
    dotAll: true,
  ).hasMatch(html);
  final isTor = RegExp(
    r'Tor Exit Node.*?yes',
    caseSensitive: false,
    dotAll: true,
  ).hasMatch(html);
  final isHosting = RegExp(
    r'Server.*?yes',
    caseSensitive: false,
    dotAll: true,
  ).hasMatch(html);

  return IpSourceVerdict(
    source: IpInsightSource.scamalytics,
    status: IpSourceProbeStatus.ok,
    latencyMs: latencyMs,
    networkKind: isHosting ? IpNetworkKind.hosting : IpNetworkKind.unknown,
    riskScore: score,
    isProxy: isProxy,
    isTor: isTor,
    isHosting: isHosting,
    note: riskLabel != null ? 'Fraud $score ($riskLabel)' : 'Fraud $score',
  );
}

IpNetworkKind _pickNetworkKind({
  bool isHosting = false,
  bool isMobile = false,
  IpNetworkKind? declared,
}) {
  if (isHosting || declared == IpNetworkKind.hosting) {
    return IpNetworkKind.hosting;
  }
  if (isMobile) {
    return IpNetworkKind.mobile;
  }
  return declared ?? IpNetworkKind.unknown;
}

IpNetworkKind? _declaredKind(String? raw) {
  return switch (raw?.toLowerCase()) {
    'isp' || 'residential' => IpNetworkKind.residential,
    'business' || 'government' || 'banking' => IpNetworkKind.business,
    'education' => IpNetworkKind.education,
    'hosting' || 'datacenter' => IpNetworkKind.hosting,
    'mobile' || 'wireless' => IpNetworkKind.mobile,
    _ => null,
  };
}

double? _parseAbuserScore(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final match = RegExp(r'([0-9]*\.?[0-9]+)').firstMatch(raw);
  if (match == null) return null;
  return double.tryParse(match.group(1)!);
}

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

bool _bool(Object? value) => value == true;

String? _str(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

int? _int(Object? value) {
  return switch (value) {
    final int n => n,
    final num n => n.round(),
    final String s => int.tryParse(s.trim()),
    _ => null,
  };
}

int? _asn(Object? value) {
  final parsed = switch (value) {
    final int n => n,
    final String s => int.tryParse(RegExp(r'\d+').firstMatch(s)?.group(0) ?? ''),
    _ => null,
  };
  return parsed == null || parsed == 0 ? null : parsed;
}
