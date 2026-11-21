import 'package:flutter/widgets.dart';

import 'models.dart';

/// Self-contained bilingual localization for the IP Insight plugin module,
/// following FlClash's active locale without touching generated ARB tables.
class IpInsightStrings {
  const IpInsightStrings._(this.zh);

  final bool zh;

  factory IpInsightStrings.of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    final isZh = locale?.languageCode.toLowerCase() == 'zh';
    return IpInsightStrings._(isZh);
  }

  String get cardTitle => zh ? 'IP 质量体检' : 'IP Quality Insight';
  String get cardDescription => zh
      ? '多源 IP 纯净度评分、属性识别与 AI/流媒体可用性检测'
      : 'Multi-source IP purity score, type detection & AI/media unlock checks';
  String get sheetTitle => zh ? 'IP 深度体检报告' : 'IP Quality Report';
  String get runCheckup => zh ? '一键体检' : 'Run Checkup';
  String get recheck => zh ? '重新测评' : 'Recheck';
  String get checking => zh ? '多源测评中...' : 'Evaluating...';
  String get waitingOutbound => zh ? '等待获取出口 IP' : 'Waiting for exit IP';
  String get scoreOutOf => '/ 100';
  String get scoreLabel => zh ? '综合评分' : 'Composite Score';
  String get cachedTag => zh ? '缓存' : 'Cached';
  String get liveTag => zh ? '实时' : 'Live';
  String get sourcesSummary => zh ? '测评源' : 'Sources';

  String get sectionOverview => zh ? 'IP 属性画像' : 'IP Profile';
  String get sectionScoreBreakdown => zh ? '评分拆解' : 'Score Breakdown';
  String get sectionToolAvailability => zh ? '工具与服务可用性' : 'Tool Availability';
  String get sectionSources => zh ? '内置测评网站对比' : 'Evaluation Sources';

  String get fieldIpAddress => zh ? '出口 IP' : 'Exit IP';
  String get fieldIpVersion => zh ? '协议栈' : 'IP Stack';
  String get fieldNetworkType => zh ? 'IP 所属类型' : 'IP Type';
  String get fieldBroadcastType => zh ? '原生 / 广播' : 'Origin Type';
  String get fieldLocation => zh ? '地理位置' : 'Location';
  String get fieldAsn => zh ? 'ASN / 运营商' : 'ASN / ISP';
  String get fieldRiskFlags => zh ? '风险污染标记' : 'Risk Signals';
  String get noRiskFlags => zh ? '无明显风险标记' : 'No risk flags';

  String get breakdownBase => zh ? '基准分' : 'Base Score';
  String get breakdownNetwork => zh ? 'IP 属性修正' : 'IP Type Factor';
  String get breakdownRisk => zh ? '多源欺诈风险扣分' : 'Weighted Risk Penalty';
  String get breakdownAnonymity => zh ? '代理 / 滥用污染扣分' : 'Anonymity & Abuse';
  String get breakdownBroadcast => zh ? '广播 IP 修正' : 'Broadcast Factor';
  String get breakdownConsensus => zh ? '多源纯净一致加分' : 'Clean Consensus Bonus';

  String get aiReadiness => zh ? 'AI 可用' : 'AI';
  String get streamingReadiness => zh ? '流媒体' : 'Media';
  String get generalReadiness => zh ? '常用' : 'Tools';

  String categoryLabel(ToolCategory category) {
    return switch (category) {
      ToolCategory.ai => zh ? 'AI 工具可用性' : 'AI Tools',
      ToolCategory.streaming => zh ? '流媒体解锁' : 'Streaming Media',
      ToolCategory.general => zh ? '开发与常用工具' : 'Developer & General',
    };
  }

  String networkKindLabel(IpNetworkKind kind) {
    return switch (kind) {
      IpNetworkKind.residential => zh ? '家庭住宅 IP' : 'Residential',
      IpNetworkKind.mobile => zh ? '移动蜂窝 IP' : 'Mobile',
      IpNetworkKind.business => zh ? '商业宽带 IP' : 'Business',
      IpNetworkKind.education => zh ? '教育机构 IP' : 'Education',
      IpNetworkKind.hosting => zh ? '机房 / IDC' : 'Datacenter',
      IpNetworkKind.unknown => zh ? '未知类型' : 'Unknown',
    };
  }

  String networkKindShort(IpNetworkKind kind) {
    return switch (kind) {
      IpNetworkKind.residential => zh ? '住宅 IP' : 'Residential',
      IpNetworkKind.mobile => zh ? '移动 IP' : 'Mobile',
      IpNetworkKind.business => zh ? '商宽 IP' : 'Business',
      IpNetworkKind.education => zh ? '教育 IP' : 'Edu',
      IpNetworkKind.hosting => zh ? '机房 IP' : 'IDC',
      IpNetworkKind.unknown => zh ? '待判定' : 'Unknown',
    };
  }

  String broadcastLabel(IpBroadcastKind kind) {
    return switch (kind) {
      IpBroadcastKind.nativeIp => zh ? '原生 IP' : 'Native IP',
      IpBroadcastKind.broadcast => zh ? '广播 IP' : 'Broadcast',
      IpBroadcastKind.unknown => zh ? '路由未知' : 'Unknown',
    };
  }

  String gradeLabel(IpPurityGrade grade) {
    return switch (grade) {
      IpPurityGrade.pristine => zh ? '极佳纯净' : 'Pristine',
      IpPurityGrade.clean => zh ? '优质低险' : 'Clean',
      IpPurityGrade.moderate => zh ? '常规可用' : 'Moderate',
      IpPurityGrade.polluted => zh ? '存在污染' : 'Polluted',
      IpPurityGrade.severe => zh ? '高危污染' : 'Severe',
    };
  }

  String gradeHint(IpPurityGrade grade) {
    return switch (grade) {
      IpPurityGrade.pristine =>
        zh
            ? '多源交叉验证极为纯净，适合高敏感 AI 与流媒体环境'
            : 'Verified clean across multiple sources; ideal for AI & streaming',
      IpPurityGrade.clean =>
        zh
            ? '风险极低，AI 工具与主流流媒体访问稳定'
            : 'Low risk; reliable for AI tools and media platforms',
      IpPurityGrade.moderate =>
        zh
            ? '多为标准机房或广播段，部分风控站点可能触发人机验证'
            : 'Typical datacenter/broadcast range; strict sites may challenge',
      IpPurityGrade.polluted =>
        zh
            ? '检测到代理/欺诈风险特征，易遇验证码、限流或 AI 拦截'
            : 'Elevated fraud/proxy flags; CAPTCHAs or AI blocks likely',
      IpPurityGrade.severe =>
        zh
            ? '存在严重滥用或高危污染标记，强烈建议切换其他出口节点'
            : 'Severe abuse or blocklist signals; switch exit node',
    };
  }

  String sourceStatusLabel(IpSourceProbeStatus status) {
    return switch (status) {
      IpSourceProbeStatus.ok => zh ? '正常' : 'OK',
      IpSourceProbeStatus.rateLimited => zh ? '限流' : 'Limited',
      IpSourceProbeStatus.timeout => zh ? '超时' : 'Timeout',
      IpSourceProbeStatus.failed => zh ? '失败' : 'Failed',
    };
  }

  List<String> flagLabels(IpRiskFlags flags) {
    return [
      if (flags.isTor) 'Tor',
      if (flags.isAbuser) zh ? '历史滥用' : 'Abuser',
      if (flags.isCompromised) zh ? '曾被入侵' : 'Compromised',
      if (flags.isScraper) zh ? '爬虫标记' : 'Scraper',
      if (flags.isVpn) 'VPN',
      if (flags.isProxy) zh ? '公开代理' : 'Proxy',
    ];
  }
}
