#!/bin/sh

# Script for downloading and installing/extracting the latest release
# of given GitHub projects (only Linux/amd64: deb/rpm/apk
# or zip/tar.gz/tar.xz).
#
# Dependencies: wget, grep, awk, tr, id, readelf, xargs
# Optional:
# - for deb: dpkg
# - for rpm: rpm
# - for apk: apk
# - for zip: unzip, zipfile, wc
# - for tar.gz or tar.xz: tar, gz/xz, wc

CACHE_DIR=~/.cache/install-from-github
TMP_FILE="$CACHE_DIR/asset.txt"
DOWNLOAD_DIR=~/Downloads/install-from-github
BINARY_DIR=~/.local/bin
CONFIG_DIR=~/.config/install-from-github
USER_PROJECTS="$CONFIG_DIR/projects.txt"

ACCEPT_FILTER='64'
IGNORE_FILTER_PACKAGE='arm|ppc'
IGNORE_FILTER_ARCHIVE='mac|macos|darwin|apple|win|bsd|arm|aarch|ppc|i686|sha256|deb$|rpm$|apk$|sig$|proxy-linux'

WGET="wget"
WGET_ARGS='--continue --timestamping'
# TODO: --timestamping only available in GNU wget!?
# TODO: Use curl when wget is not available

RED=$(printf '\033[0;31m')
MAGENTA=$(printf '\033[0;35m')
YELLOW=$(printf '\033[0;33m')
BLUE=$(printf '\033[0;34m')
GREEN=$(printf '\033[0;32m')
BOLD=$(printf '\033[1m')
RESET=$(printf '\033[0m')

header() {
    echo
    echo "${MAGENTA}$1${RESET}"
}
warn() { echo "  ${YELLOW}$1${RESET}"; }
info() { echo "  ${BLUE}$1${RESET}"; }
note() { echo "${GREEN}$1${RESET}"; }
error() { echo "${RED}$1${RESET}" >&2; }
die() {
    error "$1"
    exit 1
}

usage() {
    echo "Download latest deb/rpm/apk package (if available) or archive otherwise
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
  -A, --appimage                   pick AppImage if applicable and available
  -f, --force                      force install
  -s, --system                     system install 
  -p, --project-file projects.txt  read projects from file projects.txt
                                   (one project per line)
  -u, --update-project             Update project file with provided GITHUB_PROJECT(s)
  -b, --bin-dir                    target binary directory (default: $BINARY_DIR)
  -c, --clean                      Clean download dir $DOWNLOAD_DIR and exit
  -d, --dev                        development mode: use already downloaded
                                   asset lists (if possible) and skip download
                                   of packages/archives (for testing filters)
  -P, --proxy                          Specify proxy server to be used

This script's homepage: <https://github.com/MaxGyver83/install-from-github/>
"
}

while [ "$#" -gt 0 ]; do case $1 in
    -h | --help)
        usage
        exit 0
        ;;
    -s | --system)
        if [ "$(id -u)" -ne 0 ]; then
            warn "Restart as sudo"
            exec sudo "$0" "$@"
        fi
        shift
        ;;
    -v | --verbose)
        VERBOSE=1
        shift
        ;;
    -vv | --extra-verbose)
        EXTRA_VERBOSE=1
        VERBOSE=1
        shift
        ;;
    -a | --archives-only)
        ARCHIVES_ONLY=1
        shift
        ;;
    -A | --appimage)
        APPIMAGE=1
        shift
        ;;
    -m | --prefer-musl)
        PREFER_MUSL=1
        shift
        ;;
    -f | --force)
        FORCE_INSTALL=1
        note "Force re-install latest version"
        shift
        ;;
    -c | --clean)
        CLEAN=1
        shift
        ;;
    -d | --dev)
        DEV=1
        shift
        ;;
    -p | --project-file)
        PROJECT_FILE="$(realpath "$2")"
        shift
        shift
        ;;
    -u | --update-project)
        UPDATE_PROJECT=1
        shift
        ;;
    -P | --proxy)
        export https_proxy="$2"
        shift
        shift
        ;;
    *) break ;;
    esac done

if [ "$(id -u)" -eq 0 ]; then
    IS_ROOT=1
    # Install at system level if script run as root
    note "Will install the binaries at system level for all users"
    if [ -d "/usr/local/bin" ]; then
        BINARY_DIR=/usr/local/bin
    else
        BINARY_DIR=/usr/bin
    fi
fi
[ $VERBOSE ] || WGET_ARGS="$WGET_ARGS -o /dev/null"
[ $EXTRA_VERBOSE ] && set -x

if [ $CLEAN ]; then
    note "Cleaning download dir $DOWNLOAD_DIR"
    if [ $VERBOSE ]; then
        rm -v -r ${DOWNLOAD_DIR:?}/*
    else
        rm -r ${DOWNLOAD_DIR:?}/*
    fi
    exit 0
fi

if [ -f /etc/debian_version ]; then
    PACKAGE_FILETYPE="deb"
    INSTALL_CMD="dpkg -i"
elif [ -f /etc/redhat-release ]; then
    PACKAGE_FILETYPE="rpm"
    INSTALL_CMD="rpm -i"
elif [ -f /etc/alpine-release ]; then
    PACKAGE_FILETYPE="apk"
    INSTALL_CMD="apk add --allow-untrusted"
    PREFER_MUSL=1
fi

if [ "$INSTALL_CMD" ] && [ ! $IS_ROOT ]; then
    if command -v sudo >/dev/null 2>&1; then
        INSTALL_CMD="sudo $INSTALL_CMD"
    elif command -v doas >/dev/null 2>&1; then
        INSTALL_CMD="doas $INSTALL_CMD"
    fi
fi

is_binary() {
    readelf --file-header "$1" >/dev/null 2>&1
}

is_in_PATH() {
    case "$PATH" in
    *":$1:"*) return 0 ;;
    *":$1") return 0 ;;
    "$1:"*) return 0 ;;
    *) return 1 ;;
    esac
}

download_asset_list() {
    project="$1"
    filename="$2"
    # in development mode, use cached asset list if available
    [ "$DEV" ] && [ -f "$filename" ] && return 0
    info "Downloading asset list ..."
    if result=$($WGET --server-response -O "$TMP_FILE" "https://api.github.com/repos/$project/releases/latest" 2>&1); then
        [ "$VERBOSE" ] && echo "$result"
        mv "$TMP_FILE" "$filename"
        return 0
    fi
    http_status=$(echo "$result" | grep "HTTP/")
    error "Download error: $http_status"
    [ "$VERBOSE" ] && echo "$result"
    return 1
}

download_and_install_package() {
    project="$1"
    filename="$2"
    all_packages="$(grep browser_download_url "$filename" |
        awk '{ print $2 }' | tr -d '"' |
        grep -E "\.${PACKAGE_FILETYPE}\$")"
    if [ -z "$all_packages" ]; then
        warn "No ${PACKAGE_FILETYPE} package available. Checking for archive ..."
        return 1
    fi
    count="$(echo "$all_packages" | wc -l)"
    if [ "$count" -gt 1 ]; then
        # only 64 bit, no arm, ppc
        package="$(echo "$all_packages" |
            grep -E "$ACCEPT_FILTER" |
            grep -E -i -v "$IGNORE_FILTER_PACKAGE")"
    else
        package="$all_packages"
    fi

    count="$(echo "$package" | wc -l)"
    if [ "$count" -gt 1 ]; then
        if [ $PREFER_MUSL ]; then
            package="$(echo "$package" | grep musl)"
        else
            package="$(echo "$package" | grep -v musl)"
        fi
    fi

    info "Found package: $package"

    count="$(echo "$package" | wc -l)"
    if [ -z "$package" ]; then
        note "  Skipped packages:
        $all_packages"
        warn "${PACKAGE_FILETYPE}: No matches left after filtering. Checking for archive ..."
        return 1
    elif [ "$count" -gt 1 ]; then
        warn "${PACKAGE_FILETYPE}: Too many matches left after filtering. Checking for archive ..."
        return 1
    fi
    [ $DEV ] && return 0
    info "Downloading $(basename "$package") ..."
    $WGET $WGET_ARGS "$package"
    echo "  $INSTALL_CMD $(basename "$package")"
    if ! $INSTALL_CMD "$(basename "$package")"; then
        error "Installation failed!"
        return 1
    fi
}

extract_archive() {
    case $1 in
    *.tar.gz)
        filetype='.tar.gz'
        cmd='tar -xzf'
        dir_flag='-C'
        ;;
    *.tar.xz)
        filetype='.tar.xz'
        cmd='tar -xJf'
        dir_flag='-C'
        ;;
    *.zip)
        filetype='.zip'
        cmd='unzip -q'
        dir_flag='-d'
        ;;
    *)
        warn "Unknown archive file type!"
        return
        ;;
    esac

    # extract into new subfolder
    folder="${filename%"$filetype"}"
    # remove $folder first if it already exists
    [ -d "$folder" ] && rm -rf "$folder"
    mkdir "$folder"
    info "Extracting $filename into $folder ..."
    [ "$VERBOSE" ] && echo "Source dir: $(pwd)"
    $cmd "$filename" $dir_flag "$folder"
    # copy executables into $BINARY_DIR
    find "$folder" -executable -type f -print0 | xargs -0 -I{} cp {} "$BINARY_DIR" && find "$BINARY_DIR" -type f -exec chmod +x {} \;
    executables="$(find "$folder" -executable -type f)"
    if [ -n "$executables" ]; then
        filelist="$(echo "$executables" | while read -r file; do basename "$file"; done | xargs)"
        info "Copied $BOLD$filelist$RESET$BLUE to $BINARY_DIR"
    fi
}

download_and_extract_archive() {
    project="$1"
    filename="$2"
    info "Filter: $ACCEPT_FILTER"
    archive=$(grep browser_download_url "$filename" |
        awk '{ print $2 }' | tr -d '"' |
        grep -e "$ACCEPT_FILTER" |
        grep -E -i -v "$IGNORE_FILTER_ARCHIVE")
    count="$(echo "$archive" | wc -l)"
    if [ "$count" -gt 1 ]; then
        if [ $PREFER_MUSL ]; then
            archive="$(echo "$archive" | grep musl)"
        elif [ $APPIMAGE ]; then
            archive="$(echo "$archive" | grep -i AppImage)"
        else
            archive="$(echo "$archive" | grep -v musl | grep -vi AppImage)"
        fi
    fi
    count="$(echo "$archive" | wc -l)"
    if [ -z "$archive" ]; then
        warn "archive: No matches left after filtering. Skipping $project."
        return 1
    elif [ "$count" -gt 1 ]; then
        warn "archive: Too many matches left after filtering. Skipping $project."
        info "Archives: $archive"
        return 1
    fi
    info "Download archive: $archive"
    [ $DEV ] && return 0
    filename="$(basename "$archive")"
    [ -f "$DOWNLOAD_DIR/$filename" ] && rm -rf "${DOWNLOAD_DIR:?}/$filename"
    $WGET $WGET_ARGS "$archive"
    mkdir -p $BINARY_DIR
    if is_binary "$filename"; then
        [ -x "$filename" ] || chmod +x "$filename"
        cp "$filename" $BINARY_DIR && info "Copied $BOLD$filename$RESET$BLUE into $BINARY_DIR."
    else
        extract_archive "$filename"
    fi
    AT_LEAST_ON_BINARY_COPIED=1
}

get_asset_version() {
    project="$1"
    filename="$2"
    if [ ! -e "$filename" ]; then
        info "No cached asset file for '$project'"
        return 1
    fi
    tag_name=$(grep '"tag_name"' "$filename" 2>/dev/null)
    tag_url=$(grep '"url"' "$filename" 2>/dev/null)
    asset_version=${tag_name#*tag_name\": \"}
    if [ "$asset_version" = "$tag_name" ]; then
        warn "Failed to extract version from tag url: $tag_url"
        return 1
    fi
    asset_version=${asset_version%\"*}
}

update_config() {
    project="$1"
    if ! grep -q "^$project" "$PROJECT_FILE" 2>/dev/null; then
        if echo "$project # auto-added on $(date '+%Y-%m-%d  %H:%M:%S')" >>"$PROJECT_FILE"; then
            warn "Added '$project' to project file $PROJECT_FILE"
        else
            warn "Failed to add '$project' to project file '$PROJECT_FILE'"
        fi
    else
        warn "Project file $PROJECT_FILE already contained '$project'"
    fi
}

# shellcheck disable=SC2015 # die when either mkdir or cd fails
mkdir -p "$DOWNLOAD_DIR" && cd "$DOWNLOAD_DIR" ||
    die "Could not create/change into $DOWNLOAD_DIR!"

mkdir -p "$CACHE_DIR" ||
    die "Could not create $CACHE_DIR!"

mkdir -p "$CONFIG_DIR" ||
    die "Could not create $CONFIG_DIR!"

if [ "$PROJECT_FILE" ]; then
    # ignore comments (everything after '#')
    projects="$(grep -o '^[^#]*' "$PROJECT_FILE")"
else
    PROJECT_FILE="$USER_PROJECTS"
fi

if [ -n "$1" ]; then
    # append specified projects
    projects="${projects} $*"
fi

if [ ! "$projects" ]; then
    warn "Using config file $USER_PROJECTS"
    projects="$(grep -o '^[^#]*' "$USER_PROJECTS")"
fi

if [ ! "$projects" ]; then
    usage
    exit 0
fi

for project in $projects; do
    header "$project"
    # Check if the project is not already done
    if ! printf "%s" "$done_projects" | grep -q "$project"; then
        # If not, add it to the done_projects array
        done_projects="${done_projects} ${project}"
        filename="$CACHE_DIR/$(echo "$project" | tr / _)_assets.json"
        if get_asset_version "$project" "$filename"; then
            last_version="$asset_version"
            info "Last version of $project was '$last_version'"
        else
            last_version="unknown"

        fi
        download_asset_list "$project" "$filename" ||
            die "Couldn't download asset file from GitHub!"
        [ -s "$filename" ] || {
            warn "$filename is empty!"
            continue
        }
        get_asset_version "$project" "$filename"
        if [ "$last_version" = "$asset_version" ] && [ ! "$FORCE_INSTALL" ]; then
            info "Project '$project' is already on latest version $asset_version"
            if [ "$UPDATE_PROJECT" ]; then
                update_config "$project"
            fi
            continue
        else
            if [ "$last_version" != "$asset_version" ]; then
                info "Found new version $asset_version for project '$project'"
            else
                info "Force re-install version $asset_version for project '$project'"
            fi
            if [ "$INSTALL_CMD" ] && [ ! "$ARCHIVES_ONLY" ]; then
                if download_and_install_package "$project" "$filename" && [ "$UPDATE_PROJECT" ]; then
                    update_config "$project"
                    continue
                fi
            fi
            if download_and_extract_archive "$project" "$filename" && [ "$UPDATE_PROJECT" ]; then
            update_config "$project"
            fi
        fi
    else
        warn "Duplicate entry for $project, skipping."
    fi
done

if [ "$AT_LEAST_ON_BINARY_COPIED" ] && ! is_in_PATH "$BINARY_DIR"; then
    echo
    warn "$BINARY_DIR is not in \$PATH! Add it with
PATH=\"$BINARY_DIR:\$PATH\""
fi
