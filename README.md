# Install from GitHub

## What is this script good for?

TL;DR: Run `install-from-github.sh` with a list of GitHub projects to download and install/extract their latest deb/rpm/apk packages or binary archives.

Whenever I start working on a new Linux system (p.e. a server in a cluster, a VPS, a project-wide development Docker container at work) for longer than a few minutes, I want to install some tools that I'm used to. And most of these systems have Ubuntu LTS installed, with old software in their repositories and some tools not even available. In such cases, I go to GitHub.com and search the latest release's deb package matching my system, download it and install it (with `dpkg`). Sometimes, there is no deb package available, and I have to download and extract the (correct) zip/tar.gz/tar.xz archive. There is a lot of typing, clicking, copying and pasting involved. And there is no link that points always to the latest 64-bit deb package (of a project). That's why I made this script to automate this task.

This script is for 64-bit (`x86_64`) Linux systems only. It should be easy to make it work on BSD/macOS/arm systems, too. (The filters would be slightly different on such systems.)

![Screenshot of install-from-github.sh](https://maximilian-schillinger.de/img/install-from-github.png "Screenshot")

## Installation

### Clone this git repository

```sh
git clone https://github.com/MaxGyver83/install-from-github
cd install-from-github
./install-from-github.sh
```

### Download script

```sh
wget https://raw.githubusercontent.com/MaxGyver83/install-from-github/main/install-from-github.sh
chmod +x install-from-github.sh
./install-from-github.sh
```

## Usage

This script will prefer deb/rpm/apk packages and install them with `[sudo] dpkg -i PACKAGE` (or alike, in case you are using Debian/Ubuntu, RedHat or Alpine) and download + extract binary archives as a fallback. If you prefer binary archives (maybe because you don't have sudo rights), use the option `--archives-only` (or short: `-a`):

```sh
./install-from-github.sh BurntSushi/ripgrep sharkdp/fd
# or
./install-from-github.sh -p projects.txt
```

Add `-m`/`--prefer-musl` if you prefer musl over glibc variants (when applicable). This is the default behaviour in Alpine Linux.

### Install at system level

Run the script as `root` to install the programs at system level.

### Default user config

The user may store a default project file at `~/.config/install-from-github/projects.txt`.

### Command options

```console
Download latest deb/rpm/apk package (if available) or archive otherwise
for every given GITHUB_PROJECT to ~/Download/ and install/extract it.

USAGE
  ./install-from-github.sh [OPTIONS] GITHUB_PROJECTS

EXAMPLE
  ./install-from-github.sh -v -a BurntSushi/ripgrep sharkdp/fd

OPTIONS
  -h, --help                       show help
  -v, --verbose                    print output of wget command
  -vv, --extra-verbose             print every command (set -x), implies -v
  -a, --archives-only              skip searching for deb/rpm/apk packages first
  -m, --prefer-musl                pick musl package/archive if applicable and
                                   available
  -f, --force                      force install
  -p, --project-file projects.txt  read projects from file projects.txt
                                   (one project per line)
  -u, --update-project             Update project file with provided GITHUB_PROJECT(s)
  -b, --bin-dir                    target binary directory (default: ~/.local/bin)
  -c, --clean                      Clean download dir ~/Downloads/install-from-github and exit
  -d, --dev                        development mode: use already downloaded
                                   asset lists (if possible) and skip download
                                   of packages/archives (for testing filters)

This script's homepage: <https://github.com/MaxGyver83/install-from-github/>
```

## Notes

* Dependencies: wget, grep, awk, tr (and dpkg or unzip or tar + gz or xz)
* If the script doesn't work as expected, try calling it with `-v` or `-vv`.
* On Debian/Ubuntu/RedHat/Alpine: This script will try installing deb/rpm/apk packages using sudo or doas, asking for your password (cancel with Ctrl-c if you want to install later).
* The script caches the release data of the downloaded scripts in `~/.cache/install-from-github` to avoid unnecessary re-installs.
