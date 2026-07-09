# openwrt-official-builds-fullcone
This script builds nft-fullcone kernel module suitable for OpenWrt official kernel. \
It's kernel vermagic is same as OpenWrt official kernel. \
So this module is compatible and can be installed directly in OpenWrt official image.

The build process references https://hamy.io/post/0015/how-to-compile-openwrt-and-still-use-the-official-repository/ \
The patch is derived from https://github.com/wongsyrone/lede-1

## Supported releases

| Release  | Script                       | OpenWrt patch                   | LuCI patch                        |
|----------|------------------------------|---------------------------------|-----------------------------------|
| 25.12.5  | `openwrt-25.12.5-fullcone.sh` | `openwrt-25.12.5-fullcone.patch` | `luci-25.12-fullcone.patch`       |
| 22.03.2  | `openwrt-22.03.2-fullcone.sh` | `openwrt-22.03.2-fullcone.patch` | `luci-app-firewall-fullcone.patch` |

Usage (kernel 6.12, GCC 14.3 based release):

    ./openwrt-25.12.5-fullcone.sh [target/subtarget]    # defaults to x86/64

## 25.12 notes

- OpenWrt 25.12 replaced opkg with **APK**. Built packages are `.apk`; the kernel
  vermagic is now taken from `packages/kernel-<version>~<vermagic>-r<rel>.apk` in the
  official `sha256sums`. Toolchain/LLVM archives are `.tar.zst`, so the build host
  needs `zstd` (GNU tar `--zstd`).
- The kernel module is built from the maintained upstream
  https://github.com/fullcone-nat-nftables/nft-fullcone (same wongsyrone module,
  same `fullcone` nft expression) via the `fullconenat-nft` package with a kernel
  6.12 `validate()` signature fix. The resulting package is still `kmod-nft-fullcone`.
- The firewall4 / nftables / libnftnl fullcone patches are the renewed versions of the
  original Syrone Wong patches, rebased on the versions OpenWrt 25.12 ships
  (nftables 1.1.6, libnftnl 1.3.1, firewall4 2025-03-17), as maintained by ImmortalWrt.
- The official kernel enables `CONFIG_NF_CONNTRACK_EVENTS` (release builds use
  `CONFIG_ALL_KMODS`, and kmod-nf-conntrack-netlink selects it), so the module's
  conntrack event based mapping cleanup works against the unmodified official kernel
  config — vermagic and struct layouts both match.
- The kmod's Makefile deliberately sets **no `KCONFIG`** (commented out, like the
  22.03 patch did): vermagic is an md5 over the merged `.config.set`, computed
  before oldconfig drops unknown symbols. With `CONFIG_ALL_KMODS` the package is
  auto-selected, so any KCONFIG line it contributed (e.g. the non-upstream
  `CONFIG_NF_CONNTRACK_CHAIN_EVENTS=y`) would change the hash and break the
  vermagic match with the official kernel.
- `PKG_RELEASE` of libnftnl / nftables / firewall4 is bumped by 1 so the patched
  rebuilds install as upgrades over the official packages.

### Configuration change vs the 22.03 build

Fullcone is now switched **globally** (current upstream/ImmortalWrt design) instead of
per zone:

- `defaults.fullcone`  — enable IPv4 full-cone NAT (applies to zones with `masq` enabled)
- `defaults.fullcone6` — enable IPv6 full-cone NAT (applies to zones with `masq6` enabled)

The old per-zone `fullcone4` / `fullcone6` zone options are gone. Behavior is otherwise
identical: the `fullcone` expression is emitted in the zone dstnat/srcnat chains as a
drop-in replacement of masquerade (UDP gets RFC3489 full-cone NAT, other protocols fall
back to masquerade), and fw4 probes the expression at runtime (`nft_try_fullcone`) and
disables fullcone globally if the kernel module is missing, falling back to plain masq.

In LuCI the toggles appear under Network → Firewall → General Settings once the
`nft_fullcone` module is loaded (feature-detected via `/sys/module/nft_fullcone`).

### Installing on an official image

    apk add --allow-untrusted kmod-nft-fullcone-*.apk
    apk add --allow-untrusted libnftnl11-*.apk nftables-json-*.apk firewall4-*.apk
    apk add --allow-untrusted luci-base-*.apk luci-app-firewall-*.apk   # optional, LuCI toggle
    uci set firewall.@defaults[0].fullcone='1' && uci commit firewall && fw4 restart

kmod/target packages land in `bin/targets/<target>/<subtarget>/packages/`,
userspace/LuCI packages in `bin/packages/<arch>/{base,luci}/`.
