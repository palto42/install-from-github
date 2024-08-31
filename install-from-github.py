import os
import sys
import shutil
import subprocess
import requests
import json
import argparse

# Constants
CACHE_DIR = os.path.expanduser('~/.cache/install-from-github')
DOWNLOAD_DIR = os.path.expanduser('~/Downloads/install-from-github')
BINARY_DIR = os.path.expanduser('~/.local/bin')
CONFIG_DIR = os.path.expanduser('~/.config/install-from-github')
USER_PROJECTS = os.path.join(CONFIG_DIR, 'projects.txt')

ACCEPT_FILTER = '64'
IGNORE_FILTER_PACKAGE = 'arm|ppc'
IGNORE_FILTER_ARCHIVE = 'mac|macos|darwin|apple|win|bsd|arm|aarch|ppc|i686|sha256|deb$|rpm$|apk$|sig$|proxy-linux'

WGET = 'wget'
WGET_ARGS = '--continue --timestamping'

# ANSI colors for output
class Colors:
    RED = '\033[0;31m'
    MAGENTA = '\033[0;35m'
    YELLOW = '\033[0;33m'
    BLUE = '\033[0;34m'
    GREEN = '\033[0;32m'
    BOLD = '\033[1m'
    RESET = '\033[0m'

def colorize(text, color):
    return f"{color}{text}{Colors.RESET}"

def header(message):
    print(colorize(message, Colors.MAGENTA))

def warn(message):
    print(colorize(message, Colors.YELLOW))

def info(message):
    print(colorize(message, Colors.BLUE))

def note(message):
    print(colorize(message, Colors.GREEN))

def error(message):
    print(colorize(message, Colors.RED), file=sys.stderr)

def die(message):
    error(message)
    sys.exit(1)

# Utility functions
def is_binary(file_path):
    try:
        subprocess.run(['readelf', '--file-header', file_path], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except subprocess.CalledProcessError:
        return False

def is_in_path(directory):
    return directory in os.environ['PATH']

def download_asset_list(project, filename, verbose=False, dev_mode=False):
    if dev_mode and os.path.exists(filename):
        return
    info(f"Downloading asset list for {project}...")
    try:
        url = f"https://api.github.com/repos/{project}/releases/latest"
        response = requests.get(url)
        if response.status_code == 200:
            with open(filename, 'w') as f:
                f.write(response.text)
            if verbose:
                print(response.text)
        else:
            error(f"Failed to download {project}: {response.status_code}")
            return False
    except Exception as e:
        error(f"Download failed: {e}")
        return False
    return True

def extract_archive(filename, verbose=False):
    folder, ext = os.path.splitext(filename)
    if os.path.exists(folder):
        shutil.rmtree(folder)
    os.mkdir(folder)
    info(f"Extracting {filename} into {folder}...")
    cmd = []
    if filename.endswith('.tar.gz'):
        cmd = ['tar', '-xzf', filename, '-C', folder]
    elif filename.endswith('.tar.xz'):
        cmd = ['tar', '-xJf', filename, '-C', folder]
    elif filename.endswith('.zip'):
        cmd = ['unzip', '-q', filename, '-d', folder]
    else:
        warn(f"Unknown archive file type for {filename}")
        return

    subprocess.run(cmd, check=True)
    # Move executables to BINARY_DIR
    executables = []
    for root, _, files in os.walk(folder):
        for file in files:
            full_path = os.path.join(root, file)
            if os.access(full_path, os.X_OK):
                shutil.copy(full_path, BINARY_DIR)
                executables.append(full_path)

    if executables:
        info(f"Copied executables to {BINARY_DIR}: {', '.join([os.path.basename(f) for f in executables])}")

def download_and_extract_archive(project, filename, prefer_musl=False, appimage=False, dev_mode=False):
    info(f"Filtering archives for {project}")
    with open(filename, 'r') as f:
        asset_data = json.load(f)
    
    assets = asset_data.get("assets", [])
    download_url = None
    for asset in assets:
        asset_name = asset.get("name", "")
        asset_url = asset.get("browser_download_url", "")
        if ACCEPT_FILTER in asset_name and not any(ignored in asset_name for ignored in IGNORE_FILTER_ARCHIVE.split('|')):
            if prefer_musl and 'musl' in asset_name:
                download_url = asset_url
            elif appimage and 'AppImage' in asset_name:
                download_url = asset_url
            elif not prefer_musl and not appimage:
                download_url = asset_url
            break

    if download_url:
        info(f"Downloading archive: {download_url}")
        filename = os.path.join(DOWNLOAD_DIR, os.path.basename(download_url))
        if not dev_mode:
            subprocess.run([WGET, WGET_ARGS, download_url], check=True)
            extract_archive(filename)
    else:
        warn(f"No matching archives found for {project}")

def main():
    parser = argparse.ArgumentParser(description='Download and install GitHub releases.')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')
    parser.add_argument('-d', '--dev', action='store_true', help='Development mode')
    parser.add_argument('-m', '--prefer-musl', action='store_true', help='Prefer musl packages')
    parser.add_argument('-A', '--appimage', action='store_true', help='Prefer AppImage packages')
    parser.add_argument('-f', '--force', action='store_true', help='Force re-install')
    parser.add_argument('projects', nargs='*', help='GitHub projects (e.g., user/repo)')
    args = parser.parse_args()

    os.makedirs(DOWNLOAD_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR, exist_ok=True)
    os.makedirs(CONFIG_DIR, exist_ok=True)

    projects = args.projects or []
    if not projects:
        # Read from projects.txt if no projects are provided
        if os.path.exists(USER_PROJECTS):
            with open(USER_PROJECTS) as f:
                projects = [line.strip().split('#', 1)[0] for line in f if line.strip()]

    if not projects:
        error("No projects to install.")
        sys.exit(1)

    for project in projects:
        header(f"Processing {project}")
        asset_file = os.path.join(CACHE_DIR, f"{project.replace('/', '_')}_assets.json")
        if download_asset_list(project, asset_file, verbose=args.verbose, dev_mode=args.dev):
            download_and_extract_archive(project, asset_file, prefer_musl=args.prefer_musl, appimage=args.appimage, dev_mode=args.dev)

if __name__ == "__main__":
    main()
