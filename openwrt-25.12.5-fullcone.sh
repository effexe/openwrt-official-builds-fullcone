#!/bin/sh -e

OPENWRT_REPO="https://github.com/openwrt/openwrt.git"
OPENWRT_DL="https://downloads.cdn.openwrt.org"

OPENWRT_VER=25.12.5
FULL_TARGET=${1:-x86/64}

TARGET="$(echo "$FULL_TARGET" | cut -s -d/ -f1)"
SUBTARGET="$(echo "$FULL_TARGET" | cut -s -d/ -f2)"

[ -z "$TARGET" -o -z "$SUBTARGET" ] && {
  echo Invalid target \""$FULL_TARGET"\"
  exit 1
}

git clone --depth=1 -b v${OPENWRT_VER} ${OPENWRT_REPO} openwrt-${OPENWRT_VER}
cd openwrt-${OPENWRT_VER}

TARGET_URL="${OPENWRT_DL}/releases/${OPENWRT_VER}/targets/${TARGET}/${SUBTARGET}"
SHA256SUMS="$(wget -O - "${TARGET_URL}/sha256sums")"

TOOLCHAIN_STRING="$(echo "$SHA256SUMS" | grep ".*openwrt-toolchain.*tar.zst")"
TOOLCHAIN_FILE=$(echo "$TOOLCHAIN_STRING" | sed -n -e 's/.*\(openwrt-toolchain.*\).tar.zst/\1/p')

LLVM_STRING="$(echo "$SHA256SUMS" | grep ".*llvm-bpf.*tar.zst")"
LLVM_FILE=$(echo "$LLVM_STRING" | sed -n -e 's/.*\(llvm-bpf.*.tar.zst\)/\1/p')

# since 25.12 the kernel is shipped as APK: packages/kernel-<version>~<vermagic>-r<rel>.apk
KERNEL_STRING="$(echo "$SHA256SUMS" | grep ".*packages/kernel-.*\.apk")"
KERNEL_VERMAGIC=$(echo "$KERNEL_STRING" | sed -n -e 's/.*kernel-[^~]*~\([0-9a-f]*\)-r[0-9]*\.apk/\1/p')

echo Official kernel vermagic $KERNEL_VERMAGIC

wget -O - ${TARGET_URL}/${TOOLCHAIN_FILE}.tar.zst | tar --zstd -xf -
# extracting the prebuilt llvm-bpf toolchain at the buildroot top makes
# HAS_PREBUILT_LLVM_TOOLCHAIN=y so BPF_TOOLCHAIN defaults to PREBUILT
wget -O - ${TARGET_URL}/${LLVM_FILE} | tar --zstd -xf -

git apply ../openwrt-${OPENWRT_VER}-fullcone.patch

./scripts/feeds update -a

git -C feeds/luci apply "$(realpath -- ../luci-25.12-fullcone.patch)"

./scripts/feeds install -a

wget -O .config ${TARGET_URL}/config.buildinfo

./scripts/ext-toolchain.sh \
  --toolchain ${TOOLCHAIN_FILE}/toolchain-* \
  --overwrite-config \
  --config ${TARGET}/${SUBTARGET}

make toolchain/install -j$(nproc)
make target/compile -j$(nproc)

CURR_VERMAGIC=$(cat build_dir/target-*/linux-*/linux-*/.vermagic)
[ "$CURR_VERMAGIC" = "$KERNEL_VERMAGIC" ] || {
  echo Current kernel vermagic not equal with OpenWrt official kernel
  exit 1
}

make package/linux/compile -j$(nproc)

make package/fullconenat-nft/compile -j$(nproc)
make package/libnftnl/compile -j$(nproc)
make package/nftables/compile -j$(nproc)
make package/firewall4/compile -j$(nproc)
make package/luci-base/compile -j$(nproc)
make package/luci-app-firewall/compile -j$(nproc)
