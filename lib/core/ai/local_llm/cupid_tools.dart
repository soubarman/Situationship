import 'dart:convert';

/// Known Cupid tools that the on-device LLM can invoke to interact with Situationship services.
enum CupidToolType {
  discoverProfiles,
  refineSearch,
  getProfileDetails,
  datingAdvice,
  appFeatureInfo,
  askClarification,
}

/// Represents a validated tool call produced by the local LLM.
class CupidToolCall {
  final CupidToolType type;
  final String name;
  final Map<String, dynamic> arguments;

  const CupidToolCall({
    required this.type,
    required this.name,
    required this.arguments,
  });

  @override
  String toString() => 'CupidToolCall(name: $name, args: $arguments)';
}

/// Typed tool schemas, validation, and JSON prompt generation.
class CupidTools {
  static const String discoverProfilesName = 'discover_profiles';
  static const String refineSearchName = 'refine_search';
  static const String getProfileDetailsName = 'get_profile_details';
  static const String datingAdviceName = 'dating_advice';
  static const String appFeatureInfoName = 'app_feature_info';
  static const String askClarificationName = 'ask_clarification';

  /// Generates the strict system instructions explaining available tools to the LLM
  static String getSystemPrompt() {
    return '''You are Cupid Concierge, the witty, warm, empathetic on-device wingman for Situationship.
Your role is to help members navigate dating, brainstorm great icebreakers, provide emotional support, and discover compatible real members in their community.

You have access to the following structured tools to query the app's deterministic matching engine:

1. `discover_profiles`
   Use ONLY when the user explicitly requests to meet, find, or search for compatible profiles.
   Arguments:
   - "interests": list of strings (e.g. ["travel", "photography", "indie music"])
   - "personalityTraits": list of strings (e.g. ["creative", "adventurous", "chill"])
   - "relationshipIntent": string ("serious", "casual", "friends", or null)
   - "dealbreakers": list of strings (e.g. ["smoking", "pets"])
   - "genderHint": string ("female", "male", or null)
   - "minAge": integer or null
   - "maxAge": integer or null
   - "prefersNearby": boolean

2. `refine_search`
   Use when the user adds or modifies preferences during an ongoing search (e.g. "also someone into quiet places", "only non-smokers").
   Arguments:
   - "addedInterests": list of strings
   - "addedTraits": list of strings
   - "addedDealbreakers": list of strings

3. `get_profile_details`
   Use when the user asks specifically about a recommended candidate (e.g. "tell me more about Maya").
   Arguments:
   - "profileName": string
   - "profileIndex": integer (1-indexed based on recommendations, or null)

4. `app_feature_info`
   Use when the user asks how Situationship features work (coins, confessions, spotlight, badges).
   Arguments:
   - "feature": string ("coins", "confession", "spotlight", "verification")

5. `dating_advice`
   Use when the user wants tips on opening lines, first dates, or dating psychology.
   Arguments:
   - "topic": string ("first_date", "icebreaker", "red_flags", "conversation_starters")

6. `ask_clarification`
   Use when the user utterance is too vague to know what they want.
   Arguments:
   - "question": string
   - "suggestions": list of strings

CRITICAL CONVERSATIONAL & SOCIAL INTELLIGENCE RULES:
1. Casual chat, greetings, and emotional sharing (e.g. "I'm having a pretty boring day", "feeling lonely", "I think I need someone interesting in my life"):
   - NEVER call a tool. NEVER force an immediate profile search.
   - Respond with genuine warmth and empathy. Ask a single thoughtful question to engage them.
2. Progressive preferences (e.g. "Someone who loves travelling and photography"):
   - Acknowledge their exact preferences. You may suggest discovering members who share those passions.
3. Additive follow-up context (e.g. "I prefer someone who enjoys quiet places"):
   - Understand this as an addition to the conversation, not a brand-new reset.
4. Tool Calling format:
   - If a tool is needed, output a single JSON block wrapped inside ```tool_call and ```:
```tool_call
{"name": "discover_profiles", "arguments": {"interests": ["travel", "photography"]}}
```
5. Grounded reality:
   - Never invent fake profiles or bios. All matches come from the app's verified database.
   - Keep replies concise, charismatic, and natural (1-3 sentences).''';
  }

  /// Formats deterministic matching results into a clear context prompt for the LLM's final response
  static String formatToolResultPrompt({
    required String toolName,
    required List<Map<String, dynamic>> results,
    required String querySummary,
  }) {
    if (results.isEmpty) {
      return '''[Tool Result: $toolName]
Status: No active profiles in your community matched all criteria ($querySummary).
Instruction: Tell the user honestly that no exact matches were found for these criteria. Do not invent any profile. Politely ask if they would like to broaden their distance or explore another interest.''';
    }

    final buffer = StringBuffer('[Tool Result: $toolName]\nFound ${results.length} verified candidate(s):\n');
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('${i + 1}. ${r['name']}, ${r['age']} (${r['city'] ?? 'Nearby'})');
      if (r['bio'] != null && r['bio'].toString().isNotEmpty) {
        buffer.writeln('   Bio: "${r['bio']}"');
      }
      buffer.writeln('   Top Interests: ${(r['interests'] as List).take(3).join(', ')}');
      buffer.writeln('   Compatibility Score: ${r['score']}%');
      if (r['rationale'] != null) {
        buffer.writeln('   Match Insight: ${r['rationale']}');
      }
    }
    buffer.writeln('Instruction: Present these genuine candidates with charisma. Highlight the specific shared interests (e.g. travel, photography) that connect them to the user. Keep it natural and concise.');
    return buffer.toString();
  }

  /// Extracts and validates a tool call from LLM output text
  static CupidToolCall? parseToolCall(String text) {
    // 1. Look for ```tool_call ... ``` or <tool_call> ... </tool_call>
    final regex = RegExp(r'```(?:tool_call|json)?\s*(\{[\s\S]*?\})\s*```', caseSensitive: false);
    final match = regex.firstMatch(text);

    String? jsonCandidate;
    if (match != null) {
      jsonCandidate = match.group(1);
    } else {
      // Look for standalone JSON object with "name" and "arguments"
      final rawMatch = RegExp(r'(\{\s*"name"\s*:\s*"[^"]+"\s*,\s*"arguments"\s*:\s*\{[\s\S]*?\}\s*\})').firstMatch(text);
      if (rawMatch != null) {
        jsonCandidate = rawMatch.group(1);
      }
    }

    if (jsonCandidate == null) return null;

    try {
      final decoded = jsonDecode(jsonCandidate.trim());
      if (decoded is! Map<String, dynamic>) return null;

      final name = decoded['name']?.toString();
      final args = decoded['arguments'];
      final argsMap = (args is Map<String, dynamic>) ? args : <String, dynamic>{};

      switch (name) {
        case discoverProfilesName:
          return CupidToolCall(
            type: CupidToolType.discoverProfiles,
            name: discoverProfilesName,
            arguments: _sanitizeDiscoverArgs(argsMap),
          );

        case refineSearchName:
          return CupidToolCall(
            type: CupidToolType.refineSearch,
            name: refineSearchName,
            arguments: _sanitizeRefineArgs(argsMap),
          );

        case getProfileDetailsName:
          return CupidToolCall(
            type: CupidToolType.getProfileDetails,
            name: getProfileDetailsName,
            arguments: {
              'profileName': argsMap['profileName']?.toString(),
              'profileIndex': (argsMap['profileIndex'] is num) ? (argsMap['profileIndex'] as num).toInt() : null,
            },
          );

        case appFeatureInfoName:
          return CupidToolCall(
            type: CupidToolType.appFeatureInfo,
            name: appFeatureInfoName,
            arguments: {'feature': argsMap['feature']?.toString() ?? 'general'},
          );

        case datingAdviceName:
          return CupidToolCall(
            type: CupidToolType.datingAdvice,
            name: datingAdviceName,
            arguments: {'topic': argsMap['topic']?.toString() ?? 'dating'},
          );

        case askClarificationName:
          return CupidToolCall(
            type: CupidToolType.askClarification,
            name: askClarificationName,
            arguments: {
              'question': argsMap['question']?.toString() ?? 'Tell me more about what you have in mind!',
              'suggestions': _toStringList(argsMap['suggestions']),
            },
          );

        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Removes the tool_call code block from the user-facing text
  static String cleanToolCallMarkup(String text) {
    return text
        .replaceAll(RegExp(r'```(?:tool_call|json)?\s*\{[\s\S]*?\}\s*```', caseSensitive: false), '')
        .replaceAll(RegExp(r'\{\s*"name"\s*:\s*"[^"]+"\s*,\s*"arguments"\s*:\s*\{[\s\S]*?\}\s*\}'), '')
        .trim();
  }

  static Map<String, dynamic> _sanitizeDiscoverArgs(Map<String, dynamic> raw) {
    return {
      'interests': _toStringList(raw['interests']),
      'personalityTraits': _toStringList(raw['personalityTraits']),
      'relationshipIntent': raw['relationshipIntent']?.toString(),
      'dealbreakers': _toStringList(raw['dealbreakers']),
      'genderHint': raw['genderHint']?.toString(),
      'minAge': (raw['minAge'] is num) ? (raw['minAge'] as num).toInt() : null,
      'maxAge': (raw['maxAge'] is num) ? (raw['maxAge'] as num).toInt() : null,
      'prefersNearby': raw['prefersNearby'] == true,
    };
  }

  static Map<String, dynamic> _sanitizeRefineArgs(Map<String, dynamic> raw) {
    return {
      'addedInterests': _toStringList(raw['addedInterests']),
      'addedTraits': _toStringList(raw['addedTraits']),
      'addedDealbreakers': _toStringList(raw['addedDealbreakers']),
    };
  }

  static List<String> _toStringList(dynamic val) {
    if (val is List) {
      return val.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }
}
