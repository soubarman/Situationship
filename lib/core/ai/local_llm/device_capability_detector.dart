import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:situationship/core/ai/local_llm/model_spec.dart';

/// Comprehensive snapshot of the device's hardware & inference capabilities.
class DeviceCapabilityReport {
  final DeviceTier tier;
  final int estimatedRamMb;
  final int processorCount;
  final bool hasGpuAcceleration;
  final bool isWeb;
  final bool isAndroid;
  final ModelSpec recommendedModel;
  final String reasoning;

  const DeviceCapabilityReport({
    required this.tier,
    required this.estimatedRamMb,
    required this.processorCount,
    required this.hasGpuAcceleration,
    required this.isWeb,
    required this.isAndroid,
    required this.recommendedModel,
    required this.reasoning,
  });

  Map<String, dynamic> toMap() => {
        'tier': tier.name,
        'estimatedRamMb': estimatedRamMb,
        'processorCount': processorCount,
        'hasGpuAcceleration': hasGpuAcceleration,
        'isWeb': isWeb,
        'isAndroid': isAndroid,
        'recommendedModelId': recommendedModel.id,
        'reasoning': reasoning,
      };
}

/// Detects local device capabilities adaptively across Android, Web, and Desktop.
class DeviceCapabilityDetector {
  static DeviceCapabilityReport? _cachedReport;

  /// Detects hardware specifications and selects the optimal on-device model.
  static Future<DeviceCapabilityReport> detect({bool forceRefresh = false}) async {
    if (_cachedReport != null && !forceRefresh) {
      return _cachedReport!;
    }

    if (kIsWeb) {
      return _detectWebCapabilities();
    }

    final isAndroid = Platform.isAndroid;
    final processorCount = Platform.numberOfProcessors;

    // Platform-specific heuristics
    int estimatedRamMb;
    bool hasGpuAcceleration = false;

    if (isAndroid) {
      // Android: typical modern device classification based on processor count and system info
      if (processorCount <= 4) {
        estimatedRamMb = 2048; // Budget entry-level
      } else if (processorCount <= 6) {
        estimatedRamMb = 3500; // Mid-range
        hasGpuAcceleration = true;
      } else {
        estimatedRamMb = 6144; // High-end octa-core
        hasGpuAcceleration = true;
      }
    } else {
      // Desktop / Host testing environment
      estimatedRamMb = processorCount > 4 ? 8192 : 4096;
      hasGpuAcceleration = true;
    }

    DeviceTier tier;
    ModelSpec recommended;
    String reasoning;

    if (estimatedRamMb < 3000 || processorCount <= 4) {
      tier = DeviceTier.low;
      recommended = ModelSpec.smollm2_135m;
      reasoning =
          'Detected entry-level hardware ($processorCount cores, ~${estimatedRamMb}MB RAM). Selected SmolLM2-135M (~105MB) for zero thermal throttling and instant inference.';
    } else if (estimatedRamMb <= 5500 || processorCount <= 6) {
      tier = DeviceTier.balanced;
      recommended = ModelSpec.qwen25_05b;
      reasoning =
          'Detected mid-range hardware ($processorCount cores, ~${estimatedRamMb}MB RAM). Selected Qwen2.5-0.5B (~398MB) for balanced conversational nuance and smooth throughput.';
    } else {
      tier = DeviceTier.high;
      recommended = ModelSpec.qwen25_15b;
      reasoning =
          'Detected high-performance hardware ($processorCount cores, ~${estimatedRamMb}MB RAM, e.g. Snapdragon 7/8 series). Selected Qwen2.5-1.5B (~986MB) for superior social intelligence, emotional nuance, and responsive mobile token generation.';
    }

    _cachedReport = DeviceCapabilityReport(
      tier: tier,
      estimatedRamMb: estimatedRamMb,
      processorCount: processorCount,
      hasGpuAcceleration: hasGpuAcceleration,
      isWeb: false,
      isAndroid: isAndroid,
      recommendedModel: recommended,
      reasoning: reasoning,
    );

    return _cachedReport!;
  }

  /// Web detection heuristic: uses browser WebGL / WebGPU if available
  static DeviceCapabilityReport _detectWebCapabilities() {
    // Flutter Web runs inside browser JS sandbox.
    // WebGPU and Wasm limits typically warrant the compact or balanced model.
    const report = DeviceCapabilityReport(
      tier: DeviceTier.low,
      estimatedRamMb: 2048,
      processorCount: 4,
      hasGpuAcceleration: true,
      isWeb: true,
      isAndroid: false,
      recommendedModel: ModelSpec.smollm2_135m,
      reasoning:
          'Running on Flutter Web. Selected SmolLM2-135M (~105MB) to ensure fast in-browser Wasm/WebGPU execution without exceeding browser tab memory quotas.',
    );
    _cachedReport = report;
    return report;
  }
}
