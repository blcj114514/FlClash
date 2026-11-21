import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/features/ip_insight/ip_insight.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/providers/service_status.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';

/// Native FlClash Dashboard widget presenting multi-source IP quality score,
/// IP attributes (Residential/Business/IDC, Native/Broadcast), and grouped
/// AI/Streaming/General tool unlock summaries.
class IpInsightCard extends ConsumerStatefulWidget {
  const IpInsightCard({super.key});

  @override
  ConsumerState<IpInsightCard> createState() => _IpInsightCardState();
}

class _IpInsightCardState extends ConsumerState<IpInsightCard> {
  late final OutboundIpProbe _outboundProbe;
  late final ServiceStatus _serviceStatus;

  @override
  void initState() {
    super.initState();
    _outboundProbe = ref.read(outboundIpProbeProvider.notifier)
      ..watch(routedOutbound);
    _serviceStatus = ref.read(serviceStatusProvider.notifier);
    for (final target in ToolCategory.ai.targets) {
      _serviceStatus.watch(target);
    }
  }

  @override
  void dispose() {
    _outboundProbe.unwatch(routedOutbound);
    for (final target in ToolCategory.ai.targets) {
      _serviceStatus.unwatch(target);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final density = DashboardDensityScope.of(context);
    final mobile = !density.isDesktop;
    final compact = density.isCompact;
    final strings = IpInsightStrings.of(context);
    final insight = ref.watch(ipInsightProvider);
    final serviceState = ref.watch(serviceStatusProvider);
    final report = insight.report;

    final anyAiLoading = ToolCategory.ai.targets.any(serviceState.isLoading);
    final loading = insight.isEvaluating || anyAiLoading;

    final chip = report != null
        ? DashboardChip(
            label: strings.gradeLabel(report.grade),
            tone: purityChipToneOf(report.grade),
            dot: true,
          )
        : insight.isEvaluating
        ? DashboardChip(label: strings.checking)
        : null;

    Future<void> openSheet() => showIpInsightSheet(context);

    final body = _IpInsightSummary(
      insight: insight,
      serviceState: serviceState,
      compact: compact,
      mobile: mobile,
    );

    return DashboardCard(
      semanticLabel: strings.cardTitle,
      onTap: mobile ? openSheet : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.verified,
            title: strings.cardTitle,
            chevron: mobile,
            trailing: [
              if (chip != null) chip,
              if (!mobile)
                Transform.translate(
                  offset: const Offset(8, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (loading)
                        const SizedBox.square(
                          dimension: 32,
                          child: Center(child: ActivityIndicator(size: 16)),
                        )
                      else
                        DashboardIconButton(
                          glyph: AppGlyphs.bolt,
                          tooltip: strings.runCheckup,
                          onPressed: () => ref
                              .read(ipInsightProvider.notifier)
                              .runFullCheckup(),
                        ),
                      DashboardIconButton(
                        glyph: AppGlyphs.chevronForward,
                        tooltip: strings.sheetTitle,
                        onPressed: openSheet,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: mobile ? 12 : (compact ? 8 : 10)),
          if (mobile) body else Expanded(child: body),
        ],
      ),
    );
  }
}

class _IpInsightSummary extends StatelessWidget {
  const _IpInsightSummary({
    required this.insight,
    required this.serviceState,
    required this.compact,
    required this.mobile,
  });

  final IpInsightState insight;
  final RoutedProbeState<ServiceTarget, ServiceCheck> serviceState;
  final bool compact;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final strings = IpInsightStrings.of(context);
    final scheme = context.colorScheme;
    final report = insight.report;
    final gaugeSize = mobile ? 66.0 : (compact ? 54.0 : 62.0);

    final aiStats = _categoryStats(serviceState, ToolCategory.ai);
    final mediaStats = _categoryStats(serviceState, ToolCategory.streaming);
    final generalStats = _categoryStats(serviceState, ToolCategory.general);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: compact ? 10 : 12,
          children: [
            PurityScoreGauge(
              score: report?.score,
              grade: report?.grade,
              size: gaugeSize,
              strokeWidth: compact ? 5 : 6,
              loading: insight.isEvaluating,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 5,
                children: [
                  if (report != null)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _MiniAttributePill(
                          label: strings.networkKindShort(report.networkKind),
                          accent: report.networkKind == IpNetworkKind.residential
                              ? scheme.success
                              : report.networkKind == IpNetworkKind.hosting
                              ? scheme.warning
                              : null,
                        ),
                        if (report.broadcastKind != IpBroadcastKind.unknown)
                          _MiniAttributePill(
                            label: strings.broadcastLabel(report.broadcastKind),
                            accent:
                                report.broadcastKind == IpBroadcastKind.nativeIp
                                ? scheme.success
                                : scheme.warning,
                          ),
                      ],
                    )
                  else
                    SkeletonText(
                      width: 112,
                      style: AppTextStyle.caption1.of(context),
                    ),
                  Text(
                    _subtitleOf(strings, report),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardText.label(context),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (mobile) const SizedBox(height: 12) else const Spacer(),
        Row(
          spacing: compact ? 6 : 8,
          children: [
            Expanded(
              child: _ToolCategoryPill(
                label: strings.aiReadiness,
                available: aiStats.available,
                total: aiStats.total,
                checked: aiStats.checked,
              ),
            ),
            Expanded(
              child: _ToolCategoryPill(
                label: strings.streamingReadiness,
                available: mediaStats.available,
                total: mediaStats.total,
                checked: mediaStats.checked,
              ),
            ),
            Expanded(
              child: _ToolCategoryPill(
                label: strings.generalReadiness,
                available: generalStats.available,
                total: generalStats.total,
                checked: generalStats.checked,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _subtitleOf(IpInsightStrings strings, IpInsightReport? report) {
    if (report == null) {
      return insight.isEvaluating ? strings.checking : strings.waitingOutbound;
    }
    final parts = <String>[
      if (report.countryCode != null)
        '${report.countryCode!.countryFlagEmoji} ${report.countryCode}',
      if (report.asn != null) 'AS${report.asn}',
      '${report.succeededSourceCount}/${report.verdicts.length} ${strings.sourcesSummary}',
    ];
    return parts.join(' · ');
  }

  ({int available, int checked, int total}) _categoryStats(
    RoutedProbeState<ServiceTarget, ServiceCheck> state,
    ToolCategory category,
  ) {
    var available = 0;
    var checked = 0;
    for (final target in category.targets) {
      final check = state.entryOf(target).value;
      if (check != null) {
        checked++;
        if (check.status == ServiceProbeStatus.available) {
          available++;
        }
      }
    }
    return (
      available: available,
      checked: checked,
      total: category.targets.length,
    );
  }
}

class _MiniAttributePill extends StatelessWidget {
  const _MiniAttributePill({required this.label, this.accent});

  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    final scheme = context.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.tone,
        shape: AppShape.full,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          maxLines: 1,
          style: AppTextStyle.caption1
              .of(context, emphasized: true)
              .copyWith(color: accent ?? scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _ToolCategoryPill extends StatelessWidget {
  const _ToolCategoryPill({
    required this.label,
    required this.available,
    required this.total,
    required this.checked,
  });

  final String label;
  final int available;
  final int total;
  final int checked;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final dotColor = checked == 0
        ? scheme.onSurfaceVariant
        : available == total
        ? scheme.success
        : available > 0
        ? scheme.warning
        : scheme.error;

    return DashboardBlock(
      radius: DashboardCorner.tab,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 5,
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              color: dotColor,
              shape: AppShape.circle,
            ),
            child: const SizedBox.square(dimension: 6),
          ),
          Flexible(
            child: Text(
              checked == 0 ? '$label —' : '$label $available/$total',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context, emphasized: true)
                  .toTabular
                  .copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
