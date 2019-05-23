#!/usr/bin/bash
# Install build dependencies, run unit tests and installed tests.

set -xeuo pipefail

dn=$(dirname $0)
. ${dn}/libpaprci/libbuild.sh

${dn}/installdeps.sh

# Default libcurl on by default in fedora unless libsoup is enabled
if test "${OS_ID}" = 'fedora'; then
    case "${CONFIGOPTS:-}" in
        *--with-soup*|*--without-curl*) ;;
        *) CONFIGOPTS="${CONFIGOPTS:-} --with-curl"
    esac
fi
case "${CONFIGOPTS:-}" in
    *--with-curl*|--with-soup*)
        if test -x /usr/bin/gnome-desktop-testing-runner; then
            CONFIGOPTS="${CONFIGOPTS} --enable-installed-tests=exclusive"
        fi
        ;;
esac

# always fail on warnings; https://github.com/ostreedev/ostree/pull/971
# NB: this disables the default set of flags from configure.ac
export CFLAGS="-Wall -Werror ${CFLAGS:-}"

build --enable-gtk-doc ${CONFIGOPTS:-}
