import os
import re

lib_dir = r'c:\Users\DELL\Downloads\Situationship\lib'

# Target files with hardcoded pinks
files_to_update = [
    r'features\profile\screens\user_detail_screen.dart',
    r'features\match\screens\communities_screen.dart',
    r'features\match\screens\create_community_screen.dart',
    r'features\match\screens\match_screen.dart',
    r'features\match\widgets\discover_tab.dart',
    r'features\match\widgets\nearly_souls_tab.dart',
    r'features\match\widgets\swipe_card.dart',
    r'features\match\widgets\swipe_deck.dart',
    r'features\feed\widgets\quick_post_box.dart',
    r'features\feed\widgets\post_card.dart',
    r'features\chat\screens\chat_detail_screen.dart',
    r'features\chat\screens\chats_screen.dart',
    r'features\spotlight\screens\spotlight_screen.dart',
    r'features\spotlight\widgets\spotlight_section.dart',
    r'shared\widgets\profile_choice_sheet.dart',
]

for rel_path in files_to_update:
    full_path = os.path.join(lib_dir, rel_path)
    if not os.path.exists(full_path):
        print(f"Skipping {full_path} (not found)")
        continue

    with open(full_path, 'r', encoding='utf-8') as f:
        text = f.read()

    original = text

    # Ensure AppTheme is imported
    if "AppTheme" not in text and "app_theme.dart" not in text:
        # compute relative import
        depth = rel_path.count(os.sep)
        prefix = '../' * depth
        import_stmt = f"import '{prefix}core/theme/app_theme.dart';\n"
        text = import_stmt + text
    elif "app_theme.dart" not in text:
        depth = rel_path.count(os.sep)
        prefix = '../' * depth
        import_stmt = f"import '{prefix}core/theme/app_theme.dart';\n"
        text = import_stmt + text

    # Replace gradients first
    text = re.sub(r'const\s*\[\s*Color\(0xFFFF2D87\)\s*,\s*Color\(0xFFEC4899\)\s*\]', '[AppTheme.primaryBlue, AppTheme.accentPurple]', text)
    text = re.sub(r'\[\s*Color\(0xFFFF2D87\)\s*,\s*Color\(0xFFEC4899\)\s*\]', '[AppTheme.primaryBlue, AppTheme.accentPurple]', text)
    text = re.sub(r'\[\s*const\s*Color\(0xFFFF2D87\)\s*,\s*const\s*Color\(0xFFEC4899\)\s*\]', '[AppTheme.primaryBlue, AppTheme.accentPurple]', text)

    text = re.sub(r'const\s*\[\s*Color\(0xFFEC4899\)\s*,\s*Color\(0xFFFF2D87\)\s*\]', '[AppTheme.accentPurple, AppTheme.primaryBlue]', text)
    text = re.sub(r'\[\s*Color\(0xFFEC4899\)\s*,\s*Color\(0xFFFF2D87\)\s*\]', '[AppTheme.accentPurple, AppTheme.primaryBlue]', text)
    text = re.sub(r'\[\s*const\s*Color\(0xFFEC4899\)\s*,\s*const\s*Color\(0xFFFF2D87\)\s*\]', '[AppTheme.accentPurple, AppTheme.primaryBlue]', text)

    text = re.sub(r'\[\s*Color\(0xFFEC4899\)\s*,\s*Color\(0xFFFFBEDA\)\s*\]', '[AppTheme.primaryBlue, AppTheme.accentPink]', text)
    text = re.sub(r'\[\s*Color\(0xFFFF2D87\)\s*,\s*Color\(0xFFFF2D87\)\s*\]', '[AppTheme.primaryBlue, AppTheme.accentPurple]', text)

    # Replace individual colors
    text = re.sub(r'const\s+Color\(0xFFFF2D87\)', 'AppTheme.primaryBlue', text)
    text = re.sub(r'Color\(0xFFFF2D87\)', 'AppTheme.primaryBlue', text)

    text = re.sub(r'const\s+Color\(0xFFEC4899\)', 'AppTheme.accentPurple', text)
    text = re.sub(r'Color\(0xFFEC4899\)', 'AppTheme.accentPurple', text)

    text = re.sub(r'const\s+Color\(0xFFFFBEDA\)', 'AppTheme.accentPink', text)
    text = re.sub(r'Color\(0xFFFFBEDA\)', 'AppTheme.accentPink', text)

    if text != original:
        with open(full_path, 'w', encoding='utf-8') as f:
            f.write(text)
        print(f"Migrated {rel_path}")

print("All migrations complete!")
