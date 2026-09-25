import re

path = r'c:\Users\DELL\Downloads\Situationship\lib\features\profile\screens\profile_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Add import for app_palette.dart if missing
if "import '../../../core/theme/app_palette.dart';" not in text:
    text = text.replace(
        "import '../../../core/theme/app_theme.dart';",
        "import '../../../core/theme/app_theme.dart';\nimport '../../../core/theme/app_palette.dart';"
    )

# 2. In build method, obtain palette
old_build_start = """    final isDark = Theme.of(context).brightness == Brightness.dark;"""
new_build_start = """    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = ref.watch(appPaletteProvider);"""
text = text.replace(old_build_start, new_build_start, 1)

# 3. Pass palette to methods in slivers
text = text.replace("_buildGlassHeader(context, user, isDark)", "_buildGlassHeader(context, user, isDark, palette)")
text = text.replace("_buildStats(user, posts.length, context, isDark)", "_buildStats(user, posts.length, context, isDark, palette)")
text = text.replace("_buildVisitorsCard(context, user, isDark)", "_buildVisitorsCard(context, user, isDark, palette)")
text = text.replace("_buildBio(user, context, isDark)", "_buildBio(user, context, isDark, palette)")
text = text.replace("_buildInterests(user, context, isDark)", "_buildInterests(user, context, isDark, palette)")
text = text.replace("_buildGridHeader(context, isDark, posts.length)", "_buildGridHeader(context, isDark, posts.length, palette)")

# 4. _buildGlassHeader definition and body
text = text.replace(
    "Widget _buildGlassHeader(BuildContext context, UserModel user, bool isDark) {",
    "Widget _buildGlassHeader(BuildContext context, UserModel user, bool isDark, AppPalette palette) {"
)
text = text.replace(
    "painter: _AvatarRingPainter(\n                    angle: _ringAnim.value * 2 * math.pi,\n                  ),",
    "painter: _AvatarRingPainter(\n                    angle: _ringAnim.value * 2 * math.pi,\n                    palette: palette,\n                  ),"
)
text = text.replace(
    "const Icon(Icons.location_on_rounded, size: 12, color: Color(0xFFFF2D87)),",
    "Icon(Icons.location_on_rounded, size: 12, color: palette.primary),"
)
text = text.replace(
    "gradientColors: const [Color(0xFFFF2D87), Color(0xFFEC4899)],",
    "gradientColors: [palette.primary, palette.secondary],"
)
text = text.replace(
    "gradientColors: [const Color(0xFFFF2D87), const Color(0xFFEC4899)],",
    "gradientColors: [palette.primary, palette.secondary],"
)
text = text.replace(
    "gradientColors: [const Color(0xFFEC4899), const Color(0xFFFF2D87)],",
    "gradientColors: [palette.secondary, palette.primary],"
)

# 5. _buildStats definition and body
text = text.replace(
    "Widget _buildStats(UserModel user, int postCount, BuildContext context, bool isDark) {",
    "Widget _buildStats(UserModel user, int postCount, BuildContext context, bool isDark, AppPalette palette) {"
)
text = text.replace(
    "color: isDark ? const Color(0xFFEC4899).withOpacity(0.35) : const Color(0xFFEC4899).withOpacity(0.2),",
    "color: palette.primary.withOpacity(isDark ? 0.35 : 0.2),"
)
text = text.replace(
    "color: const Color(0xFFEC4899).withOpacity(isDark ? 0.2 : 0.08),",
    "color: palette.primary.withOpacity(isDark ? 0.2 : 0.08),"
)
text = text.replace(
    "color: const Color(0xFFFF2D87),\n                  isDark: isDark,\n                ),\n                _Divider(isDark: isDark),\n                _StatItem(\n                  icon: Icons.favorite_rounded,\n                  label: 'Likes',\n                  value: '${user.likedBy.length}',\n                  color: const Color(0xFFFF2D87),",
    "color: palette.primary,\n                  isDark: isDark,\n                ),\n                _Divider(isDark: isDark),\n                _StatItem(\n                  icon: Icons.favorite_rounded,\n                  label: 'Likes',\n                  value: '${user.likedBy.length}',\n                  color: palette.secondary,"
)
text = text.replace(
    "color: const Color(0xFFEC4899),\n                  isDark: isDark,\n                ),",
    "color: palette.accent,\n                  isDark: isDark,\n                ),"
)

# 6. _buildVisitorsCard definition and body
text = text.replace(
    "Widget _buildVisitorsCard(BuildContext context, UserModel currentUser, bool isDark) {",
    "Widget _buildVisitorsCard(BuildContext context, UserModel currentUser, bool isDark, AppPalette palette) {"
)
text = text.replace(
    "color: const Color(0xFFEC4899).withOpacity(isDark ? 0.35 : 0.2),",
    "color: palette.primary.withOpacity(isDark ? 0.35 : 0.2),"
)
text = text.replace(
    "color: const Color(0xFFEC4899).withOpacity(isDark ? 0.18 : 0.08),",
    "color: palette.primary.withOpacity(isDark ? 0.18 : 0.08),"
)
text = text.replace(
    "colors: [Color(0xFFEC4899), Color(0xFFFF2D87)],",
    "colors: [palette.primary, palette.secondary],"
)
text = text.replace(
    "colors: [Color(0xFFFF2D87), Color(0xFFEC4899)],",
    "colors: [palette.primary, palette.secondary],"
)
text = text.replace(
    "color: const Color(0xFFFF2D87).withOpacity(0.3),",
    "color: palette.primary.withOpacity(0.3),"
)

# 7. _buildBio definition and body
text = text.replace(
    "Widget _buildBio(UserModel user, BuildContext context, bool isDark) {",
    "Widget _buildBio(UserModel user, BuildContext context, bool isDark, AppPalette palette) {"
)
text = text.replace(
    "color: isDark ? const Color(0xFFFFBEDA) : const Color(0xFFEC4899),",
    "color: isDark ? palette.accent : palette.primary,"
)

# 8. _buildInterests definition and body
text = text.replace(
    "Widget _buildInterests(UserModel user, BuildContext context, bool isDark) {",
    "Widget _buildInterests(UserModel user, BuildContext context, bool isDark, AppPalette palette) {"
)
text = text.replace(
    "const color = Color(0xFFEC4899);",
    "final color = palette.primary;"
)
text = text.replace(
    "color: isDark ? Colors.white : const Color(0xFFFF2D87),",
    "color: isDark ? Colors.white : palette.primary,"
)

# 9. _buildGridHeader definition and body
text = text.replace(
    "Widget _buildGridHeader(BuildContext context, bool isDark, int count) {",
    "Widget _buildGridHeader(BuildContext context, bool isDark, int count, AppPalette palette) {"
)

# 10. _AvatarRingPainter class
text = text.replace(
    """class _AvatarRingPainter extends CustomPainter {
  final double angle;
  const _AvatarRingPainter({required this.angle});""",
    """class _AvatarRingPainter extends CustomPainter {
  final double angle;
  final AppPalette palette;
  const _AvatarRingPainter({required this.angle, required this.palette});"""
)
text = text.replace(
    """    final gradient = SweepGradient(
      startAngle: angle,
      endAngle: angle + math.pi * 2,
      colors: const [
        Color(0xFFFF2D87),
        Color(0xFFEC4899),
        Color(0xFFFFE44D),
        Color(0xFFFF2D87),
        Color(0xFFEC4899),
      ],
    );""",
    """    final gradient = SweepGradient(
      startAngle: angle,
      endAngle: angle + math.pi * 2,
      colors: [
        palette.primary,
        palette.secondary,
        palette.accent,
        palette.primary,
        palette.secondary,
      ],
    );"""
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Updated profile_screen.dart successfully!")
