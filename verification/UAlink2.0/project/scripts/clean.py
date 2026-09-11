#!/usr/bin/env python3
"""Run: python3 scripts/clean.py [--dry-run].
Removes generated project directories and Python caches; prints removed paths.
Next: run make test or make rtl-smoke to regenerate verification outputs.
"""
import argparse
from pathlib import Path
import shutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    root = (lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[1]))(__import__('pathlib').Path(__file__).resolve())
    paths = [root / name for name in ('build', 'reports', 'artifacts', '.pytest_cache')]
    for name in ('scripts', 'model', 'verification'):
        paths.extend((root / name).rglob('__pycache__'))
    for path in paths:
        if not path.exists() and not path.is_symlink():
            continue
        print(('Would remove ' if args.dry_run else 'Removing ') + str(path.relative_to(root)))
        if not args.dry_run:
            if path.is_symlink():
                path.unlink()
            else:
                shutil.rmtree(path)


if __name__ == '__main__':
    main()
