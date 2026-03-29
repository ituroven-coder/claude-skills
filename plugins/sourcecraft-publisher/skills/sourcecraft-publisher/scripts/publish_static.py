#!/usr/bin/env python3
"""Publish static artifacts to a SourceCraft Sites repository.

Usage:
    python3 scripts/publish_static.py --source <dir-or-html> --slug <name> [--date YYYY-MM-DD] [--message "msg"]

Requires env vars: SOURCECRAFT_TOKEN, SOURCECRAFT_REPO, SOURCECRAFT_SITE_URL
Optional: SOURCECRAFT_BRANCH (default: main)
"""
import argparse, os, re, shutil, subprocess, sys, tempfile
from datetime import datetime
from pathlib import Path

SITES_YAML = """\
site:
  root: "."
  ref: {branch}
"""


def slugify(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r'[^a-z0-9]+', '-', s)
    s = re.sub(r'-+', '-', s).strip('-')
    return s or 'page'


def run(cmd, cwd=None):
    subprocess.run(cmd, cwd=cwd, check=True)


def main():
    ap = argparse.ArgumentParser(description='Publish to SourceCraft Sites')
    ap.add_argument('--source', required=True, help='Path to built static site folder or single html file')
    ap.add_argument('--slug', required=True, help='Page slug (lowercase, hyphens)')
    ap.add_argument('--date', help='ISO date, default today')
    ap.add_argument('--message', help='Commit message')
    args = ap.parse_args()

    token = os.environ['SOURCECRAFT_TOKEN']
    repo = os.environ['SOURCECRAFT_REPO']
    branch = os.environ.get('SOURCECRAFT_BRANCH', 'main')
    base_url = os.environ['SOURCECRAFT_SITE_URL'].rstrip('/')

    dt = datetime.fromisoformat(args.date) if args.date else datetime.utcnow()
    year = dt.strftime('%Y')
    year_month = dt.strftime('%Y-%m')
    slug = slugify(args.slug)
    rel = Path(year) / year_month / slug

    src = Path(args.source).resolve()
    if not src.exists():
        raise SystemExit(f'source not found: {src}')

    with tempfile.TemporaryDirectory() as td:
        repo_dir = Path(td) / 'repo'
        remote = f'https://oauth2:{token}@git.sourcecraft.dev/{repo}.git'

        # Clone — try existing branch, fall back to init if repo is empty
        try:
            run(['git', 'clone', '--branch', branch, '--depth', '1', remote, str(repo_dir)])
        except subprocess.CalledProcessError:
            # Repo might be empty or branch doesn't exist
            repo_dir.mkdir(parents=True, exist_ok=True)
            run(['git', 'init'], cwd=repo_dir)
            run(['git', 'remote', 'add', 'origin', remote], cwd=repo_dir)
            run(['git', 'checkout', '-b', branch], cwd=repo_dir)

        # Ensure .sourcecraft/sites.yaml exists
        sc_dir = repo_dir / '.sourcecraft'
        sc_dir.mkdir(exist_ok=True)
        sites_yaml = sc_dir / 'sites.yaml'
        if not sites_yaml.exists():
            sites_yaml.write_text(SITES_YAML.format(branch=branch))

        # Prepare target directory
        target = repo_dir / rel
        if target.exists():
            shutil.rmtree(target)
        target.mkdir(parents=True, exist_ok=True)

        # Copy artifact
        if src.is_dir():
            for item in src.iterdir():
                dest = target / item.name
                if item.is_dir():
                    shutil.copytree(item, dest)
                else:
                    shutil.copy2(item, dest)
        else:
            shutil.copy2(src, target / 'index.html')

        if not (target / 'index.html').exists():
            raise SystemExit('index.html not found in published artifact')

        # Commit and push
        run(['git', 'config', 'user.name', 'OpenClaw Publisher'], cwd=repo_dir)
        run(['git', 'config', 'user.email', 'publisher@openclaw.local'], cwd=repo_dir)
        run(['git', 'add', '.'], cwd=repo_dir)
        msg = args.message or f'publish: {slug} -> {rel.as_posix()}'
        status = subprocess.run(['git', 'diff', '--cached', '--quiet'], cwd=repo_dir)
        if status.returncode == 0:
            print(f'NO_CHANGES {base_url}/{rel.as_posix()}/')
            return
        run(['git', 'commit', '-m', msg], cwd=repo_dir)
        # Force push — standard pattern for SourceCraft Sites
        run(['git', 'push', '--force', 'origin', branch], cwd=repo_dir)
        print(f'{base_url}/{rel.as_posix()}/')


if __name__ == '__main__':
    main()
