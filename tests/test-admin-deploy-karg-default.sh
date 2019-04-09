#!/bin/bash
#
# Copyright (C) 2019 Robert Fairley <rfairley@redhat.com>
#
# SPDX-License-Identifier: LGPL-2.0+
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the
# Free Software Foundation, Inc., 59 Temple Place - Suite 330,
# Boston, MA 02111-1307, USA.

set -euo pipefail

. $(dirname $0)/libtest.sh

# Exports OSTREE_SYSROOT so --sysroot not needed.
setup_os_repository "archive" "syslinux"

echo "1..1"

${CMD_PREFIX} ostree --repo=sysroot/ostree/repo pull-local --remote=testos testos-repo testos/buildmaster/x86_64-runtime
rev=$(${CMD_PREFIX} ostree --repo=sysroot/ostree/repo rev-parse testos/buildmaster/x86_64-runtime)
export rev
echo "rev=${rev}"

${CMD_PREFIX} ostree admin deploy --os=testos testos:testos/buildmaster/x86_64-runtime
assert_has_dir sysroot/boot/ostree/testos-${bootcsum}

# Commit to and deploy a repo that has a default kargs file.
mkdir -p osdata/usr/lib/ostree-boot
os_tree_write_file "usr/lib/ostree-boot/kargs" "FOO=USR_1 MOO=USR_2 WOO=USR_3"
os_repository_commit "testos-repo" "1"

${CMD_PREFIX} ostree --repo=sysroot/ostree/repo remote add --set=gpg-verify=false testos file://$(pwd)/testos-repo testos/buildmaster/x86_64-runtime
${CMD_PREFIX} ostree admin upgrade --os=testos
assert_has_dir sysroot/boot/ostree/testos-${bootcsum}

assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'FOO=USR_1'

# TODO: need to check for the USR kernel args here?? i.e. should they be updated right after upgrading

# Configure kargs through the host config file.
rev=$(${CMD_PREFIX} ostree --repo=sysroot/ostree/repo rev-parse testos/buildmaster/x86_64-runtime)
export rev
echo "rev=${rev}"
etc=sysroot/ostree/deploy/testos/deploy/${rev}.1/etc
cd ${etc}
mkdir -p ostree
cd ${test_tmpdir}
echo "HELLO=ETC_1 MELLO=ETC_2 BELLO=ETC_3" > ${etc}/ostree/kargs

# Re-deploy with configured kernel args.
${CMD_PREFIX} ostree admin deploy --os=testos testos:testos/buildmaster/x86_64-runtime

assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'HELLO=ETC_1'
assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'FOO=USR_1'
assert_not_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'ostree-kargs-override'

echo "ok default kargs"
