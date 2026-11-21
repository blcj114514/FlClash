import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/providers/service_status.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/views/dashboard/widgets/card.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'l10n.dart';
import 'models.dart';
import 'provider.dart';
import 'score_gauge.dart';

Future<void> showIpInsightSheet(BuildContext context) {
  return showNestedSheet<void>(
    context,
    builder: (_) => const IpInsightSheet(),
  );
}

class IpInsightSheet extends ConsumerWidget {
  const IpInsightSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = IpInsightStrings.of(context);
    final insight = ref.watch(ipInsightProvider);
    final serviceState = ref.watch(serviceStatusProvider);
    final anyToolLoading = ToolCategory.allTargets.any(serviceState.isLoading);
    final isLoading = insight.isEvaluating || anyToolLoading;

    return Scaffold(
      title: strings.sheetTitle,
      actions: [
        AppBarActionButton(
          data: IconButtonData(
            glyph: AppGlyphs.refresh,
            tooltip: strings.recheck,
            isLoading: isLoading,
            onPressed: () =>
                ref.read(ipInsightProvider.notifier).runFullCheckup(),
          ),
        ),
      ],
      body: _IpInsightSheetBody(
        insight: insight,
        serviceState: serviceState,
      ),
    );
  }
}

class _IpInsightSheetBody extends ConsumerWidget {
  const _IpInsightSheetBody({
    required this.insight,
    required this.serviceState,
  });

  final IpInsightState insight;
  final RoutedProbeState<ServiceTarget, ServiceCheck> serviceState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = IpInsightStrings.of(context);
    final hideIp = ref.watch(
      appSettingProvider.select((state) => state.hideIp),
    );
    final report = insight.report;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
        top: context.contentTopPadding,
        bottom: 24 + context.bottomInset,
      ),
      children: [
        _HeroScoreCard(
          insight: insight,
          hideIp: hideIp,
        ),
        if (report != null) ...[
          generateSection(
            title: strings.sectionOverview,
            items: _buildProfileRows(context, strings, report, hideIp),
          ),
          generateSection(
            title: strings.sectionScoreBreakdown,
            items: _buildBreakdownRows(context, strings, report.breakdown),
          ),
        ],
        for (final category in ToolCategory.values)
          generateSection(
            title: strings.categoryLabel(category),
            items: [
              for (final target in category.targets)
                _ToolRow(
                  target: target,
                  entry: serviceState.entryOf(target),
                  onRecheck: () => ref
                      .read(serviceStatusProvider.notifier)
                      .refresh([target]),
                ),
            ],
          ),
        if (report != null)
          generateSection(
            title:
                '${strings.sectionSources} (${report.succeededSourceCount}/${report.verdicts.length})',
            items: [
              for (final verdict in report.verdicts)
                _SourceVerdictRow(verdict: verdict),
            ],
          ),
      ],
    );
  }

  List<Widget> _buildProfileRows(
    BuildContext context,
    IpInsightStrings strings,
    IpInsightReport report,
    bool hideIp,
  ) {
    final scheme = context.colorScheme;
    final displayIp = hideIp ? '*****' : report.ip;
    final locationParts = [
      if (report.countryCode != null) report.countryCode!.countryFlagEmoji,
      if (report.countryName != null) report.countryName!,
      if (report.city != null) report.city!,
    ];
    final asnLabel = [
      if (report.asn != null) 'AS${report.asn}',
      if (report.organization != null) report.organization!,
    ].join(' · ');
    final flags = strings.flagLabels(report.flags);

    return [
      DetailRow(
        title: strings.fieldIpAddress,
        copyText: hideIp ? null : report.ip,
        value: Text(displayIp),
      ),
      DetailRow(
        title: strings.fieldIpVersion,
        value: Text(report.isIpv6 ? 'IPv6' : 'IPv4'),
      ),
      DetailRow(
        title: strings.fieldNetworkType,
        value: Text(
          strings.networkKindLabel(report.networkKind),
          style: TextStyle(
            color: report.networkKind == IpNetworkKind.residential
                ? scheme.success
                : report.networkKind == IpNetworkKind.hosting
                ? scheme.warning
                : scheme.onSurface,
          ),
        ),
      ),
      DetailRow(
        title: strings.fieldBroadcastType,
        value: Text(
          report.asnCountryCode != null &&
                  report.countryCode != null &&
                  report.asnCountryCode != report.countryCode
              ? '${strings.broadcastLabel(report.broadcastKind)} (${report.asnCountryCode} -> ${report.countryCode})'
              : strings.broadcastLabel(report.broadcastKind),
          style: TextStyle(
            color: report.broadcastKind == IpBroadcastKind.nativeIp
                ? scheme.success
                : report.broadcastKind == IpBroadcastKind.broadcast
                ? scheme.warning
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      if (locationParts.isNotEmpty)
        DetailRow(
          title: strings.fieldLocation,
          value: Text(locationParts.join(' ')),
        ),
      if (asnLabel.isNotEmpty)
        DetailRow(
          title: strings.fieldAsn,
          copyText: asnLabel,
          value: Text(asnLabel),
        ),
      DetailRow(
        title: strings.fieldRiskFlags,
        value: Text(
          flags.isEmpty ? strings.noRiskFlags : flags.join(' · '),
          style: TextStyle(
            color: flags.isEmpty ? scheme.success : scheme.error,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildBreakdownRows(
    BuildContext context,
    IpInsightStrings strings,
    IpScoreBreakdown breakdown,
  ) {
    final scheme = context.colorScheme;
    String fmtDelta(int delta) => delta > 0 ? '+$delta' : '$delta';
    Color deltaColor(int delta) {
      if (delta > 0) return scheme.success;
      if (delta <= -15) return scheme.error;
      if (delta < 0) return scheme.warning;
      return scheme.onSurfaceVariant;
    }

    return [
      DetailRow(
        title: strings.breakdownBase,
        value: Text('${breakdown.baseScore}'),
      ),
      DetailRow(
        title: strings.breakdownNetwork,
        value: Text(
          fmtDelta(breakdown.networkAdjustment),
          style: TextStyle(color: deltaColor(breakdown.networkAdjustment)),
        ),
      ),
      DetailRow(
        title:
            '${strings.breakdownRisk} (${breakdown.weightedRiskScore.toStringAsFixed(0)}/100)',
        value: Text(
          fmtDelta(breakdown.riskPenalty),
          style: TextStyle(color: deltaColor(breakdown.riskPenalty)),
        ),
      ),
      DetailRow(
        title: strings.breakdownAnonymity,
        value: Text(
          fmtDelta(breakdown.anonymityPenalty),
          style: TextStyle(color: deltaColor(breakdown.anonymityPenalty)),
        ),
      ),
      DetailRow(
        title: strings.breakdownBroadcast,
        value: Text(
          fmtDelta(breakdown.broadcastPenalty),
          style: TextStyle(color: deltaColor(breakdown.broadcastPenalty)),
        ),
      ),
      DetailRow(
        title: strings.breakdownConsensus,
        value: Text(
          fmtDelta(breakdown.consensusBonus),
          style: TextStyle(color: deltaColor(breakdown.consensusBonus)),
        ),
      ),
    ];
  }
}

class _HeroScoreCard extends StatelessWidget {
  const _HeroScoreCard({
    required this.insight,
    required this.hideIp,
  });

  final IpInsightState insight;
  final bool hideIp;

  @override
  Widget build(BuildContext context) {
    final strings = IpInsightStrings.of(context);
    final colors = DashboardColors.of(context);
    final scheme = context.colorScheme;
    final report = insight.report;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(18),
      decoration: ShapeDecoration(
        color: colors.card,
        shape: AppShape.all(DashboardCorner.mobileBlock),
        shadows: DashboardShadows.e1(context),
      ),
      child: Row(
        spacing: 16,
        children: [
          PurityScoreGauge(
            score: report?.score,
            grade: report?.grade,
            size: 82,
            strokeWidth: 7,
            loading: insight.isEvaluating,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (report != null)
                      DashboardChip(
                        label: strings.gradeLabel(report.grade),
                        tone: purityChipToneOf(report.grade),
                        dot: true,
                      )
                    else
                      DashboardChip(
                        label: insight.isEvaluating
                            ? strings.checking
                            : strings.waitingOutbound,
                      ),
                    if (report != null)
                      DashboardChip(
                        label: strings.networkKindShort(report.networkKind),
                      ),
                    if (report != null &&
                        report.broadcastKind != IpBroadcastKind.unknown)
                      DashboardChip(
                        label: strings.broadcastLabel(report.broadcastKind),
                        tone: report.broadcastKind == IpBroadcastKind.nativeIp
                            ? DashboardChipTone.ok
                            : DashboardChipTone.idle,
                      ),
                  ],
                ),
                Text(
                  insight.ip == null
                      ? strings.waitingOutbound
                      : hideIp
                      ? '*****'
                      : insight.ip!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.headline
                      .of(context, emphasized: true)
                      .toTabular,
                ),
                Text(
                  report != null
                      ? strings.gradeHint(report.grade)
                      : insight.error ?? strings.cardDescription,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.target,
    required this.entry,
    required this.onRecheck,
  });

  final ServiceTarget target;
  final ProbeEntry<ServiceCheck> entry;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final check = entry.value;
    final statusColor = switch (check?.status) {
      ServiceProbeStatus.available => scheme.success,
      ServiceProbeStatus.originalsOnly ||
      ServiceProbeStatus.restricted ||
      ServiceProbeStatus.unsupportedRegion ||
      ServiceProbeStatus.disallowedIsp ||
      ServiceProbeStatus.blocked ||
      ServiceProbeStatus.comingSoon => scheme.warning,
      ServiceProbeStatus.unavailable ||
      ServiceProbeStatus.timeout ||
      ServiceProbeStatus.failed => scheme.error,
      null => scheme.onSurfaceVariant,
    };

    final statusText = _toolStatusLabel(context, check, entry.phase);
    final region = check?.region;
    final delay = check?.delay;

    return ListItem(
      onTap: onRecheck,
      leading: SizedBox.square(
        dimension: 24,
        child: Center(
          child: SvgPicture.asset(
            'assets/images/services/${target.icon}.svg',
            width: 18,
            height: 18,
            excludeFromSemantics: true,
            theme: SvgTheme(currentColor: scheme.onSurfaceVariant),
          ),
        ),
      ),
      title: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Text(
              target.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (region != null && region.isNotEmpty)
            Text(
              '${region.countryFlagEmoji} $region',
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          if (entry.isLoading)
            const ActivityIndicator(size: 14)
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: statusColor,
                    shape: AppShape.circle,
                  ),
                  child: const SizedBox.square(dimension: 7),
                ),
                Text(
                  delay != null &&
                          check?.status == ServiceProbeStatus.available
                      ? '$statusText · ${delay}ms'
                      : statusText,
                  style: AppTextStyle.footnote
                      .of(context, emphasized: true)
                      .toTabular
                      .copyWith(color: statusColor),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _toolStatusLabel(
    BuildContext context,
    ServiceCheck? check,
    ProbePhase phase,
  ) {
    final l10n = context.appLocalizations;
    if (phase == ProbePhase.probing && check == null) {
      return l10n.loading;
    }
    if (check == null) {
      return phase == ProbePhase.failed
          ? l10n.serviceFailed
          : l10n.servicePending;
    }
    return switch (check.status) {
      ServiceProbeStatus.available => l10n.serviceAvailable,
      ServiceProbeStatus.unavailable => l10n.serviceUnavailable,
      ServiceProbeStatus.restricted => l10n.serviceRestricted,
      ServiceProbeStatus.disallowedIsp => l10n.serviceDisallowedIsp,
      ServiceProbeStatus.blocked => l10n.serviceBlocked,
      ServiceProbeStatus.unsupportedRegion => l10n.serviceUnsupportedRegion,
      ServiceProbeStatus.originalsOnly => l10n.serviceOriginalsOnly,
      ServiceProbeStatus.comingSoon => l10n.serviceComingSoon,
      ServiceProbeStatus.timeout => l10n.timeout,
      ServiceProbeStatus.failed => l10n.serviceFailed,
    };
  }
}

class _SourceVerdictRow extends StatelessWidget {
  const _SourceVerdictRow({required this.verdict});

  final IpSourceVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final strings = IpInsightStrings.of(context);
    final scheme = context.colorScheme;

    final statusColor = switch (verdict.status) {
      IpSourceProbeStatus.ok =>
        (verdict.riskScore ?? 0) >= 60
            ? scheme.error
            : (verdict.riskScore ?? 0) >= 30
            ? scheme.warning
            : scheme.success,
      IpSourceProbeStatus.rateLimited ||
      IpSourceProbeStatus.timeout => scheme.warning,
      IpSourceProbeStatus.failed => scheme.error,
    };

    final summaryParts = <String>[
      if (verdict.succeeded) ...[
        if (verdict.networkKind != IpNetworkKind.unknown)
          strings.networkKindShort(verdict.networkKind),
        if (verdict.riskScore != null) 'Risk ${verdict.riskScore}',
        if (verdict.isBroadcast == true)
          strings.broadcastLabel(IpBroadcastKind.broadcast)
        else if (verdict.isBroadcast == false)
          strings.broadcastLabel(IpBroadcastKind.nativeIp),
        if (verdict.isAbuser) 'Abuser',
        if (verdict.isTor) 'Tor',
        if (verdict.isVpn) 'VPN',
        if (verdict.isProxy) 'Proxy',
      ] else
        strings.sourceStatusLabel(verdict.status),
    ];

    return ListItem(
      title: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verdict.source.label,
                  style: AppTextStyle.subheadline.of(context, emphasized: true),
                ),
                Text(
                  verdict.source.domain,
                  style: DashboardText.label(context),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                summaryParts.isEmpty
                    ? strings.sourceStatusLabel(verdict.status)
                    : summaryParts.join(' · '),
                style: AppTextStyle.footnote
                    .of(context, emphasized: true)
                    .toTabular
                    .copyWith(color: statusColor),
              ),
              if (verdict.latencyMs != null)
                Text(
                  '${verdict.latencyMs} ms',
                  style: DashboardText.label(context),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
