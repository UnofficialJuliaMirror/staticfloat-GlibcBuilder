using BinaryBuilder

# We have to build multiple versions of glibc because we want to use v2.12 for
# x86_64 and i686, but powerpc64le doesn't work on anything older than v2.25.
glibc_version = v"2.25"
glibc_version_sources = Dict(
    v"2.12.2" => [
        "https://mirrors.kernel.org/gnu/glibc/glibc-2.12.2.tar.xz" =>
        "0eb4fdf7301a59d3822194f20a2782858955291dd93be264b8b8d4d56f87203f",
    ],
    v"2.17" => [
        "https://mirrors.kernel.org/gnu/glibc/glibc-2.17.tar.xz" =>
        "6914e337401e0e0ade23694e1b2c52a5f09e4eda3270c67e7c3ba93a89b5b23e",
    ],
    v"2.25" => [
        "https://mirrors.kernel.org/gnu/glibc/glibc-2.25.tar.xz" =>
        "067bd9bb3390e79aa45911537d13c3721f1d9d3769931a30c2681bfee66f23a0",
    ],
)

# sources to build, such as glibc, linux kernel headers, our patches, etc....
sources = [
    glibc_version_sources[glibc_version]...,
	"https://www.kernel.org/pub/linux/kernel/v4.x/linux-4.12.tar.xz" =>
	"a45c3becd4d08ce411c14628a949d08e2433d8cdeca92036c7013980e93858ab",
    "patches",
]

# Bash recipe for building across all platforms
script = raw"""
## Function to take in a target such as `aarch64-linux-gnu`` and spit out a
## linux kernel arch like "arm64".
target_to_linux_arch()
{
    case "$1" in
        arm*)
            echo "arm"
            ;;
        aarch64*)
            echo "arm64"
            ;;
        powerpc*)
            echo "powerpc"
            ;;
        i686*)
            echo "x86"
            ;;
        x86*)
            echo "x86"
            ;;
    esac
}

## sysroot is where most of this stuff gets plopped
sysroot=${prefix}/${target}/sys-root

# First, install kernel headers
cd $WORKSPACE/srcdir/linux-*/
KERNEL_FLAGS="ARCH=\"$(target_to_linux_arch ${target})\" CROSS_COMPILE=\"/opt/${target}/bin/${target}-\" HOSTCC=${CC_FOR_BUILD}"

make ${KERNEL_FLAGS} mrproper
make ${KERNEL_FLAGS} headers_check
make ${KERNEL_FLAGS} INSTALL_HDR_PATH=${sysroot}/usr V=0 headers_install


# Next, install glibc
cd $WORKSPACE/srcdir/glibc-*/
# patch glibc to keep around libgcc_s_resume on arm
# ref: https://sourceware.org/ml/libc-alpha/2014-05/msg00573.html
patch -p1 < $WORKSPACE/srcdir/patches/glibc_arm_gcc_fix.patch || true

# patch glibc's stupid gcc version check (we don't require this one, as if
# it doesn't apply cleanly, it's probably fine)
patch -p0 < $WORKSPACE/srcdir/patches/glibc_gcc_version.patch || true

# patch older glibc's 32-bit assembly to withstand __i686 definition of
# newer GCC's.  ref: http://comments.gmane.org/gmane.comp.lib.glibc.user/758
patch -p1 < $WORKSPACE/srcdir/patches/glibc_i686_asm.patch || true

# Patch glibc's sunrpc cross generator to work with musl
# See https://sourceware.org/bugzilla/show_bug.cgi?id=21604
patch -p0 < $WORKSPACE/srcdir/patches/glibc-sunrpc.patch || true

# patch for building old glibc on newer binutils
# These patches don't apply on those versions of glibc where they
# are not needed, but that's ok.
patch -p0 < $WORKSPACE/srcdir/patches/glibc_nocommon.patch || true
patch -p0 < $WORKSPACE/srcdir/patches/glibc_regexp_nocommon.patch || true

mkdir -p $WORKSPACE/srcdir/glibc_build
cd $WORKSPACE/srcdir/glibc_build
$WORKSPACE/srcdir/glibc-*/configure --prefix=${prefix} \
	--host=${target} \
	--with-headers="${sysroot}/usr/include" \
	--disable-multilib \
	--disable-werror \
	libc_cv_forced_unwind=yes \
	libc_cv_c_cleanup=yes

make -j${nproc}
make install
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = [
    Linux(:i686, :glibc),
    Linux(:x86_64, :glibc),
]

# The earliest ARM version we support is v2.17
if glibc_version >= v"2.17"
	push!(platforms, Linux(:aarch64, :glibc))
	push!(platforms, Linux(:armv7l, :glibc))
end

# The earlest powerpc64le version we support is v2.25
if glibc_version >= v"2.25"
    push!(platforms, Linux(:powerpc64le, :glibc))
end


# The products that we will ensure are always built
products(prefix) = [
    LibraryProduct(prefix, "libc", :glibc),
]

# Dependencies that must be installed before this package can be built
dependencies = [
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, "Glibc", sources, script, platforms, products, dependencies)