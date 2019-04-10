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

echo "1..5"

${CMD_PREFIX} ostree --repo=sysroot/ostree/repo pull-local --remote=testos testos-repo testos/buildmaster/x86_64-runtime

${CMD_PREFIX} ostree admin deploy --os=testos testos:testos/buildmaster/x86_64-runtime
assert_has_dir sysroot/boot/ostree/testos-${bootcsum}

initial_rev=$(${CMD_PREFIX} ostree --repo=sysroot/ostree/repo rev-parse testos/buildmaster/x86_64-runtime)
echo "initial_rev=${initial_rev}"

# Configure kargs stored in the ostree commit.
mkdir -p osdata/usr/lib/ostree-boot
os_tree_write_file "usr/lib/ostree-boot/kargs" "FOO=USR_1"
os_repository_commit "testos-repo"

# Upgrade to tree with newly-committed kargs file.
${CMD_PREFIX} ostree --repo=sysroot/ostree/repo remote add --set=gpg-verify=false testos file://$(pwd)/testos-repo testos/buildmaster/x86_64-runtime
${CMD_PREFIX} ostree admin upgrade --os=testos
# Sanity check a new boot directory was created after upgrading.
assert_has_dir sysroot/boot/ostree/testos-${bootcsum}

assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'FOO=USR_1'
assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'ostree-kargs-generated-from-config.*true'

echo "ok default kargs base config"

# Configure kargs stored in the default configuration (/usr/etc).
mkdir -p osdata/usr/etc/ostree
os_tree_write_file "usr/etc/ostree/kargs" "MOO=ETC_USR_1"
os_repository_commit "testos-repo"

${CMD_PREFIX} ostree admin upgrade --os=testos
assert_has_dir sysroot/boot/ostree/testos-${bootcsum}

assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'MOO=ETC_USR_1'
assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'FOO=USR_1'
assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'ostree-kargs-generated-from-config.*true'

echo "ok default kargs default config"

# Configure kargs through the host config file.
rev=$(${CMD_PREFIX} ostree --repo=sysroot/ostree/repo rev-parse testos/buildmaster/x86_64-runtime)
echo "rev=${rev}"
etc=sysroot/ostree/deploy/testos/deploy/${rev}.0/etc
assert_has_dir ${etc}
mkdir -p ${etc}/ostree
echo "HELLO=ETC_1" > ${etc}/ostree/kargs

# Re-deploy with host-configured kernel args.
${CMD_PREFIX} ostree admin deploy --os=testos testos:testos/buildmaster/x86_64-runtime

assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'HELLO=ETC_1'
assert_not_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'MOO=ETC_USR_1'
assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'FOO=USR_1'
assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'ostree-kargs-generated-from-config.*true'

echo "ok default kargs host config"

rev=$(${CMD_PREFIX} ostree --repo=sysroot/ostree/repo rev-parse testos/buildmaster/x86_64-runtime)
echo "rev=${rev}"
etc=sysroot/ostree/deploy/testos/deploy/${rev}.1/etc
echo "" > ${etc}/ostree/kargs

${CMD_PREFIX} ostree admin deploy --os=testos testos:testos/buildmaster/x86_64-runtime

assert_not_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'HELLO=ETC_1'
assert_not_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'MOO=ETC_USR_1'
assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'FOO=USR_1'
assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'ostree-kargs-generated-from-config.*true'

echo "ok default kargs clear host config"

${CMD_PREFIX} ostree admin upgrade --os=testos --allow-downgrade --override-commit=${initial_rev}

assert_not_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'HELLO=ETC_1'
assert_not_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'MOO=ETC_USR_1'
assert_not_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'FOO=USR_1'
assert_file_has_content sysroot/boot/loader/entries/ostree-2-testos.conf 'ostree-kargs-generated-from-config.*true'

echo "ok default kargs downgrade"
