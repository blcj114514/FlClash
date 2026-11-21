import 'package:fl_clash/features/ip_insight/ip_insight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evaluateIpInsight', () {
    test('scores clean native residential IP as pristine (85-100)', () {
      final report = evaluateIpInsight(
        ip: '73.162.40.12',
        verdicts: const [
          IpSourceVerdict(
            source: IpInsightSource.ipPure,
            status: IpSourceProbeStatus.ok,
            networkKind: IpNetworkKind.residential,
            isBroadcast: false,
            riskScore: 4,
            countryCode: 'US',
            countryName: 'United States',
            city: 'San Jose',
            asn: 7922,
            organization: 'Comcast Cable Communications',
          ),
          IpSourceVerdict(
            source: IpInsightSource.proxyCheck,
            status: IpSourceProbeStatus.ok,
            networkKind: IpNetworkKind.residential,
            riskScore: 0,
            countryCode: 'US',
          ),
          IpSourceVerdict(
            source: IpInsightSource.ipLocate,
            status: IpSourceProbeStatus.ok,
            networkKind: IpNetworkKind.residential,
            isBroadcast: false,
            countryCode: 'US',
            asnCountryCode: 'US',
          ),
          IpSourceVerdict(
            source: IpInsightSource.scamalytics,
            status: IpSourceProbeStatus.ok,
            riskScore: 2,
          ),
        ],
      );

      expect(report.networkKind, IpNetworkKind.residential);
      expect(report.broadcastKind, IpBroadcastKind.nativeIp);
      expect(report.grade, IpPurityGrade.pristine);
      expect(report.score, greaterThanOrEqualTo(95));
      expect(report.flags.hasAny, isFalse);
      expect(report.isIpv6, isFalse);
    });

    test('detects broadcast datacenter IP as moderate', () {
      final report = evaluateIpInsight(
        ip: '31.56.228.147',
        verdicts: const [
          IpSourceVerdict(
            source: IpInsightSource.ipPure,
            status: IpSourceProbeStatus.ok,
            networkKind: IpNetworkKind.hosting,
            isBroadcast: true,
            isHosting: true,
            riskScore: 40,
            countryCode: 'FR',
          ),
          IpSourceVerdict(
            source: IpInsightSource.proxyCheck,
            status: IpSourceProbeStatus.ok,
            networkKind: IpNetworkKind.hosting,
            isHosting: true,
            riskScore: 33,
            countryCode: 'FR',
          ),
          IpSourceVerdict(
            source: IpInsightSource.ipLocate,
            status: IpSourceProbeStatus.ok,
            networkKind: IpNetworkKind.hosting,
            isBroadcast: true,
            isHosting: true,
            countryCode: 'FR',
            asnCountryCode: 'HK',
          ),
        ],
      );

      expect(report.networkKind, IpNetworkKind.hosting);
      expect(report.broadcastKind, IpBroadcastKind.broadcast);
      expect(report.grade, IpPurityGrade.moderate);
      expect(report.score, inInclusiveRange(50, 69));
    });

    test('penalizes abusive Tor/proxy node into severe tier', () {
      final report = evaluateIpInsight(
        ip: '185.220.101.4',
        verdicts: const [
          IpSourceVerdict(
            source: IpInsightSource.ipPure,
            status: IpSourceProbeStatus.ok,
            networkKind: IpNetworkKind.hosting,
            isHosting: true,
            isBroadcast: true,
            riskScore: 92,
            countryCode: 'DE',
          ),
          IpSourceVerdict(
            source: IpInsightSource.proxyCheck,
            status: IpSourceProbeStatus.ok,
            networkKind: IpNetworkKind.hosting,
            isHosting: true,
            isTor: true,
            isProxy: true,
            riskScore: 95,
          ),
          IpSourceVerdict(
            source: IpInsightSource.ipLocate,
            status: IpSourceProbeStatus.ok,
            networkKind: IpNetworkKind.hosting,
            isHosting: true,
            isAbuser: true,
            isTor: true,
          ),
        ],
      );

      expect(report.grade, IpPurityGrade.severe);
      expect(report.score, lessThan(30));
      expect(report.flags.isTor, isTrue);
      expect(report.flags.isAbuser, isTrue);
    });

    test('gracefully degrades when some sources fail or time out', () {
      final report = evaluateIpInsight(
        ip: '2606:4700:4700::1111',
        verdicts: const [
          IpSourceVerdict(
            source: IpInsightSource.ipPure,
            status: IpSourceProbeStatus.timeout,
          ),
          IpSourceVerdict(
            source: IpInsightSource.proxyCheck,
            status: IpSourceProbeStatus.rateLimited,
          ),
          IpSourceVerdict(
            source: IpInsightSource.ipLocate,
            status: IpSourceProbeStatus.ok,
            networkKind: IpNetworkKind.business,
            countryCode: 'US',
            asnCountryCode: 'US',
            asn: 13335,
            organization: 'Cloudflare, Inc.',
          ),
        ],
      );

      expect(report.isIpv6, isTrue);
      expect(report.succeededSourceCount, 1);
      expect(report.networkKind, IpNetworkKind.business);
      expect(report.broadcastKind, IpBroadcastKind.nativeIp);
      expect(report.score, greaterThan(70));
    });
  });
}
