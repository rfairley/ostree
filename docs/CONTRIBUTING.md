# Contributing to OSTree

The following guide is about OSTree forking, building, adding a command, testing the command, and submitting the change.

- [Getting Started](#getting-started)
- [Building OSTree](#building-ostree)
    - [Install Build Dependencies](#install-build-dependencies)
    - [OSTree Build Commands](#ostree-build-commands)
- [Testing a Build](#testing-a-build)
    - [Testing in a Container](#testing-in-a-container)
    - [Testing in a Virtual Machine](#testing-in-a-virtual-machine)
- [Tutorial: Adding a basic builtin command to OSTree](#tutorial-adding-a-basic-builtin-command-to-ostree)
    - [Modifying OSTree](#modifying-ostree)
    - [OSTree tests](#ostree-tests)
    - [Submitting patch](#submitting-a-patch)
    - [Commit message style](#commit-message-style)
    - [Returning workflow](#returning-workflow)

---

## [Getting Started](#getting-started)

Fork https://github.com/ostreedev/ostree, the run the following commands.

```bash
$ git clone https://github.com/<username>/ostree
$ git remote add upstream https://github.com/ostreedev/ostree
$ git checkout master
$ git branch --set-upstream-to=upstream/master master
```
Make a branch from master for your patch.
```bash
$ git checkout -b <name-of-branch>
$ git branch --set-upstream-to=upstream/master <name-of-branch>
```

## [Building OSTree](#building-ostree)

### [Install Build Dependencies](#install-build-dependencies)

```bash
$ sudo dnf builddep ostree
$ sudo dnf install @buildsys-build
```

### [OSTree Build Commands](#ostree-build-commands)

```bash
git submodule update --init
./autogen.sh --prefix=/usr --libdir=/usr/lib64 --sysconfdir=/etc
./configure --prefix=/usr
make
make install DESTDIR=/path/to/install/binary
```

`make install` will generate files for `/etc` and `/usr`

For more information and issues with `./autogen.sh`, `./configure` or `make` see [Build Dependencies](/docs/misc/build-dependencies.md).

## [Testing a Build](#testing-a-build)

**TODO**: This sentense below needs more context and perhaps needs to be rephrased.

Testing OSTree could interfere with the state of your machine. To avoid this, it is preferable to test and build OSTree inside a container or virtual machine.

### [Testing in a Container](#testing-in-a-container)

Docker is the preferred containerization tool. Follow this guide to [install Docker on your host machine](https://docs.docker.com/v17.09/engine/installation/linux/docker-ce/fedora/). You may need to follow this [post-installation guide for Docker](https://docs.docker.com/v17.09/engine/installation/linux/linux-postinstall/) if you would like to run Docker as a non-root user on a Linux based host machine.

Save the contents of this **Dockerfile** somewhere on your machine:
```bash
# this pulls the latest fedora image
FROM fedora:latest

# install ostree dependencies
RUN dnf update -y && \
    dnf -y install dnf-plugins-core  && \
    dnf -y builddep ostree  && \
    dnf -y install make redhat-rpm-config && \
    dnf clean all

# clone your ostree repo
RUN git clone https://github.com/<username>/ostree.git

# pull patch-branch + set upstream
RUN cd ostree && \
    git pull origin <branch of your patch> && \
    git checkout <branch of your patch> && \
    git remote add upstream https://github.com/ostreedev/ostree.git

WORKDIR /ostree
```
**Build the container**

Run `docker build` in the same directory of the `Dockerfile` like so:

```
$ docker build -t ostree-fedora-test .
```
When this build is done, the `-t` option tags the image as `ostree-fedora-test`.  

**Note**: Do not forget the dot **.** at the end of the above command which specifies the location of the Dockerfile.



You will see `ostree-fedora-test` listed when running `docker images`:

```bash
REPOSITORY                                 TAG                 IMAGE ID            CREATED             SIZE
ostree-fedora-test                         latest              817c04cc3656        1 day ago          978MB
```

**Entering the Container**

To **start** the `ostree-fedora-test` container, run:

```bash
$ docker run -it --rm --entrypoint /bin/sh --name ostree-testing ostree-fedora-test
```
**Note**:

`--rm` option removes the name of the container i.e. `ostree-testing` whenever `exit` is initiated within the container's shell prompt `#`. This is so that the container name `ostree-testing` can be re-used, otherwise remove it manually by running `docker rm <container name>`.

The state of the container will not be saved when the shell prompt exits. Best practice is modify the Dockerfile to modify the image.

**Testing in a Container Workflow**

1. Edit the changes to OSTree on your local machine.
2. `git add` your changed files, `git commit -m "commit message"` and then `git push origin <name of local branch>`
3. From within the `ostree-testing` container, make sure your changes are pulled onto the `ostree` repo in the container. Then run the [ostree build commands](#ostree-build-commands):

```
git submodule update --init && \
env NOCONFIGURE=1 ./autogen.sh && \
./configure && \
make && \
make install
```
4. `make install` will install OSTree in the default location of the guest OS.

### [Testing in a Virtual Machine](#testing-in-a-virtual-machine)

See this guide on creating an [Atomic Host Vagrant VM](https://gist.github.com/Bubblemelon/bd9f3cf429d9e04be52f9987baed53c8).

To test a build on the Atomic Host Vagrant VM, simply `scp -r <ostree binary location> vagrant@<ip-address>:~`. You can find the IP address of a Vagrant VM by running `vagrant ssh-config` in the same directory as the `Vagrantfile`.

Run `vagrant ssh` to login to the VM. To override the `Read-only file system` warning, run `ostree admin unlock`. Now replace the original OSTree binary with the new one by running `sudo mv ~/ostree /usr/bin/ostree`.

If `which ostree` doesn't return an error then the `mv` command was successful. Test the new OSTree binary, by running the OSTree commands that you've changed.

# Tutorial: Adding a basic builtin command to ostree

## [Modifying OSTree](#modifying-ostree)

This will add a command which prints `Hello OSTree!` when `ostree hello-ostree` is entered.

1. Open the OSTree code in an editor or IDE of your choice. Having the ability to ["go to definition" helps greatly in navigating](/docs/misc/ide-configuration.md).

2. Create a file in `src/ostree` named `ot-builtin-hello-ostree.c`. Code that lives in here belongs to OSTree, and uses functionality from libostree.

3. Add the following to `ot-builtin-hello-ostree.c`:

    ```C
    #include "config.h"

    #include "ot-main.h"
    #include "ot-builtins.h"
    #include "ostree.h"
    #include "otutil.h"

    // Structure for options such as ostree hello-ostree --option.
    static GOptionEntry options[] = {
      { NULL },
    };

    gboolean
    ostree_builtin_hello_ostree (int argc, char **argv, OstreeCommandInvocation *invocation, GCancellable *cancellable, GError **error)
    {
      g_autoptr(GOptionContext) context = NULL;
      g_autoptr(OstreeRepo) repo = NULL;
      gboolean ret = FALSE;

      // Creates new command context, ready to be parsed.
      // Input to g_option_context_new shows when running ostree <command> --help
      context = g_option_context_new ("");

      // Parses the command context according to the ostree CLI.
      if (!ostree_option_context_parse (context, options, &argc, &argv, invocation, &repo, cancellable, error))
        goto out;

      g_print("Hello OSTree!\n");

      ret = TRUE;
     out:
      return ret;
    }
    ```

    This defines the functionality for `hello-ostree`. Now we have to make sure the CLI can refer to the execution function, and that autotools knows to build this file.

4. Add the following in `src/ostree/main.c`:

    ```C
    { "hello-ostree",               // The name of the command
      OSTREE_BUILTIN_FLAG_NO_REPO,  // Flag not to require the `--repo` argument, see "ot-main.h"
      ostree_builtin_hello_ostree,  // Execution function for the command
      "Print hello message" },      // Short description to appear when `ostree hello-ostree --help` is entered
    ```

5. Add a macro for the function declaration of `ostree_builtin_hello_ostree`, in `ot-builtins.h`:

    ```C
    BUILTINPROTO(hello_ostree);
    ```

    This makes the function definition visible to the CLI.

6. Configure automake to include `ot-builtin-hello-ostree.c` in the build, by adding an entry in `Makefile-ostree.am` under `ostree_SOURCES`:

    ```bash
    src/ostree/ot-builtin-hello-ostree.c \
    ```

7. Rebuild ostree:

    ```bash
    make && make install DESTDIR=/path/to/install/the/content
    ```

8. Execute the new ostree binary, from where you installed it:

    ```bash
    $ ostree hello-ostree
    Hello OSTree!
    ```

## [OSTree Tests](#ostree-tests)

Tests for OSTree are done by shell scripting, by running OSTree commands and examining output. These steps will go through adding a test for `hello-ostree`.

1. Create a file in `tests` called `test-hello-ostree.sh`.

2. Add the following to `test-hello-ostree.sh`:

    ```bash
    set -euo pipefail           # Ensure the test will not silently fail

    . $(dirname $0)/libtest.sh  # Make libtest.sh functions available

    echo "1..1"                 # Declare which test is being run out of how many

    pushd ${test_tmpdir}

    ${CMD_PREFIX} ostree hello-ostree > hello-output.txt
    assert_file_has_content hello-output.txt "Hello OSTree!"

    popd

    echo "ok hello ostree"      # Indicate test success
    ```

    Many tests require a fake repository setting up (as most OSTree commands require `--repo` to be specified). See `test-pull-depth.sh` for an example of this setup.

3. Configure automake to include `test-hello-ostree.sh` in the build, by adding an entry in `Makefile-tests.am` under `_installed_or_uninstalled_test_scripts`:

    ```bash
    tests/test-hello-ostree.sh \
    ```

4. Make sure `test-hello-ostree.sh` has executable permissions!

    ```bash
    chmod +x tests/test-hello-ostree.sh
    ```

5. Run the test:

    ```
    make check TESTS="test/test-hello-ostree.sh
    ```

    Multiple tests can be specified: `make check TESTS="test1 test2 ..."`. To run all tests, use `make check`.

    Hopefully, the test passes! The following will be printed:

    ```bash
    PASS: tests/test-hello-ostree.sh 1 hello ostree
    ============================================================================
    Testsuite summary for libostree 2018.8
    ============================================================================
    # TOTAL: 1
    # PASS:  1
    # SKIP:  0
    # XFAIL: 0
    # FAIL:  0
    # XPASS: 0
    # ERROR: 0
    ============================================================================
    ```

## [Submitting a patch](#submitting-a-patch)

After you have committed your changes and tested, you are ready to submit your patch!

You should make sure your commits are placed on top of the latest changes from `upstream/master`:

```bash
$ git pull --rebase upstream master
```

To submit your patch, open a pull request from your forked repository. Most often, you'll be merging into `ostree:master` from `<username>:<branch name>`.

If some of your changes are complete and you would like feedback, you may also open a pull request that has WIP (Work In Progess) in the title.

Submitting patches
------------------

A majority of current maintainers prefer the Github pull request
model, and this motivated moving the primary git repository to
<https://github.com/ostreedev/ostree>.

**TO DO**: Is the below comment still valid? I didn't do what was mentioned here. --cheryl

<!-- However, we do not use the "Merge pull request" button, because we do
not like merge commits for one-patch pull requests, among other
reasons.  See [this issue](https://github.com/isaacs/github/issues/2)
for more information.  Instead, we use an instance of
[Homu](https://github.com/servo/homu), currently known as
`cgwalters-bot`.

As a review proceeds, the preferred method is to push `fixup!`
commits via `git commit --fixup`.  Homu knows how to use
`--autosquash` when performing the final merge.  See the
[Git documentation](https://git-scm.com/docs/git-rebase) for more
information.

Alternative methods if you don't like Github (also fully supported):

 1. Send mail to <ostree-list@gnome.org>, with the patch attached
 1. Attach them to <https://bugzilla.gnome.org/>

It is likely however once a patch is ready to apply a maintainer
will push it to a github PR, and merge via Homu. -->

## [Commit message style](#commit-message-style)

Please look at `git log` and match the commit log style, which is very
similar to the
[Linux kernel](https://git.kernel.org/cgit/linux/kernel/git/torvalds/linux.git).

You may use `Signed-off-by`, but we're not requiring it.

**TODO**: Add rules about commit message and link the source, Editing committed message may be unnecessary...

**General Commit Message Guidelines**:  

1. Title
    - Specify the context or category of the changes .e.g `lib` for library changes, `docs` for document changes, `bin/<command-name>` for command changes, etc.
    - Begin the title with the first letter of the first word capitalized.
    - Aim for less than 50 characters, otherwise 72 characters max.
    - Do not end the title with a period.
    - Use an [imperative tone](https://en.wikipedia.org/wiki/Imperative_mood).
2. Body
    - Separate the body with a blank line after the title.
    - Begin a paragraph with the first letter of the first word capitalized.
    - Each paragraph should have be within 72 characters.
    - Content should be about what was changed and why this change was made.
    - Closes: #issue-number. If the commit resolve an issues, otherwise it is not needed.


Commit Message example:

```bash
<context>: Less than 50 Characters for subject title

A paragraph of the body should be within 72 characters.

This paragraph is also less than 72 characters.

Closes: #issue-number
```

**Editting a Committed Message:**

To edit the message from the most recent commit run `git commit --amend`. To change older commits on the branch use `git rebase -i`. For a successful rebase have the branch track `upstream master`. Once the changes have been made and saved, run `git push --force origin <branch-name>`.

## [Returning workflow](#returning-workflow)

When returning to make a new patch, do the following to update your fork with the latest changes to master:

```bash
git fetch upstream
git merge upstream/master
git checkout -b <name-of-patch>
```

----
# Nothing changed in content below, was simply copied and pasted from above and moved down here


Running the test suite
----------------------

OSTree uses both `make check` and supports the
[Installed Tests](https://wiki.gnome.org/GnomeGoals/InstalledTests)
model as well (if `--enable-installed-tests` is provided).

Coding style
------------

Indentation is GNU.  Files should start with the appropriate mode lines.

Use GCC `__attribute__((cleanup))` wherever possible.  If interacting
with a third party library, try defining local cleanup macros.

Use GError and GCancellable where appropriate.

Prefer returning `gboolean` to signal success/failure, and have output
values as parameters.

Prefer linear control flow inside functions (aside from standard
loops).  In other words, avoid "early exits" or use of `goto` besides
`goto out;`.

This is an example of an "early exit":

    static gboolean
    myfunc (...)
    {
        gboolean ret = FALSE;

        /* some code */

        /* some more code */

        if (condition)
          return FALSE;

        /* some more code */

        ret = TRUE;
      out:
        return ret;
    }

If you must shortcut, use:

    if (condition)
      {
        ret = TRUE;
        goto out;
      }

A consequence of this restriction is that you are encouraged to avoid
deep nesting of loops or conditionals.  Create internal static helper
functions, particularly inside loops.  For example, rather than:

    while (condition)
      {
        /* some code */
        if (condition)
          {
             for (i = 0; i < somevalue; i++)
               {
                  if (condition)
                    {
                      /* deeply nested code */
                    }

                    /* more nested code */
               }
          }
      }

Instead do this:

    static gboolean
    helperfunc (..., GError **error)
    {
      if (condition)
       {
         /* deeply nested code */
       }

      /* more nested code */

      return ret;
    }

    while (condition)
      {
        /* some code */
        if (!condition)
          continue;

        for (i = 0; i < somevalue; i++)
          {
            if (!helperfunc (..., i, error))
              goto out;
          }
      }
