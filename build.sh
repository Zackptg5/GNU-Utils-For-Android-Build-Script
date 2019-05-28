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
  echogreen "           Note that you can put as many of these as you want together as long as they're comma separated"
  echogreen "           Ex: BIN=cpio,gzip,tar"
  echored "Coreutils additional options:"
  echogreen "FULL=true (Default true) Set this to true to compile all of coreutils, otherwise only advanced cp/mv will be setup"
  echogreen "SEP=true  (Default false) Set this to true to compile all of coreutils into separate binaries (only applicable if FULL=true)"
  echogreen "           Also note that coreutils includes advanced cp/mv (adds progress bar functionality with -g flag"
  echo " "
  exit 1
}
cp_strip () {
  for i in $1; do
    cp -f $i $DIR/$LARCH/`basename $i`
    if $LINARO; then
      $target_host-strip $DIR/$LARCH/`basename $i`
    else
      strip $DIR/$LARCH/`basename $i`
    fi
  done
}
bash_patches() {
  echogreen "Applying patches"
  local PVER=$(echo $VER | sed 's/\.//')
  for i in {001..050}; do
    wget http://ftp.gnu.org/gnu/bash/bash-$VER-patches/bash$PVER-$i 2>/dev/null
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
    [ $? -ne 0 ] && { echored "Patching failed! Did you verify line numbers? See README for more info"; return 1; }
    rm -f $PFILE
  done
}

TEXTRESET=$(tput sgr0)
TEXTGREEN=$(tput setaf 2)
TEXTRED=$(tput setaf 1)
DIR=`pwd`
LINARO=false
FULL=true
SEP=false
export OPATH=$PATH
OIFS=$IFS; IFS=\|; 
while true; do
  case "$1" in
    -h|--help) usage;;
    "") shift; break;;
    BIN=*|ARCH=*|FULL=*|SEP=*) eval $(echo "$1" | sed -e 's/=/="/' -e 's/$/"/' -e 's/,/ /g'); shift;;
    *) echored "Invalid option: $1!"; usage;;
  esac
done
IFS=$OIFS

[ -z "$ARCH" -o "$ARCH" == "all" ] && ARCH="arm arm64 x86 x64"
for LARCH in $ARCH; do
  case $LARCH in
    arm64|aarch64) LARCH=arm64; target_host=aarch64-linux-gnu; LINARO=true;;
    arm) LARCH=arm; target_host=arm-linux-gnueabi; LINARO=true;;
    x64|x86_64) LARCH=x64; target_host=x86_64-linux-gnu; LINARO=false;;
    x86|i686) LARCH=x86; target_host=i686-linux-gnu; LINARO=false;;
    *) echored "Invalid ARCH entered!"; usage;;
  esac

  [ -z "$BIN" -o "$BIN" == "all" ] && BIN="bash bc coreutils cpio diffutils ed findutils gawk grep gzip ncurses patch sed tar"
  for LBIN in $BIN; do
    case $LBIN in
      "bash") EXT=gz; VER=5.0;;
      "bc") EXT=gz; VER=1.07.1;;
      "coreutils") EXT=xz; VER=8.31;;
      "cpio") EXT=gz; VER=2.12;;
      "diffutils") EXT=xz; VER=3.7;;
      "ed") EXT=lz; VER=1.15;;
      "findutils") EXT=gz; VER=4.6.0;;
      "gawk") EXT=xz; VER=5.0.0;;
      "grep") EXT=xz; VER=3.3;;
      "gzip") EXT=xz; VER=1.10;;
      "ncurses") EXT=gz; VER=6.1;;
      "patch") EXT=xz; VER=2.7.6;;
      "sed") EXT=xz; VER=4.7;;
      "tar") EXT=xz; VER=1.32;;
      *) echored "Invalid binary specified!"; usage;;
    esac

    [[ $(wget -S --spider ftp.gnu.org/gnu/$LBIN/$LBIN-$VER.tar.$EXT 2>&1 | grep 'HTTP/1.1 200 OK') ]] || { echored "Invalid $LBIN VER! Check this: ftp.gnu.org/gnu/$LBIN for valid versions!"; continue; }

    # Setup
    echogreen "Fetching $LBIN $VER"
    rm -rf $LBIN-$VER
    [ -f "$LBIN-$VER.tar.$EXT" ] || wget ftp.gnu.org/gnu/$LBIN/$LBIN-$VER.tar.$EXT
    tar -xf $LBIN-$VER.tar.$EXT

    export PATH=$OPATH
    if $LINARO; then
      [ -f gcc-linaro-7.4.1-2019.02-x86_64_$target_host.tar.xz ] || { echogreen "Fetching Linaro gcc"; wget https://releases.linaro.org/components/toolchain/binaries/latest-7/$target_host/gcc-linaro-7.4.1-2019.02-x86_64_$target_host.tar.xz; }
      [ -d gcc-linaro-7.4.1-2019.02-x86_64_$target_host ] || { echogreen "Setting up Linaro gcc"; tar -xf gcc-linaro-7.4.1-2019.02-x86_64_$target_host.tar.xz; }

      # Add the standalone toolchain to the search path.
      export PATH=`pwd`/gcc-linaro-7.4.1-2019.02-x86_64_$target_host/bin:$PATH
    fi
    
    cd $DIR/$LBIN-$VER
    
    if [ "$LBIN" == "bash" ]; then
      case $VER in
        5*) rm -rf $DIR/bash_patches; cp -rf $DIR/bash_patches_5 $DIR/bash_patches;;
        *) rm -rf $DIR/bash_patches; cp -rf $DIR/bash_patches_4 $DIR/bash_patches;;
      esac
      bash_patches || continue
    elif [ "$LBIN" == "coreutils" ]; then
      # Apply patches - originally by atdt and Sonelli @ github
      echogreen "Applying advcpmv patches"
      patch -p1 -i $DIR/advcpmv-$VER.patch
      [ $? -ne 0 ] && { echored "ADVC patching failed! Did you verify line numbers? See README for more info"; continue; }
    fi

    # Configure
    echogreen "Configuring for $LARCH"
    if [ "$target_host" == "i686-linux-gnu" ]; then
      FLAGS='-m32 -march=i686 -static -O2'
      HOST="TIME_T_32_BIT_OK=yes --host=$target_host"
    else
      FLAGS='-static -O2'
      HOST="--host=$target_host"
    fi
    # Fix for mktime_internal build error for arm/64 cross-compile
    [ "$LBIN" == "coreutils" -o "$LBIN" == "diffutils" -o "$LBIN" == "patch" -o "$LBIN" == "tar" ] && sed -i -e '/WANT_MKTIME_INTERNAL=0/i\WANT_MKTIME_INTERNAL=1\n$as_echo "#define NEED_MKTIME_INTERNAL 1" >>confdefs.h' -e '/^ *WANT_MKTIME_INTERNAL=0/,/^ *fi/d' configure
    # Single binary coreutils if applicable
    [ "$LBIN" == "coreutils" ] && $FULL && ! $SEP && HOST="--enable-single-binary=symlinks $HOST"
    
    # Ed has super old configure flags, Bash got lots of stuff
    case $LBIN in
      "bash") ./configure --disable-nls --without-bash-malloc bash_cv_dev_fd=whacky bash_cv_getcwd_malloc=yes --enable-largefile --enable-alias --enable-history --enable-readline --enable-multibyte --enable-job-control --enable-array-variables $HOST CFLAGS="$FLAGS" LDFLAGS="$FLAGS";;
      "ed") [ "$target_host" == "i686-linux-gnu" ] && ./configure CFLAGS="$FLAGS" LDFLAGS="$FLAGS" || ./configure CC=$target_host-gcc CFLAGS="$FLAGS" LDFLAGS="$FLAGS";;
      "ncurses") export AR="ar" AS="clang -m32" CC="clang -m32" CXX="clang++ -m32" LD="ld" STRIP="strip"; ./configure --disable-nls --without-gmp $HOST CFLAGS="$FLAGS" LDFLAGS="$FLAGS";;
      *) ./configure --disable-nls --without-gmp $HOST CFLAGS="$FLAGS" LDFLAGS="$FLAGS";;
    esac
    [ $? -eq 0 ] || { echored "Configure failed!"; cd $DIR; continue; }

    # Build
    echogreen "Building"
    sed -i 's/^MANS = .*//g' Makefile
    # Fix for coreutils
    [ "$LBIN" == "coreutils" ] && [ ! "$(grep "#define HAVE_MKFIFO 1" lib/config.h)" ] && echo "#define HAVE_MKFIFO 1" >> lib/config.h
    # Fix for bc
    [ "$LBIN" == "bc" ] && sed -i -e '\|./fbc -c|d' -e 's|$(srcdir)/fix-libmath_h|cp -f ../../bc_libmath.h $(srcdir)/libmath.h|' bc/Makefile
    make
    [ $? -eq 0 ] || { echored "Build failed!"; cd $DIR; continue; }
    
    # Process    
    mkdir $DIR/$LARCH 2>/dev/null
    case $LBIN in
      "bash") cp_strip "$LBIN";;
      "bc") cp_strip "$LBIN/$LBIN dc/dc";;
      "coreutils") if $FULL; then
                     if $SEP; then
                       for i in $(cat $DIR/coreutils_modules); do
                         cp_strip src/$i
                       done
                     else
                       cp_strip src/$LBIN
                     fi
                   else
                     cp_strip "src/cp src/mv"
                   fi;;
      "cpio") cp_strip src/$LBIN;;
      "diffutils") cp_strip "src/cmp src/diff src/diff3 src/sdiff";;
      "ed") cp_strip $LBIN;;
      "findutils") cp_strip "find/find locate/bigram locate/code locate/frcode locate/locate locate/updatedb xargs/xargs";;
      "gawk") cp_strip $LBIN;;
      "grep") cp_strip src/$LBIN; cp -f src/egrep src/fgrep $DIR/$LARCH/;;
      "gzip") cp_strip $LBIN; cp -f gunzip gzexe $DIR/$LARCH/;;
      "ncurses") cp_strip "progs/clear progs/infocmp progs/tabs progs/tic progs/toe progs/tput progs/tset";;
      "patch") cp_strip src/$LBIN;;
      "sed") cp_strip $LBIN/$LBIN;;
      "tar") cp_strip src/$LBIN;;
    esac
    echogreen "$LBIN built sucessfully and can be found at: $DIR/$LARCH"
    cd $DIR
  done
done
