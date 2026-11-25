/// Hardware capability tier for adaptive model selection.
enum DeviceTier {
  /// Entry-level devices (< 3 GB available RAM, budget quad-core SoC).
  low,

  /// Mid-range devices (3 GB - 6 GB RAM, octa-core SoC, modern browser).
  balanced,

  /// High-performance devices (> 6 GB RAM, NPU / Vulkan / WebGPU).
  high,
}

/// Model family defining tokenization and chat template conventions.
enum ModelFamily {
  smollm,
  qwen,
  gemma,
  llama,
}

/// Specification for an on-device local language model.
class ModelSpec {
  final String id;
  final String name;
  final ModelFamily family;
  final DeviceTier tier;
  final int sizeBytes;
  final String sha256Checksum;
  final String downloadUrl;
  final int contextLength;
  final String quantization;
  final int minRamMb;
  final int minDiskMb;
  final String description;

  const ModelSpec({
    required this.id,
    required this.name,
    required this.family,
    required this.tier,
    required this.sizeBytes,
    required this.sha256Checksum,
    required this.downloadUrl,
    required this.contextLength,
    required this.quantization,
    required this.minRamMb,
    required this.minDiskMb,
    required this.description,
  });

  /// Curated production-ready adaptive models
  static const ModelSpec smollm2_135m = ModelSpec(
    id: 'smollm2-135m-q4',
    name: 'SmolLM2 135M Instruct (Q4_K_M)',
    family: ModelFamily.smollm,
    tier: DeviceTier.low,
    sizeBytes: 105454432, // ~105.4 MB
    sha256Checksum: '2e8040ceae7815abe0dcb3540b9995eaa1fa0d2ca9e797d0a635ae4433c68c2d',
    downloadUrl:
        'https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf',
    contextLength: 2048,
    quantization: 'Q4_K_M',
    minRamMb: 1200,
    minDiskMb: 300,
    description: 'Ultra-lightweight reasoning model for entry-level devices and instant startup.',
  );

  static const ModelSpec qwen25_05b = ModelSpec(
    id: 'qwen2.5-0.5b-q4',
    name: 'Qwen 2.5 0.5B Instruct (Q4_K_M)',
    family: ModelFamily.qwen,
    tier: DeviceTier.balanced,
    sizeBytes: 398240768, // ~398 MB
    sha256Checksum: '9e382d62118331fa55b9a89632eb914f69741e4f4d2f8319f390022d4f8287d3',
    downloadUrl:
        'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2_5-0_5b-instruct-q4_k_m.gguf',
    contextLength: 4096,
    quantization: 'Q4_K_M',
    minRamMb: 2500,
    minDiskMb: 800,
    description: 'Optimal balance of nuanced conversational wit, empathy, and speed.',
  );

  static const ModelSpec qwen25_15b = ModelSpec(
    id: 'qwen2.5-1.5b-q4',
    name: 'Qwen 2.5 1.5B Instruct (Q4_K_M)',
    family: ModelFamily.qwen,
    tier: DeviceTier.high,
    sizeBytes: 986000000, // ~986 MB
    sha256Checksum: 'a718b53e89139268f76dfcf89c97b8f9e7f84897ff7b0572e9a686d0b30bb694',
    downloadUrl:
        'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2_5-1_5b-instruct-q4_k_m.gguf',
    contextLength: 4096,
    quantization: 'Q4_K_M',
    minRamMb: 3500,
    minDiskMb: 1500,
    description: 'Superior conversational nuance, emotional empathy, and robust multi-turn context for high-performance phones (Snapdragon 7/8 series, 8GB+ RAM).',
  );

  static const ModelSpec gemma2_2b = ModelSpec(
    id: 'gemma2-2b-q4',
    name: 'Gemma 2 2B IT (Q4_K_M)',
    family: ModelFamily.gemma,
    tier: DeviceTier.high,
    sizeBytes: 1530920960, // ~1.53 GB
    sha256Checksum: 'c1b48b11116a5b6cbe19e044199c0715efd8d73b302c38d3876e5792aa236c5d',
    downloadUrl:
        'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
    contextLength: 4096,
    quantization: 'Q4_K_M',
    minRamMb: 4500,
    minDiskMb: 2500,
    description: 'Flagship reasoning and social fluency for devices with dedicated NPUs or >6GB RAM.',
  );

  static List<ModelSpec> get allModels => [
        smollm2_135m,
        qwen25_05b,
        qwen25_15b,
        gemma2_2b,
      ];

  static ModelSpec forTier(DeviceTier tier) {
    switch (tier) {
      case DeviceTier.low:
        return smollm2_135m;
      case DeviceTier.balanced:
        return qwen25_05b;
      case DeviceTier.high:
        return qwen25_15b;
    }
  }

  /// Formats prompt according to the model family's chat template
  String formatChatPrompt({
    required String systemInstruction,
    required List<Map<String, String>> history,
    required String currentUtterance,
  }) {
    final buffer = StringBuffer();

    switch (family) {
      case ModelFamily.smollm:
      case ModelFamily.qwen:
        // ChatML format (<|im_start|>system...<|im_end|>)
        buffer.writeln('<|im_start|>system\n$systemInstruction<|im_end|>');
        for (final turn in history) {
          final role = turn['role'] ?? 'user';
          final content = turn['content'] ?? '';
          buffer.writeln('<|im_start|>$role\n$content<|im_end|>');
        }
        buffer.writeln('<|im_start|>user\n$currentUtterance<|im_end|>');
        buffer.write('<|im_start|>assistant\n');
        break;

      case ModelFamily.gemma:
        // Gemma format (<start_of_turn>model...<end_of_turn>)
        buffer.writeln('<start_of_turn>user\n[System Instructions]\n$systemInstruction');
        for (final turn in history) {
          final role = turn['role'] == 'assistant' ? 'model' : 'user';
          final content = turn['content'] ?? '';
          buffer.writeln('<start_of_turn>$role\n$content<end_of_turn>');
        }
        buffer.writeln('<start_of_turn>user\n$currentUtterance<end_of_turn>');
        buffer.write('<start_of_turn>model\n');
        break;

      case ModelFamily.llama:
        // Llama 3 format
        buffer.writeln('<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n$systemInstruction<|eot_id|>');
        for (final turn in history) {
          final role = turn['role'] ?? 'user';
          final content = turn['content'] ?? '';
          buffer.writeln('<|start_header_id|>$role<|end_header_id|>\n$content<|eot_id|>');
        }
        buffer.writeln('<|start_header_id|>user<|end_header_id|>\n$currentUtterance<|eot_id|>');
        buffer.write('<|start_header_id|>assistant<|end_header_id|>\n');
        break;
    }

    return buffer.toString();
  }
}
