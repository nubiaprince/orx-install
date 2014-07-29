#!/usr/bin/env bash
#
# install-librarian.sh: Install Outernet's Librarian on RaspBMC
# Copyright (C) 2014, Outernet Inc.
# Some rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.
#

set -e

# Constants
RELEASE=0.1a3
ONDD_RELEASE="0.1.0-0"
NAME=librarian
ROOT=0
OK=0
YES=0
NO=1

# Command aliases
#
# NOTE: we use the `--no-check-certificate` because wget on RaspBMC thinks the
# GitHub's SSL cert is invalid when downloading the tarball.
#
EI="easy_install-3.4"
PIP="pip"
WGET="wget --no-check-certificate"
UNPACK="tar xzf"
MKD="mkdir -p"
PYTHON=/usr/bin/python3

# URLS and locations
TARS="https://github.com/Outernet-Project/$NAME/archive/"
DEBS="http://outernet-project.github.io/orx-install"
EXT=".tar.gz"
TARBALL="v${RELEASE}${EXT}"
SRCDIR="/opt/$NAME"
SPOOLDIR=/var/spool/downloads/content
SRVDIR=/srv/zipballs
TMPDIR=/tmp
PKGLISTS=/etc/apt/sources.list.d
INPUT_RULES=/etc/udev/rules.d/99-input.rules
LOCK=/run/lock/orx-setup.lock
LOG="install.log"

# checknet(URL)
# 
# Performs wget dry-run on provided URL to see if it works. Echoes 0 if 
# everything is OK, or non-0 otherwise.
#
checknet() {
    $WGET -q --tries=10 --timeout=20 --spider "$1" > /dev/null || echo $NO
    echo $?
}

# warn_and_die(message)
#
# Prints a big fat warning message and exits
#
warn_and_die() {
    echo "FAIL"
    echo "=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*"
    echo "$1"
    echo "=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*=*"
    exit 1
}

# section(message)
#
# Echo section start message without newline.
#
section() {
    echo -n "${1}... "
}

# fail()
# 
# Echoes "FAIL" and exits
#
fail() {
    echo "FAILED (see '$LOG' for details)"
    exit 1
}

# do_or_fail()
#
# Runs a command and fails if commands returns with a non-0 status
#
do_or_fail() {
    "$@" >> $LOG 2>&1 || fail
}

# do_or_pass()
# 
# Runs a command and ignores non-0 return
#
do_or_pass() {
    "$@" >> $LOG 2>&1 || true
}

# is_in_sources(name)
#
# Find out if any of the package source lists contain the name
is_in_sources() {
    result=$(grep -h ^deb /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>> "$LOG" | grep -o "$1" 2>> "$LOG")
    case "$result" in
        "$1") echo $YES ;;
        *) echo $NO ;;
    esac
}

# backup()
#
# Back up a file by copying it to a path with '.old' suffix and echo about it
#
backup() {
    if [[ -f "$1" ]] && ! [[ -f "${1}.old" ]]; then
        cp "$1" "${1}.old"
        echo "Backed up '$1' to '${1}.old'" >> "$LOG"
    fi
}

###############################################################################
# License
###############################################################################

cat <<EOF

=======================================================
Outernet Data Delivery agent End User License Agreement
=======================================================

Among other things, this script installs ONDD (Outernet Data Delivery agent) 
which is licensed to you under the following conditions:

This software is provided as-is with no warranty and is for use exclusively
with the Outernet satellite datacast. This software is intended for end user
applications and their evaluation. Due to licensing agreements with third
parties, commercial use of the software is strictly prohibited. 

YOU MUST AGREE TO THESE TERMS IF YOU CONTINUE.

EOF
read -p "Press any key to continue (CTRL+C to quit)..." -n 1
echo ""

###############################################################################
# Preflight checks
###############################################################################

section "Root permissions"
if [[ $EUID -ne $ROOT ]]; then
    warn_and_die "Please run this script as root."
fi
echo "OK"

section "Lock file"
if [[ -f "$LOCK" ]]; then
    warn_and_die "Already set up. Remove lock file '$LOCK' to reinstall."
fi
echo "OK"

section "Internet connection"
if [[ $(checknet "http://example.com/") != $OK ]]; then
    warn_and_die "Internet connection is required."
fi
echo "OK"

section "Port 80 free"
if [[ $(checknet "127.0.0.1:80") == $OK ]]; then
    warn_and_die "Port 80 is taken. Disable XBMC webserver and try again."
fi
echo "OK"

###############################################################################
# Packages
###############################################################################

section "Adding additional repositories"
if [[ $(is_in_sources jessie) == $NO ]]; then
    # Adds Raspbian's jessie repositories to sources.list
    cat > "$PKGLISTS/jessie.list" <<EOF
deb http://archive.raspbian.org/raspbian jessie main contrib non-free
deb-src http://archive.raspbian.org/raspbian jessie main contrib non-free
EOF
fi
echo "DONE"

section "Installing packages"
do_or_fail apt-get update
DEBIAN_FRONTEND=noninteractive do_or_fail apt-get -y --force-yes install \
    python3.4 python3.4-dev python3-setuptools
echo "DONE"

###############################################################################
# Outernet Data Delivery agent
###############################################################################

section "Installing Outernet Data Delivery agent"
do_or_fail wget --directory-prefix "$TMPDIR" \
    "$DEBS/ondd_${ONDD_RELEASE}_armhf.deb"
do_or_fail dpkg -i "$TMPDIR/ondd_${ONDD_RELEASE}_armhf.deb"
do_or_pass rm "$TMPDIR/ondd_${ONDD_RELEASE}_armhf.deb"
echo "DONE"

###############################################################################
# Librarian
###############################################################################

# Obtain and unpack the Librarian source
section "Installing Librarian"
do_or_pass rm "$TMPDIR/$TARBALL" # Make sure there aren't any old ones
do_or_fail $WGET --directory-prefix "$TMPDIR" "${TARS}${TARBALL}"
do_or_fail $UNPACK "$TMPDIR/$TARBALL" -C /opt 
do_or_pass rm "$SRCDIR" # For some reason `ln -f` doesn't work, so we remove first
do_or_fail ln -s "${SRCDIR}-${RELEASE}" "$SRCDIR"
do_or_pass rm "$TMPDIR/$TARBALL" # Remove tarball, since it's no longer needed
# Install python dependencies globally
do_or_fail $EI pip
do_or_fail $PIP install -r "$SRCDIR/conf/requirements.txt"
# Create paths necessary for the software to run
do_or_fail $MKD "$SPOOLDIR"
do_or_fail $MKD "$SRVDIR"
echo "DONE"

###############################################################################
# System services
###############################################################################

section "Configuring system services"
# Create upstart job
cat > "/etc/init/${NAME}.conf" <<EOF
description "Outernet Librarian v$RELEASE"

start on custom-network-done
stop on shutdown
respawn

script
PYTHONPATH=$SRCDIR python3 "$SRCDIR/$NAME/app.py"
end script
EOF
echo "DONE"


section "Starting Librarian"
do_or_fail service $NAME start
echo "DONE"

###############################################################################
# Cleanup
###############################################################################

touch "$LOCK"

