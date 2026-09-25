import os
import re
import subprocess

def get_analyzer_errors():
    res = subprocess.run('flutter analyze', shell=True, capture_output=True, text=True, cwd=r'c:\Users\DELL\Downloads\Situationship')
    errors = []
    for line in res.stdout.splitlines():
        if 'error - ' in line and ('invalid_constant' in line or 'const_with_non_constant_argument' in line or 'const_initialized_with_non_constant_value' in line):
            m = re.search(r'error - .*? - (lib[\\/][^:]+):(\d+):(\d+)', line)
            if m:
                errors.append((m.group(1), int(m.group(2)), int(m.group(3))))
    return errors

def fix_file(file_path, error_lines):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.readlines()

    modified = False
    for lnum in sorted(error_lines, reverse=True):
        idx = lnum - 1
        if idx >= len(content):
            continue
        line = content[idx]
        
        # Check if 'const ' is right on this line
        if 'const ' in line:
            # Replace 'const '
            new_line = re.sub(r'\bconst\s+', '', line, count=1)
            if new_line != line:
                content[idx] = new_line
                modified = True
                continue

        # Look upwards within up to 10 lines for the enclosing const
        found = False
        for back in range(1, 12):
            if idx - back < 0:
                break
            prev_line = content[idx - back]
            if 'const ' in prev_line:
                # Remove const from that enclosing line
                new_prev = re.sub(r'\bconst\s+', '', prev_line, count=1)
                if new_prev != prev_line:
                    content[idx - back] = new_prev
                    modified = True
                    found = True
                    break
            # If we hit a closing bracket or something indicating a completely different block, stop
            if prev_line.strip().endswith(';') and not prev_line.strip().startswith('return'):
                break

    if modified:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.writelines(content)
        print(f"Fixed consts in {file_path}")

def main():
    for iteration in range(5):
        print(f"--- Iteration {iteration+1} ---")
        errors = get_analyzer_errors()
        print(f"Found {len(errors)} constant errors")
        if not errors:
            print("All constant errors resolved!")
            break
        
        by_file = {}
        for path, lnum, col in errors:
            by_file.setdefault(path, set()).add(lnum)
            
        for path, lines in by_file.items():
            fix_file(path, lines)

if __name__ == '__main__':
    main()
