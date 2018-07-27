# Ostree Build Dependencies

- [Overview](#overview)
    - [rpm dependencies](#rpm-dependencies)
- [Dependencies when running `./autogen.sh`](#autogen-dep)
- [Dependencies when running `./configure`](#configure-dep)
- [Dependencies when running `make`](#make-dep)

---

## [Overview](#overview)

The dependencies listed here can be resolved by running:

`sudo dnf builddep ostree`

For a Debian based OS: 

`sudo apt build-dep ostree`.

This guide would be useful if you didn't run `builddep` and encountered one of these errors.

### [rpm dependencies](#rpm-dependencies)

This package, `redhat-rpm-config`, does not come with `builddep`. You will encounter this error, `missing: usr/lib/rpm/redhat/redhat-hardened-cc1`, if not installed.

Run `sudo dnf install redhat-rpm-config` to resolve.

`redhat-rpm-config` provides default flags for the complier and linker in ostree and most rpm packages.

A [bugzilla discussion](https://bugzilla.redhat.com/show_bug.cgi?id=1217376) about `redhat-rpm-config`.

You may run, `sudo dnf install @buildsys-build`. This includes `redhat-rpm-config` and a set of packages in the _base buildroot_ to generate RPMs.

[libbuild.sh](https://github.com/ostreedev/ostree/blob/master/ci/libpaprci/libbuild.sh#L38) contains the required packages to build ostree in a container.

## [Dependencies when running `./autogen.sh`](#autogen-dep)

``` bash
env NOCONFIGURE=1 ./autogen.sh
You don't have gtk-doc installed, and thus won't be able to generate the documentation.
autoreconf: Entering directory `.'
autoreconf: configure.ac: not using Gettext
autoreconf: running: aclocal -I buildutil -I libglnx ${ACLOCAL_FLAGS} --output=aclocal.m4t
sh: aclocal: command not found
autoreconf: aclocal failed with exit status: 127
```
Resolve by, running:
``` bash
sudo dnf install autoconf && \
sudo dnf install gtk-doc
```
***
``` bash
env NOCONFIGURE=1 ./autogen.sh
autoreconf: Entering directory `.'
autoreconf: configure.ac: not using Gettext
autoreconf: running: aclocal --force -I buildutil -I libglnx ${ACLOCAL_FLAGS}
configure.ac:108: warning: macro 'AM_PATH_GLIB_2_0' not found in library
configure.ac:216: warning: macro 'AM_PATH_GPGME_PTHREAD' not found in library
autoreconf: configure.ac: tracing
autoreconf: configure.ac: not using Libtool
autoreconf: running: /usr/bin/autoconf --force
configure.ac:108: error: possibly undefined macro: AM_PATH_GLIB_2_0
      If this token and others are legitimate, please use m4_pattern_allow.
      See the Autoconf documentation.
autoreconf: /usr/bin/autoconf failed with exit status: 1
```

To resolve `warning: macro 'AM_PATH_GPGME_PTHREAD' not found in library`, run:

``` bash
sudo dnf install gpgme-devel
```

To resolve `warning: macro 'AM_PATH_GPGME_PTHREAD' not found in library`, run:

```bash
sudo dnf install glib2-devel
```
***
```bash
error: Libtool library used but 'LIBTOOL' is undefined
The usual way to define 'LIBTOOL' is to add 'LT_INIT'
to 'configure.ac' and run 'aclocal' and 'autoconf' again.
If 'LT_INIT' is in 'configure.ac', make sure
its definition is in aclocal's search path.
```

To resolve the above warning, run: `sudo dnf install libtool`

## [Dependencies when running `./configure`](#configure-dep)

```
configure: error: bison not found but required
```

Will require `m4`, i.e. `sudo dnf install m4`

To resolve, run `sudo dnf install bison`

If install error occurs, may need to install `libiconv`.

***
```bash
checking for OT_DEP_LZMA... no
configure: error: Package requirements (liblzma >= 5.0.5) were not met:

Package 'liblzma', required by 'virtual:world', not found

Consider adjusting the PKG_CONFIG_PATH environment variable if you
installed software in a non-standard prefix.

Alternatively, you may set the environment variables OT_DEP_LZMA_CFLAGS
and OT_DEP_LZMA_LIBS to avoid the need to call pkg-config.
See the pkg-config man page for more details.
```
Resolve by:
```
sudo dnf install xz-devel
```
***
```bash
checking for OT_DEP_E2P... no
configure: error: Package requirements (e2p) were not met:

Package 'e2p', required by 'virtual:world', not found

Consider adjusting the PKG_CONFIG_PATH environment variable if you
installed software in a non-standard prefix.

Alternatively, you may set the environment variables OT_DEP_E2P_CFLAGS
and OT_DEP_E2P_LIBS to avoid the need to call pkg-config.
See the pkg-config man page for more details.
```
Resolve by, running:
```
sudo dnf install e2fsprogs-devel
```
***
```bash
configure: error: Package requirements (fuse >= 2.9.2) were not met:

Package 'fuse', required by 'virtual:world', not found

Consider adjusting the PKG_CONFIG_PATH environment variable if you
installed software in a non-standard prefix.

Alternatively, you may set the environment variables BUILDOPT_FUSE_CFLAGS
and BUILDOPT_FUSE_LIBS to avoid the need to call pkg-config.
See the pkg-config man page for more details.
```
Resolve by, running:
```
sudo dnf install fuse-devel
```

## [Dependencies when running `make`](#make-dep)

```bash
  CC       src/ostree/ostree-parse-datetime.o
  CCLD     ostree
./.libs/libostree-1.so: error: undefined reference to 'gpg_strerror_r'
collect2: error: ld returned 1 exit status
make[2]: *** [Makefile:3831: ostree] Error 1
make[2]: Leaving directory '/home/user/github/ostree'
make[1]: *** [Makefile:7031: all-recursive] Error 1
make[1]: Leaving directory '/home/user/github/ostree'
make: *** [Makefile:2799: all] Error 2
```
Checked if these were installed:

- `libgcrypt`
- `libgpg-error` and `libgpg-error-devel`

If error persists, this may be a linker issue with ELF:  

```bash
update-alternatives --config ld
```

Information on:

- [Gold Linker](https://en.wikipedia.org/wiki/Gold_(linker))
- [Executable and Linkable Format (ELF)](https://en.wikipedia.org/wiki/Executable_and_Linkable_Format)
- [GNU Linker](https://en.wikipedia.org/wiki/GNU_linker) i.e. the implementation of `ld`.

```bash
There are 2 programs which provide 'ld'.

  Selection    Command
-----------------------------------------------
*+ 1           /usr/bin/ld.bfd
   2           /usr/bin/ld.gold
```

The **+** sign should be on selection **1**.

Ostree currently uses the GNU linker as the default linker in compiling the executable. Having `fuse-ld=gold` in a Fedora 28 the _buildroot_ will break the build as gold doesn't _search indirect dependencies_.
