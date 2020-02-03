#!/bin/bash
echored () {
	echo "${TEXTRED}$1${TEXTRESET}"
}
echogreen () {
	echo "${TEXTGREEN}$1${TEXTRESET}"
}
usage () {
  echo " "
  echored "USAGE:"
  echogreen "BIN=      (Default: all) (Valid options are: bash, bc, coreutils, cpio, diffutils, ed, findutils, gawk, grep, gzip, ncurses, patch, sed, tar)"
  echogreen "ARCH=     (Default: all) (Valid Arch values: all, arm, arm64, aarch64, x86, i686, x64, x86_64)"
  echogreen "STATIC=   (Default: false) (Valid options are: true, false)"
  echogreen "API=      (Default: 21) (Valid options are: 21, 22, 23, 24, 26, 27, 28, 29)"
  echogreen "SEP=      (Default: false) (Valid options are: true, false) - Determines if coreutils builds as a single busybox-like binary or as separate binaries"
  echogreen "           Note that you can put as many of these as you want together as long as they're comma separated"
  echogreen "           Ex: BIN=cpio,gzip,tar"
  echogreen "           Also note that coreutils includes advanced cp/mv (adds progress bar functionality with -g flag"
  echo " "
  exit 1
}
patch_file() {
  echogreen "Applying patch"
  local DEST=$(basename $1)
  cp -f $1 $DEST
  patch -p0 -i $DEST
  [ $? -ne 0 ] && { echored "Patching failed! Did you verify line numbers? See README for more info"; exit 1; }
}
bash_patches() {
  echogreen "Applying patches"
  local PVER=$(echo $VER | sed 's/\.//')
  for i in {001..050}; do
    wget http://mirrors.kernel.org/gnu/bash/bash-$VER-patches/bash$PVER-$i 2>/dev/null
    if [ -f "bash$PVER-$i" ]; then
      patch -p0 -i bash$PVER-$i
      rm -f bash$PVER-$i
    else
      break
    fi
  done
  for i in $DIR/bash_patches/*; do
    local PFILE=$(basename $i)
    cp -f $i $PFILE
    sed -i "s/4.4/$VER/g" $PFILE
    patch -p0 -i $PFILE
    [ $? -ne 0 ] && { echored "Patching failed!"; return 1; }
    rm -f $PFILE
  done
}
build_zlib() {
  export ZPREFIX="$(echo $PREFIX | sed "s|$LBIN|zlib|")"
  [ -d $ZPREFIX ] && return 0
	cd $DIR
	echogreen "Building ZLib..."
	[ -f "zlib-$ZVER.tar.gz" ] || wget http://zlib.net/zlib-$ZVER.tar.gz
	[ -d zlib-$ZVER ] || tar -xf zlib-$ZVER.tar.gz
	cd zlib-$ZVER
	./configure --prefix=$ZPREFIX
	[ $? -eq 0 ] || { echored "Configure failed!"; exit 1; }
	make -j$JOBS
	[ $? -eq 0 ] || { echored "Build failed!"; exit 1; }
	make install
  make clean
	cd $DIR/$LBIN-$VER
}
build_bzip2() {
  export BPREFIX="$(echo $PREFIX | sed "s|$LBIN|bzip2|")"
  [ -d $BPREFIX ] && return 0
	cd $DIR
	echogreen "Building BZip2..."
	[ -f "bzip2-latest.tar.gz" ] || wget https://www.sourceware.org/pub/bzip2/bzip2-latest.tar.gz
	[[ -d "bzip2-"[0-9]* ]] || tar -xf bzip2-latest.tar.gz
	cd bzip2-[0-9]*
	sed -i -e '/# To assist in cross-compiling/,/LDFLAGS=/d' -e "s/CFLAGS=/CFLAGS=$CFLAGS /" -e 's/bzip2recover test/bzip2recover/' Makefile
	export LDFLAGS
	make -j$JOBS
	export -n LDFLAGS
	[ $? -eq 0 ] || { echored "Bzip2 build failed!"; exit 1; }
	make install -j$JOBS PREFIX=$BPREFIX
  make clean
	$STRIP $BPREFIX/bin/bunzip2 $BPREFIX/bin/bzcat $BPREFIX/bin/bzip2 $BPREFIX/bin/bzip2recover
	cd $DIR/$LBIN-$VER
}
build_pcre() {
	build_zlib
	build_bzip2
  export PPREFIX="$(echo $PREFIX | sed "s|$LBIN|pcre|")"
  [ -d $PPREFIX ] && return 0
	cd $DIR
	rm -rf pcre-$PVER 2>/dev/null
	echogreen "Building PCRE..."
	[ -f "pcre-$PVER.tar.bz2" ] || wget https://ftp.pcre.org/pub/pcre/pcre-$PVER.tar.bz2
	[ -d pcre-$PVER ] || tar -xf pcre-$PVER.tar.bz2
	cd pcre-$PVER
	$STATIC && local FLAGS="$FLAGS--disable-shared "
	./configure $FLAGS--prefix= --enable-unicode-properties --enable-jit --enable-pcre16 --enable-pcre32 --enable-pcregrep-libz --enable-pcregrep-libbz2 --host=$target_host CFLAGS="$CFLAGS -I$ZPREFIX/include -I$BPREFIX/include" LDFLAGS="$LDFLAGS -L$ZPREFIX/lib -L$BPREFIX/lib"
	[ $? -eq 0 ] || { echored "Configure failed!"; exit 1; }
	make -j$JOBS
	[ $? -eq 0 ] || { echored "Build failed!"; exit 1; }
	make install -j$JOBS DESTDIR=$PPREFIX
  make clean
	cd $DIR/$LBIN-$VER
}

TEXTRESET=$(tput sgr0)
TEXTGREEN=$(tput setaf 2)
TEXTRED=$(tput setaf 1)
DIR=$PWD
NDKVER=r20b
STATIC=false
SEP=false
export OPATH=$PATH
OIFS=$IFS; IFS=\|;
while true; do
  case "$1" in
    -h|--help) usage;;
    "") shift; break;;
    API=*|STATIC=*|BIN=*|ARCH=*|SEP=*) eval $(echo "$1" | sed -e 's/=/="/' -e 's/$/"/' -e 's/,/ /g'); shift;;
    *) echored "Invalid option: $1!"; usage;;
  esac
done
IFS=$OIFS
[ -z "$ARCH" -o "$ARCH" == "all" ] && ARCH="arm arm64 x86 x64"
[ -z "$BIN" -o "$BIN" == "all" ] && BIN="bash bc coreutils cpio diffutils ed findutils gawk grep gzip ncurses patch sed tar"

case $API in
  21|22|23|24|26|27|28|29) ;;
  *) API=21;;
esac

if [ -f /proc/cpuinfo ]; then
  JOBS=$(grep flags /proc/cpuinfo | wc -l)
elif [ ! -z $(which sysctl) ]; then
  JOBS=$(sysctl -n hw.ncpu)
else
  JOBS=2
fi

# Set up Android NDK
echogreen "Fetching Android NDK $NDKVER"
[ -f "android-ndk-$NDKVER-linux-x86_64.zip" ] || wget https://dl.google.com/android/repository/android-ndk-$NDKVER-linux-x86_64.zip
[ -d "android-ndk-$NDKVER" ] || unzip -qo android-ndk-$NDKVER-linux-x86_64.zip
export ANDROID_NDK_HOME=$DIR/android-ndk-$NDKVER
export ANDROID_TOOLCHAIN=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin

for LBIN in $BIN; do
  NDK=true
  # Versioning and overrides
  LAPI=$API
  PVER=8.43
  ZVER=1.2.11
  LVER=1.16
  GVER=0.20.1
  case $LBIN in
    "bash") EXT=gz; VER=5.0; $STATIC || NDK=false;;
    "bc") EXT=gz; VER=1.07.1;;
    "coreutils") EXT=xz; VER=8.31; [ $LAPI -lt 23 ] && LAPI=23;;
    "cpio") EXT=gz; VER=2.12;;
    "diffutils") EXT=xz; VER=3.7;;
    "ed") EXT=lz; VER=1.15;;
    "findutils") EXT=xz; VER=4.7.0; [ $LAPI -lt 23 ] && LAPI=23;;
    "gawk") EXT=xz; VER=5.0.1; $STATIC || NDK=false;;
    "grep") EXT=xz; VER=3.3; [ $LAPI -lt 23 ] && LAPI=23;;
    "gzip") EXT=xz; VER=1.10;;
    "ncurses") EXT=gz; VER=6.1;;
    "patch") EXT=xz; VER=2.7.6;;
    "sed") EXT=xz; VER=4.7; [ $LAPI -lt 23 ] && LAPI=23;;
    "tar") EXT=xz; VER=1.32; ! $STATIC && [ $LAPI -lt 28 ] && LAPI=28;;
    *) echored "Invalid binary specified!"; usage;;
  esac

  [[ $(wget -S --spider http://mirrors.kernel.org/gnu/$LBIN/$LBIN-$VER.tar.$EXT 2>&1 | grep 'HTTP/1.1 200 OK') ]] || { echored "Invalid $LBIN VER! Check this: http://mirrors.kernel.org/gnu/$LBIN for valid versions!"; exit 1; }

  # Setup
  echogreen "Fetching $LBIN $VER"
  rm -rf $LBIN-$VER
  [ -f "$LBIN-$VER.tar.$EXT" ] || wget http://mirrors.kernel.org/gnu/$LBIN/$LBIN-$VER.tar.$EXT
  tar -xf $LBIN-$VER.tar.$EXT

  for LARCH in $ARCH; do
    # Setup toolchain
    case $LARCH in
      arm64|aarch64) LINKER=linker64; LARCH=aarch64; $NDK && target_host=aarch64-linux-android || { target_host=aarch64-linux-gnu; LINARO=true; };;
      arm) LINKER=linker; LARCH=arm; $NDK && target_host=arm-linux-androideabi || { target_host=arm-linux-gnueabi; LINARO=true; };;
      x64|x86_64) LINKER=linker64; LARCH=x86_64; LINARO=false; $NDK && target_host=x86_64-linux-android || target_host=x86_64-linux-gnu;;
      x86|i686) LINKER=linker; LARCH=i686; LINARO=false; $NDK && target_host=i686-linux-android || target_host=i686-linux-gnu;;
      *) echored "Invalid ARCH entered!"; usage;;
    esac
    export PATH=$OPATH
    unset AR AS LD RANLIB STRIP CC CXX GCC GXX
    # Bash doesn't compile as static with ndk aarch64 for reasons unknown
    [ "$LBIN" == "bash" -a "$LARCH" == "aarch64" ] && { NDK=false; LINARO=true; target_host=aarch64-linux-gnu; }
    if $NDK || $LINARO; then
      export AR=$target_host-ar
      export AS=$target_host-as
      export LD=$target_host-ld
      export RANLIB=$target_host-ranlib
      export STRIP=$target_host-strip
      if $NDK; then
        export CC=$target_host-clang
        export GCC=$target_host-gcc
        export CXX=$target_host-clang++
        export GXX=$target_host-g++
        export PATH=$ANDROID_TOOLCHAIN:$PATH
        [ "$LARCH" == "arm" ] && target_host=armv7a-linux-androideabi
        # Create sometimes needed symlinks
        ln -sf $ANDROID_TOOLCHAIN/$target_host$LAPI-clang $ANDROID_TOOLCHAIN/$CC
        ln -sf $ANDROID_TOOLCHAIN/$target_host$LAPI-clang++ $ANDROID_TOOLCHAIN/$CXX
        ln -sf $ANDROID_TOOLCHAIN/$target_host$LAPI-clang $ANDROID_TOOLCHAIN/$GCC
        ln -sf $ANDROID_TOOLCHAIN/$target_host$LAPI-clang++ $ANDROID_TOOLCHAIN/$GXX
        [ "$LARCH" == "arm" ] && target_host=arm-linux-androideabi
      elif $LINARO; then
				[ -f gcc-linaro-7.5.0-2019.12-x86_64_$target_host.tar.xz ] || { echogreen "Fetching Linaro gcc"; wget https://releases.linaro.org/components/toolchain/binaries/latest-7/$target_host/gcc-linaro-7.5.0-2019.12-x86_64_$target_host.tar.xz; }
	      [ -d gcc-linaro-7.5.0-2019.12-x86_64_$target_host ] || { echogreen "Setting up Linaro gcc"; tar -xf gcc-linaro-7.5.0-2019.12-x86_64_$target_host.tar.xz; }
	      export PATH=$PWD/gcc-linaro-7.5.0-2019.12-x86_64_$target_host/bin:$PATH
        export CC=$target_host-gcc
        export CXX=$target_host-g++
      fi
    fi

    rm -rf $LBIN-$VER 2>/dev/null
    tar -xf $LBIN-$VER.tar.$EXT
    unset FLAGS
    cd $DIR/$LBIN-$VER

    if $STATIC; then
      CFLAGS='-static -O2'
      LDFLAGS='-static'
      $NDK && [ -f $DIR/ndk_static_patches/$LBIN.patch ] && patch_file $DIR/ndk_static_patches/$LBIN.patch
      export PREFIX=$DIR/build-static/$LBIN/$LARCH
    else
      CFLAGS='-O2 -fPIE -fPIC'
      LDFLAGS='-s -pie'
      $NDK || LDFLAGS="$LDFLAGS -Wl,-dynamic-linker,/system/bin/$LINKER"
      export PREFIX=$DIR/build-dynamic/$LBIN/$LARCH
    fi
    if ! $NDK; then
      case $LARCH in
        "arm") CFLAGS="$CFLAGS -mfloat-abi=softfp -mthumb"; LDFLAGS="$LDFLAGS -march=armv7-a -Wl,--fix-cortex-a8";;
        "i686") CFLAGS="$CFLAGS -march=i686 -mtune=intel -mssse3 -mfpmath=sse -m32";;
        "x86_64") CFLAGS="$CFLAGS -march=x86-64 -msse4.2 -mpopcnt -m64 -mtune=intel";;
      esac
    elif [ "$LARCH" == "i686" ]; then
      FLAGS="TIME_T_32_BIT_OK=yes "
    fi

    # Fixes:
    # 1) mktime_internal build error for non-ndk arm/64 cross-compile
    # 2) %n issue due to these binaries using old gnulib (This was in Jan 2019: http://git.savannah.gnu.org/gitweb/?p=gnulib.git;a=commit;h=6c0f109fb98501fc8d65ea2c83501b45a80b00ab)
    # 3) minus_zero duplication error in NDK
    # 4) Bionic error fix in NDK
    # 5) Sort and timeout binaries have what appears to be seccomp problems and so don't work when compiled without ndk
    echogreen "Configuring for $LARCH"
    case $LBIN in
      "bash")
        $STATIC && FLAGS="$FLAGS--enable-static-link "
        bash_patches || exit 1
        ./configure $FLAGS--prefix=$PREFIX --disable-nls --without-bash-malloc bash_cv_dev_fd=whacky bash_cv_getcwd_malloc=yes --enable-largefile --enable-alias --enable-history --enable-readline --enable-multibyte --enable-job-control --enable-array-variables --host=$target_host --target=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        ;;
      "bc")
        ./configure $FLAGS--prefix=$PREFIX --host=$target_host --target=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        sed -i -e '\|./fbc -c|d' -e 's|$(srcdir)/fix-libmath_h|cp -f ../../bc_libmath.h $(srcdir)/libmath.h|' bc/Makefile
        ;;
      "coreutils")
        patch_file $DIR/coreutils.patch
        if ! $SEP; then
          FLAGS="$FLAGS--enable-single-binary=symlinks "
          $NDK || FLAGS="$FLAGS--enable-single-binary-exceptions=sort,timeout " #5
        fi
        if $NDK; then
          sed -i "s/USE_FORTIFY_LEVEL/BIONIC_FORTIFY/g" lib/cdefs.h #4
          sed -i "s/USE_FORTIFY_LEVEL/BIONIC_FORTIFY/g" lib/stdio.in.h #4
          sed -i -e '/if (!num && negative)/d' -e "/return minus_zero/d" -e "/DOUBLE minus_zero = -0.0/d" lib/strtod.c #3
          ./configure $FLAGS--prefix=$PREFIX --disable-nls --enable-no-install-program=stdbuf --host=$target_host --target=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        else
          sed -i -e '/WANT_MKTIME_INTERNAL=0/i\WANT_MKTIME_INTERNAL=1\n$as_echo "#define NEED_MKTIME_INTERNAL 1" >>confdefs.h' -e '/^ *WANT_MKTIME_INTERNAL=0/,/^ *fi/d' configure #1
          ./configure $FLAGS--prefix=$PREFIX --disable-nls --enable-no-install-program=stdbuf --host=$target_host --target=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        fi
        [ ! "$(grep "#define HAVE_MKFIFO 1" lib/config.h)" ] && echo "#define HAVE_MKFIFO 1" >> lib/config.h
        ;;
      "cpio")
        sed -i 's/!defined __UCLIBC__)/!defined __UCLIBC__) || defined __ANDROID__/' gnu/vasnprintf.c #2
        ./configure $FLAGS--prefix=$PREFIX --disable-nls --host=$target_host --target=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        ;;
      "diffutils")
        $NDK || sed -i -e '/WANT_MKTIME_INTERNAL=0/i\WANT_MKTIME_INTERNAL=1\n$as_echo "#define NEED_MKTIME_INTERNAL 1" >>confdefs.h' -e '/^ *WANT_MKTIME_INTERNAL=0/,/^ *fi/d' configure #1
        ./configure $FLAGS--prefix=$PREFIX --disable-nls --host=$target_host --target=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        ;;
      "ed")
        ./configure $FLAGS--prefix=$PREFIX CC=$GCC CXX=$GXX CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        ;;
      "findutils")
        $NDK || sed -i -e '/WANT_MKTIME_INTERNAL=0/i\WANT_MKTIME_INTERNAL=1\n$as_echo "#define NEED_MKTIME_INTERNAL 1" >>confdefs.h' -e '/^ *WANT_MKTIME_INTERNAL=0/,/^ *fi/d' configure #1
        ./configure $FLAGS--disable-nls --prefix=/system --sbindir=/system/bin --libexecdir=/system/bin --datarootdir=/system/usr/share --host=$target_host --target=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        $STATIC || sed -i -e "/#ifndef HAVE_ENDGRENT/,/#endif/d" -e "/#ifndef HAVE_ENDPWENT/,/#endif/d" -e "/endpwent/d" -e "/endgrent/d" find/parser.c
        ;;
      "gawk")
        ./configure $FLAGS--prefix=$PREFIX --disable-nls --host=$target_host --target=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        ;;
      "grep")
        build_pcre
        ./configure $FLAGS--prefix=$PREFIX --enable-perl-regexp --disable-nls --host=$target_host --target=$target_host CFLAGS="$CFLAGS -I$PPREFIX/include" LDFLAGS="$LDFLAGS -L$PPREFIX/lib" || { echored "Configure failed!"; exit 1; }
        ;;
      "gzip")
        sed -i 's/!defined __UCLIBC__)/!defined __UCLIBC__) || defined __ANDROID__/' lib/vasnprintf.c #2
        ./configure $FLAGS--prefix=$PREFIX --host=$target_host --target=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        ;;
      "ncurses")
        ./configure $FLAGS--prefix=$PREFIX --disable-nls --disable-stripping --host=$target_host --target=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        ;;
      "patch")
        $NDK || sed -i -e '/WANT_MKTIME_INTERNAL=0/i\WANT_MKTIME_INTERNAL=1\n$as_echo "#define NEED_MKTIME_INTERNAL 1" >>confdefs.h' -e '/^ *WANT_MKTIME_INTERNAL=0/,/^ *fi/d' configure #1
        ./configure $FLAGS--prefix=$PREFIX --host=$target_host --target=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        ;;
			"sed")
        $NDK && { sed -i "s/USE_FORTIFY_LEVEL/BIONIC_FORTIFY/g" lib/cdefs.h; sed -i "s/USE_FORTIFY_LEVEL/BIONIC_FORTIFY/g" lib/stdio.in.h; } #4
        ./configure $FLAGS--prefix=$PREFIX --disable-nls --host=$target_host --target=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        ;;
			"tar")
        sed -i 's/!defined __UCLIBC__)/!defined __UCLIBC__) || defined __ANDROID__/' gnu/vasnprintf.c #2
        if $NDK; then
          sed -i "s/USE_FORTIFY_LEVEL/BIONIC_FORTIFY/g" gnu/cdefs.h #4
          sed -i "s/USE_FORTIFY_LEVEL/BIONIC_FORTIFY/g" gnu/stdio.in.h #4
        else
          sed -i -e '/WANT_MKTIME_INTERNAL=0/i\WANT_MKTIME_INTERNAL=1\n$as_echo "#define NEED_MKTIME_INTERNAL 1" >>confdefs.h' -e '/^ *WANT_MKTIME_INTERNAL=0/,/^ *fi/d' configure #1
        fi
        ./configure $FLAGS--prefix=$PREFIX --disable-nls --host=$target_host --target=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || { echored "Configure failed!"; exit 1; }
        ;;
    esac

    make -j$JOBS
    [ $? -eq 0 ] || { echored "Build failed!"; exit 1; }

    if [ "$LBIN" == "findutils" ]; then
      sed -i -e "s|/usr/bin|/system/bin|g" -e "s|SHELL=\".*\"|SHELL=\"/system/bin/sh\"|" locate/updatedb
      make install DESTDIR=$PREFIX
      mv -f $PREFIX/system/* $PREFIX
      rm -rf $PREFIX/sdcard $PREFIX/system
    else
      make install
    fi
    echogreen "$LBIN built sucessfully and can be found at: $PREFIX"
    cd $DIR
  done
done