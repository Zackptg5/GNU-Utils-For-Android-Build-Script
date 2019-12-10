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
  echogreen "NDK=      (Default: false) (Valid options are: true, false)"
  echogreen "BIN=      (Default: all) (Valid options are: bash, bc, coreutils, cpio, diffutils, ed, findutils, gawk, grep, gzip, ncurses, patch, sed, tar)"
  echogreen "ARCH=     (Default: all) (Valid Arch values: all, arm, arm64, aarch64, x86, i686, x64, x86_64)"
  echogreen "STATIC=   (Default: true) (Valid options are: true, false)"
  echogreen "API=   (Default: 21) (Valid options are: 21, 22, 23, 24, 26, 27, 28, 29)"
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
	cd $DIR
	rm -rf zlib-$ZVER 2>/dev/null
	echogreen "Building ZLib..."
	[ -f "zlib-$ZVER.tar.gz" ] || wget http://zlib.net/zlib-$ZVER.tar.gz
	tar -xf zlib-$ZVER.tar.gz
	cd zlib-$ZVER
	./configure --static --prefix=$PREFIX
	[ $? -eq 0 ] || { echored "Configure failed!"; exit 1; }
	make -j$JOBS
	[ $? -eq 0 ] || { echored "Build failed!"; exit 1; }
	make install -j$JOBS
	cd $DIR/$LBIN-$VER
}
build_bzip2() {
	cd $DIR
	rm -rf bzip2-[0-9]* 2>/dev/null
	echogreen "Building BZip2..."
	[ -f "bzip2-latest.tar.gz" ] || wget https://www.sourceware.org/pub/bzip2/bzip2-latest.tar.gz
	tar -xf bzip2-latest.tar.gz
	cd bzip2-[0-9]*
	sed -i -e '/# To assist in cross-compiling/,/LDFLAGS=/d' -e "s/CFLAGS=/CFLAGS=$CFLAGS /" -e 's/bzip2recover test/bzip2recover/' Makefile
	export LDFLAGS
	make -j$JOBS
	export -n LDFLAGS
	[ $? -eq 0 ] || { echored "Bzip2 build failed!"; exit 1; }
	make install -j$JOBS PREFIX=$DIR/$LBIN-$VER/extras
	cd $DIR/$LBIN-$VER
	$STRIP extras/bin/bunzip2 extras/bin/bzcat extras/bin/bzip2 extras/bin/bzip2recover
}
build_pcre() {
	build_zlib
	build_bzip2
	[ "$1" == -s ] && local SEP=true || local SEP=false
	cd $DIR
	rm -rf pcre-$PVER 2>/dev/null
	echogreen "Building PCRE..."
	[ -f "pcre-$PVER.tar.bz2" ] || wget https://ftp.pcre.org/pub/pcre/pcre-$PVER.tar.bz2
	tar -xf pcre-$PVER.tar.bz2
	cd pcre-$PVER
	# Binary compiles as dynamic regardless of flags for some reason, but that doesn't matter for grep compile - just need include and libs
	./configure $FLAGS--prefix= --enable-unicode-properties --enable-jit --enable-pcre16 --enable-pcre32 --enable-pcregrep-libz --enable-pcregrep-libbz2 --host=$target_host CFLAGS="$CFLAGS -I$DIR/$LBIN-$VER/extras/include" LDFLAGS="$LDFLAGS -L$DIR/$LBIN-$VER/extras/lib"
	[ $? -eq 0 ] || { echored "Configure failed!"; exit 1; }
	make -j$JOBS
	[ $? -eq 0 ] || { echored "Build failed!"; exit 1; }
	if $SEP; then
		make install -j$JOBS DESTDIR=$DIR/$LBIN-$VER/pcre
	else
		make install -j$JOBS DESTDIR=$DIR/$LBIN-$VER/extras
	fi
	cd $DIR/$LBIN-$VER
}

TEXTRESET=$(tput sgr0)
TEXTGREEN=$(tput setaf 2)
TEXTRED=$(tput setaf 1)
DIR=`pwd`
LINARO=false
STATIC=true
NDKVER=r20b
MAXAPI=29
export OPATH=$PATH
OIFS=$IFS; IFS=\|;
while true; do
  case "$1" in
    -h|--help) usage;;
    "") shift; break;;
    API=*|STATIC=*|NDK=*|BIN=*|ARCH=*) eval $(echo "$1" | sed -e 's/=/="/' -e 's/$/"/' -e 's/,/ /g'); shift;;
    *) echored "Invalid option: $1!"; usage;;
  esac
done
IFS=$OIFS

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

[ -z $NDK ] && NDK=false
if $NDK; then
  # Set up Android NDK
  echogreen "Fetching Android NDK $NDKVER"
  [ -f "android-ndk-$NDKVER-linux-x86_64.zip" ] || wget https://dl.google.com/android/repository/android-ndk-$NDKVER-linux-x86_64.zip
  [ -d "android-ndk-$NDKVER" ] || unzip -qo android-ndk-$NDKVER-linux-x86_64.zip
  export ANDROID_NDK_HOME=$DIR/android-ndk-$NDKVER
  export ANDROID_TOOLCHAIN=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin
else
  NDK=false
fi

[ -z "$ARCH" -o "$ARCH" == "all" ] && ARCH="arm arm64 x86 x64"
for LARCH in $ARCH; do
  case $LARCH in
    arm64|aarch64) LINKER=linker64; LARCH=aarch64; $NDK && target_host=aarch64-linux-android || { target_host=aarch64-linux-gnu; LINARO=true; };;
    arm) LINKER=linker; LARCH=arm; $NDK && target_host=arm-linux-androideabi || { target_host=arm-linux-gnueabi; LINARO=true; };;
    x64|x86_64) LINKER=linker64; LINARO=false; LARCH=x86_64; $NDK && target_host=x86_64-linux-android || target_host=x86_64-linux-gnu;;
    x86|i686) LINKER=linker; LINARO=false; LARCH=i686; $NDK && target_host=i686-linux-android || target_host=i686-linux-gnu;;
    *) echored "Invalid ARCH entered!"; usage;;
  esac

  [ -z "$BIN" -o "$BIN" == "all" ] && BIN="bash bc coreutils cpio diffutils ed findutils gawk grep gzip ncurses patch sed tar"
  for LBIN in $BIN; do
    # Versioning and overrides
    LAPI=$API
		PVER=8.43
		ZVER=1.2.11
    case $LBIN in
      "bash") EXT=gz; VER=5.0;;
      "bc") EXT=gz; VER=1.07.1;;
      "coreutils") EXT=xz; VER=8.31; [ $LAPI -lt 23 ] && LAPI=23;;
      "cpio") EXT=gz; VER=2.12;;
      "diffutils") EXT=xz; VER=3.7;;
      "ed") EXT=lz; VER=1.15;;
      "findutils") EXT=xz; VER=4.7.0; [ $LAPI -lt 23 ] && LAPI=23;;
      "gawk") EXT=xz; VER=5.0.1;;
      "grep") EXT=xz; VER=3.3; [ $LAPI -lt 23 ] && LAPI=23;;
      "gzip") EXT=xz; VER=1.10;;
      "ncurses") EXT=gz; VER=6.1;;
      "patch") EXT=xz; VER=2.7.6;;
      "sed") EXT=xz; VER=4.7; [ $LAPI -lt 23 ] && LAPI=23;;
      "tar") EXT=xz; VER=1.32; LAPI=28;;
      *) echored "Invalid binary specified!"; usage;;
    esac

    [[ $(wget -S --spider http://mirrors.kernel.org/gnu/$LBIN/$LBIN-$VER.tar.$EXT 2>&1 | grep 'HTTP/1.1 200 OK') ]] || { echored "Invalid $LBIN VER! Check this: http://mirrors.kernel.org/gnu/$LBIN for valid versions!"; exit 1; }

    # Setup
    echogreen "Fetching $LBIN $VER"
    rm -rf $LBIN-$VER
		[ -f "$LBIN-$VER.tar.$EXT" ] || wget http://mirrors.kernel.org/gnu/$LBIN/$LBIN-$VER.tar.$EXT
    tar -xf $LBIN-$VER.tar.$EXT

    export PATH=$OPATH
    unset AR AS LD RANLIB STRIP CC GCC CXX GXX
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
	      export PATH=`pwd`/gcc-linaro-7.5.0-2019.12-x86_64_$target_host/bin:$PATH
        export CC=$target_host-gcc
        export CXX=$target_host-g++
      fi
    fi

    # Run patches/fixes and configure
    echogreen "Configuring for $LARCH"
    unset FLAGS
    cd $DIR/$LBIN-$VER
    case $LBIN in
      "bash") $STATIC && FLAGS="--enable-static-link "; bash_patches || exit 1;;
      "coreutils"|"sed") $NDK && { sed -i "s/USE_FORTIFY_LEVEL/BIONIC_FORTIFY/g" lib/cdefs.h; sed -i "s/USE_FORTIFY_LEVEL/BIONIC_FORTIFY/g" lib/stdio.in.h; };;
      "tar") $NDK && { sed -i "s/USE_FORTIFY_LEVEL/BIONIC_FORTIFY/g" gnu/cdefs.h; sed -i "s/USE_FORTIFY_LEVEL/BIONIC_FORTIFY/g" gnu/stdio.in.h; };;
    esac
    # Fix for mktime_internal build error for non-ndk arm/64 cross-compile
    case $LBIN in
      "coreutils"|"diffutils"|"findutils"|"patch"|"tar") $NDK || sed -i -e '/WANT_MKTIME_INTERNAL=0/i\WANT_MKTIME_INTERNAL=1\n$as_echo "#define NEED_MKTIME_INTERNAL 1" >>confdefs.h' -e '/^ *WANT_MKTIME_INTERNAL=0/,/^ *fi/d' configure;;
		esac
		# Fix %n issue due to these binaries using old gnulib (This was in Jan 2019: http://git.savannah.gnu.org/gitweb/?p=gnulib.git;a=commit;h=6c0f109fb98501fc8d65ea2c83501b45a80b00ab)
		case $LBIN in
			"cpio"|"tar") sed -i 's/!defined __UCLIBC__)/!defined __UCLIBC__) || defined __ANDROID__/' gnu/vasnprintf.c;;
			"gzip") sed -i 's/!defined __UCLIBC__)/!defined __UCLIBC__) || defined __ANDROID__/' lib/vasnprintf.c;;
		esac
		# Fix for minus_zero duplication error in NDK
		case $LBIN in
			"coreutils") $NDK && sed -i -e '/if (!num && negative)/d' -e "/return minus_zero/d" -e "/DOUBLE minus_zero = -0.0/d" lib/strtod.c;;
		esac
    [ -f $DIR/$LBIN.patch ] && patch_file $DIR/$LBIN.patch
    if $STATIC; then
      CFLAGS='-static -O2'
      LDFLAGS='-static'
      $NDK && [ -f $DIR/ndk_static_patches/$LBIN.patch ] && patch_file $DIR/ndk_static_patches/$LBIN.patch
    else
      CFLAGS='-O2 -fPIE -fPIC'
      LDFLAGS='-s -pie'
      $NDK || LDFLAGS="$LDFLAGS -Wl,-dynamic-linker,/system/bin/$LINKER"
    fi

    case $LARCH in
      "arm") CFLAGS="$CFLAGS -mfloat-abi=softfp -mthumb"; LDFLAGS="$LDFLAGS -march=armv7-a -Wl,--fix-cortex-a8";;
      "i686") CFLAGS="$CFLAGS -march=i686 -mtune=intel -mssse3 -mfpmath=sse -m32"; [ -z $FLAGS ] && FLAGS="TIME_T_32_BIT_OK=yes " || FLAGS="$FLAGS TIME_T_32_BIT_OK=yes ";;
      "x86_64") CFLAGS="$CFLAGS -march=x86-64 -msse4.2 -mpopcnt -m64 -mtune=intel";;
    esac

    # Ed has super old configure flags, Bash got lots of stuff, Sort and timeout don't work on some roms, grep needs pcre
    case $LBIN in
      "bash") ./configure $FLAGS--disable-nls --without-bash-malloc bash_cv_dev_fd=whacky bash_cv_getcwd_malloc=yes --enable-largefile --enable-alias --enable-history --enable-readline --enable-multibyte --enable-job-control --enable-array-variables --disable-stripping --host=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS";;
      "coreutils") $NDK && ./configure $FLAGS--disable-nls --without-gmp --enable-no-install-program=stdbuf --enable-single-binary=symlinks --prefix=/system --sbindir=/system/bin --libexecdir=/system/bin --sharedstatedir=/sdcard/gnu/com --localstatedir=/sdcard/gnu/var --datarootdir=/sdcard/gnu/share --host=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || ./configure $FLAGS--disable-nls --without-gmp --with-gnu-ld --enable-no-install-program=stdbuf --enable-single-binary=symlinks --enable-single-binary-exceptions=sort,timeout,sleep --prefix=/system --sbindir=/system/bin --libexecdir=/system/bin --sharedstatedir=/sdcard/gnu/com --localstatedir=/sdcard/gnu/var --datarootdir=/sdcard/gnu/share --host=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS";;
      "ed") [ "$target_host" == "i686-linux-gnu" ] && ./configure --disable-stripping CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || ./configure --disable-stripping CC=$GCC CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS";;
			"findutils") ./configure $FLAGS--disable-nls --prefix=/system --sbindir=/system/bin --libexecdir=/system/bin --sharedstatedir=/sdcard/gnu/com --localstatedir=/sdcard/gnu/var --datarootdir=/sdcard/gnu/share --host=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS";;
			"grep") build_pcre -s
							./configure $FLAGS--disable-shared --enable-perl-regexp --disable-nls --host=$target_host CFLAGS="$CFLAGS -I$DIR/$LBIN-$VER/pcre/include" LDFLAGS="$LDFLAGS -L$DIR/$LBIN-$VER/pcre/lib";;
			*) ./configure $FLAGS--disable-nls --without-gmp --disable-stripping --host=$target_host CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS";;
    esac
    [ $? -eq 0 ] || { echored "Configure failed!"; exit 1; }

    # Build
    echogreen "Building"
    # Fixes
    case $LBIN in
      "bc") sed -i -e '\|./fbc -c|d' -e 's|$(srcdir)/fix-libmath_h|cp -f ../../bc_libmath.h $(srcdir)/libmath.h|' bc/Makefile;;
      "coreutils") [ ! "$(grep "#define HAVE_MKFIFO 1" lib/config.h)" ] && echo "#define HAVE_MKFIFO 1" >> lib/config.h;;
    esac

    make -j$JOBS
    [ $? -eq 0 ] || { echored "Build failed!"; exit 1; }

    # Fix paths in updatedb
    [ "$LBIN" == "findutils" ] && sed -i -e "s|/usr/bin|/system/bin|g" -e "s|SHELL=\".*\"|SHELL=\"/system/bin/sh\"|" -e "s|# The database file to build.|# The database file to build.\nmkdir -p /sdcard/gnu/tmp /sdcard/gnu/var|" -e "s|TMPDIR=/tmp|TMPDIR=/sdcard/gnu/tmp|" locate/updatedb

		rm -rf $DIR/out/$LARCH/$LBIN 2>/dev/null
		mkdir $DIR/out/$LARCH/$LBIN 2>/dev/null
    make install -j$JOBS DESTDIR=$DIR/out/$LARCH/$LBIN
    echogreen "$LBIN built sucessfully and can be found at: $DIR/out/$LARCH"
    cd $DIR
  done
done
