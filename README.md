# scalar_builder

Build driver for Scalar Kernel, a generic kernel image (GKI) android12-5.10
tree for arm64: <https://github.com/itelrs4/kernel_common-5.10>

It builds `Image.gz` with the Neutron clang, checks
the exported application binary interface (ABI) of `vmlinux`, packs an
AnyKernel3 zip and reports to Telegram. `build.sh` only sequences the steps,
each one is a function in `lib/`.

## Flow

```text
setup                     for each variant
+-----------------+       +------------------+
| config_load     |       | kernel_prepare   |
| host_check      |       | kernel_configure |
| kernel_fetch    |------>| kernel_compile   |
| toolchain_setup |       | abi_check        |
+-----------------+       | package          |
                          | report_result    |
                          +------------------+

                any step fails
                       |
                       v
        +----------------------------+
        | on_exit: restore the tree, |
        | write failure log, notify  |
        +----------------------------+
```

| Step | What it does |
|---|---|
| `prepare` | checks out `scalar-build-<variant>` at `origin/$KERNEL_BRANCH`, applies the SUSFS patches for that variant, probes the KVM warning flag |
| `configure` | `gki_defconfig`, `LOCALVERSION`, LTO mode, `olddefconfig` |
| `compile` | `make headers`, `make Image.gz` |
| `abi_check` | compares symbol checksums with the ABI, see below |
| `package` | AnyKernel3 zip |

## ABI check

```text
+-----------------------------+      +---------------+
| android/abi_gki_aarch64.xml |      | vmlinux       |
| <elf-symbol name=S crc=0xC> |      | __crc_S = 0xD |
+-----------------------------+      +---------------+
               |                             |
               +--------- join on S ---------+
                              |
                              v
                +---------------------------+
                | S missing, or C differs   |
                | -> out/<variant>/abi.diff |
                | -> the build fails        |
                +---------------------------+
```

With `CONFIG_MODVERSIONS` genksyms hashes the type expansion of every exported
symbol into a cyclic redundancy check (CRC) and `ld` exports it as the
absolute symbol `__crc_<name>`. `modpost` copies that value into the
`__versions` section of each module, and `check_version()` in
`kernel/module.c` compares it with the kernel's `__kcrctab` at load time,
refusing the module with "disagrees about version of symbol". Vendor modules
are never rebuilt, so every value in the XML has to survive. The check cannot
see semantic changes behind an unchanged type.

## Toolchain

`neutron-clang-06092026` (LLVM 24) comes from the Neutron-Toolchains
`clang-build-catalogue` releases as a `.tar.zst`. The tarball is checked
against a pinned SHA-256 and removed on a mismatch. To bump it, change the tag,
URL and hash in `lib/toolchain.sh` and the cache key in both workflows.

## Build details

- Link time optimization (LTO): `full` links all bitcode in a single `ld.lld`
  job, `thin` splits it into parallel backends. `CONFIG_CFI_CLANG` (control
  flow integrity) needs one of them, so there is no option to turn LTO off.
- `DEBUG_INFO` is disabled. DWARF is only read by the ABI tooling and
  dominates link time and memory.
- ccache covers the compile step. The LTO link always runs.
- `BRANCH` and `KMI_GENERATION` from `build.config.common` feed
  `setlocalversion` for the `-android12-<generation>-g<hash>` suffix.
  `LOCALVERSION` is passed empty so no `+` is appended, and
  `CONFIG_LOCALVERSION` carries `-Scalar-<codename>-<variant>`.
- `KBUILD_BUILD_USER`, `_HOST` and `_TIMESTAMP` pin the strings in
  `/proc/version`.
- The KVM Makefile is patched to probe `-Wuninitialized-const-pointer`
  instead of trusting the clang version, and restored on exit.
- Each variant must end up with the expected `CONFIG_KSU` and
  `CONFIG_KSU_SUSFS` (Vanilla 0/0, SUSFS 1/1) after `olddefconfig`, otherwise
  the build stops.

SUSFS is the tree plus the private KernelSU-Next and SUSFS patches from
`$SUSFS_DIR`, applied with `git am --3way` on a throwaway branch. It is
refused when the `CI` environment variable is set.

## Telegram

`TELEGRAM_CHAT` lists the targets, separated by commas or spaces:

| Target | Meaning |
|---|---|
| `123456789` | private chat, the user has to `/start` the bot first |
| `-1001234567890` | group, supergroup or channel by id |
| `@scalar_builds` | public channel |
| `-1001234567890/42` | topic 42 of a forum group |

The bot must be a member of a group and an administrator with "post messages"
in a channel. Ids show up in `getUpdates` after a message was sent to the bot
or the group.

Each target owns one message. It starts as `[BUILDING]`, is edited at every
stage and ends as `[SUCCESS]`, `[FAILED]` or `[CANCELLED]`. The summary and the
changelog of the last ten commits stay in it the whole time. The clone fetches
30 commits so there is history to list, merge commits are skipped.

```text
🔨 <b>Scalar Kernel Bifeng</b> - <code>BUILDING</code>

<blockquote>📅 2026-11-16 14:10 WIB
🌿 android12-5.10-staging @ 4b749c7
🛠 neutron-clang-06092026 - LTO full - 4 CPU
🧪 Vanilla, KSUN + SUSFS
🏷️ Status weekly build</blockquote>

⏳ KSUN + SUSFS: compile, 37m 12s
<code>LTO     vmlinux.o</code>

📋 <b>Changelog</b>
<blockquote expandable>• 4b749c7 BACKPORT: erofs: Use ARM64 v8 ASM ...</blockquote>
```

The title emoji marks the state: 🔨 building, ✅ success, ❌ build error,
🚫 cancelled. Each terminal state replaces the stage block with its own card:

```text
✅ ... SUCCESS
📲 5.10.272-Scalar-Bifeng-SUSFS-android12-9-g4f2a7381f169
🏷️ Status weekly build - ABI OK - ⏱ 37m 12s - 💾 25M
🔑 sha256 5139fea704c34853

❌ ... FAILED
❌ Build error - KSUN + SUSFS (exit 2)
🐞 2 error line(s): error: something broke
📄 Log: build-failed-SUSFS-20261116-1410.txt

🚫 ... CANCELLED
🚫 Build cancelled - KSUN + SUSFS
⏹ Signal: TERM - stage: SUSFS
📄 Partial log: build.log
```

The zip gets the success card as its caption, the failure log is attached to
the error message. `INT`, `TERM` and `HUP` during the build are reported as
`CANCELLED` with the signal and the current stage, so a GitHub Actions
cancellation or the 360-minute timeout no longer leaves the message stuck on
`[BUILDING]` or gets misreported as a failure.

The calls behind it:

```text
   build.sh                               Telegram
   |                                          |
   |--- sendMessage ------------------------->|  once per target, returns id
   |--- editMessageText(id) ----------------->|  at every stage change
   |--- editMessageText(id) ----------------->|  every 60 s: time, last line
   |--- sendDocument ------------------------>|  zip or log, then by file id
   |                                          |
```

The file is uploaded once and the other targets get it by file id. A target
that fails does not stop the build or the other targets. Edits with identical
text are rejected with 400 and ignored. Uploads are limited to 50 MB. Without
`TELEGRAM_TOKEN` or targets every call is skipped.

## Configuration

Settings come from `config.env` (see `config.env.example`) or the
environment. `LTO`, `CODENAME` and `CLEAN` are asked for when unset and stdin
is a terminal.

| Variable | Meaning |
|---|---|
| `CODENAME` | 1-14 of `[A-Za-z0-9._-]`, release string and build host |
| `LTO` | `full` (default) or `thin` |
| `CLEAN` | `y` wipes `out/<variant>` first |
| `JOBS` | `make -j`, default `nproc` |
| `KERNEL_BRANCH` | kernel branch, default `android12-5.10-staging` |
| `KERNEL_REPO`, `KERNEL_DIR` | where to clone from, or an existing tree |
| `ANYKERNEL_REPO` | AnyKernel3 template |
| `SUSFS_DIR` | directory of `*.patch`, builds the SUSFS variant too |
| `TELEGRAM_TOKEN`, `TELEGRAM_CHAT` | bot token and targets |

Output:

| Path | Content |
|---|---|
| `release/Scalar-<codename>-<variant>-<version>-<date>.zip` | flashable zip |
| `release/Scalar-<codename>-<variant>-<version>-<date>-Image.gz` | the kernel image alone |
| `release/build-failed-<stage>-<date>.txt` | stage, exit status, commit, matching error lines, `abi.diff`, full log |
| `out/<variant>/` | objects, `abi.expected`, `abi.actual`, `abi.diff` |
| `build.log` | output of the last run |

Host: bash 4.4+, git, curl, tar, make, bc, bison, flex, perl, python3, zip,
lz4, cpio, sha256sum, OpenSSL and libelf headers, optionally ccache.

## Local build

```sh
cp config.env.example config.env
./build.sh
```

## GitHub Actions

Manual run (`workflow_dispatch`) with `codename`, `lto`, `branch`
(`android12-5.10-staging` or `android12-5.10`) and `other_branch`, which
overrides `branch`. A first step checks the branch with `git ls-remote` and
fails at once if it is missing. With the `SUSFS_DEPLOY_KEY` secret, a read
only deploy key of the private `lifeats666ln/scalar-patch`, its patches are
checked out and SUSFS is built too; its zip goes to Telegram only, never to
the artifacts. Runs on `ubuntu-24.04`. The
toolchain is cached, ccache is keyed by branch and LTO mode with a fallback
to the staging cache. `TELEGRAM_TOKEN` and `TELEGRAM_CHAT` are repository
secrets. Artifacts are named after the branch and kept 14 days, failure logs
7. `lto` defaults to `thin`: a full LTO link of SUSFS starves the 16 GB runner
even with 32 GB of swap and the runner loses contact with GitHub. Build full
LTO releases on a larger machine.

After a successful build `release.sh` publishes `release/` as a GitHub release
tagged `<codename>-<release_type>-<date>-r<run>`, a prerelease unless the branch is
`android12-5.10`. The notes open with a `weekly build` / `stable build` status
heading and a branch, toolchain and LTO line, list each zip with its SHA256,
then the `git shortlog` since the previous release of the same branch. That
previous kernel head is kept in a hidden `<!-- head <branch> <type> <sha> -->`
line.
