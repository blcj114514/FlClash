import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/service_status.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'evaluator.dart';
import 'models.dart';

@immutable
class IpInsightState {
  const IpInsightState({
    this.ip,
    this.report,
    this.isEvaluating = false,
    this.error,
  });

  final String? ip;
  final IpInsightReport? report;
  final bool isEvaluating;
  final String? error;

  IpInsightState copyWith({
    String? ip,
    IpInsightReport? report,
    bool clearReport = false,
    bool? isEvaluating,
    String? error,
    bool clearError = false,
  }) {
    return IpInsightState(
      ip: ip ?? this.ip,
      report: clearReport ? null : (report ?? this.report),
      isEvaluating: isEvaluating ?? this.isEvaluating,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final ipInsightEvaluatorProvider = Provider<IpInsightEvaluator>((ref) {
  return IpInsightEvaluator();
});

final ipInsightProvider = NotifierProvider<IpInsightController, IpInsightState>(
  IpInsightController.new,
);

class IpInsightController extends Notifier<IpInsightState> {
  CancelToken? _cancelToken;
  int _generation = 0;

  @override
  IpInsightState build() {
    ref.onDispose(() {
      _cancelToken?.cancel();
      _cancelToken = null;
    });

    final exitIp = ref.watch(
      outboundIpProbeProvider.select(
        (probe) => probe.entryOf(routedOutbound).value?.ip,
      ),
    );

    if (exitIp == null || exitIp.isEmpty) {
      return const IpInsightState();
    }

    final evaluator = ref.read(ipInsightEvaluatorProvider);
    final cached = evaluator.cached(exitIp);
    if (cached != null) {
      return IpInsightState(ip: exitIp, report: cached);
    }

    scheduleMicrotask(() => evaluate(exitIp));
    return IpInsightState(ip: exitIp, isEvaluating: true);
  }

  /// Evaluates [ip] across all built-in zero-key sources.
  Future<void> evaluate(String ip, {bool forceRefresh = false}) async {
    if (ip.isEmpty) return;
    _cancelToken?.cancel();
    final token = CancelToken();
    _cancelToken = token;
    final generation = ++_generation;

    state = state.copyWith(
      ip: ip,
      isEvaluating: true,
      clearError: true,
      clearReport: state.ip != ip,
    );

    try {
      final evaluator = ref.read(ipInsightEvaluatorProvider);
      final report = await evaluator.evaluate(
        request.dio,
        ip,
        forceRefresh: forceRefresh,
        cancelToken: token,
      );
      if (generation != _generation) return;
      state = IpInsightState(ip: ip, report: report);
    } catch (error) {
      if (generation != _generation) return;
      if (error is DioException && error.type == DioExceptionType.cancel) {
        return;
      }
      state = state.copyWith(
        isEvaluating: false,
        error: compactError(error),
      );
    }
  }

  /// Triggers a complete checkup: refreshes outbound IP if needed, forces a
  /// fresh multi-source IP score check, and refreshes AI + Media + Tool probes.
  Future<void> runFullCheckup() async {
    final outboundNotifier = ref.read(outboundIpProbeProvider.notifier);
    final currentIp = ref
        .read(outboundIpProbeProvider)
        .entryOf(routedOutbound)
        .value
        ?.ip;

    ref
        .read(serviceStatusProvider.notifier)
        .refresh(ToolCategory.allTargets);

    if (currentIp == null || currentIp.isEmpty) {
      outboundNotifier.refresh(const [routedOutbound]);
      return;
    }
    await evaluate(currentIp, forceRefresh: true);
  }
}
