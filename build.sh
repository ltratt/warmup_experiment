#! /bin/sh

unknown_platform() {
    echo "Unknown platform: `uname`"
    exit 1
}

missing=0
check_for () {
    which $1 > /dev/null 2> /dev/null
    if [ $? -ne 0 ]; then
        echo "Error: can't find $1 binary"
        missing=1
    fi
}

check_for cc
check_for g++
check_for bunzip2
check_for git
check_for hg
check_for python
check_for svn
check_for unzip
check_for xml2-config
check_for bash
check_for java
check_for javac
check_for xzdec
check_for wget

case `uname` in
    Linux*) PATCH_ARGS=--backup
esac

which pypy > /dev/null 2> /dev/null
if [ $? -eq 0 ]; then
    PYTHON=`which pypy`
else
    PYTHON=`which python2.7`
fi

# Let's use GNU make across the board
case `uname` in
    OpenBSD) GMAKE=gmake;;
    Linux) GMAKE=make;;
    *) unknown_platform;;
esac
check_for ${GMAKE}

if [ $missing -eq 1 ]; then
    exit 1
fi

HERE=`pwd`
wrkdir=${HERE}/work
PATCH_DIR=${HERE}/patches

mkdir -p ${wrkdir}
echo "===> Working in $wrkdir"

PATCH_DIR=`pwd`/patches/

# XXX when we stabilise, fix the krun revision.
fetch_krun() {
    echo "\n===> Download and build krun\n"
    if ! [ -d "${HERE}/krun" ]; then
        cd ${HERE} && git clone https://github.com/softdevteam/krun.git || exit $?
    fi
}

# We build our own fixed version of GCC, thus ruling out differences in
# packaged compilers for the different platforms.
GCC_V=4.9.3
OUR_CC=${wrkdir}/gcc-inst/bin/zgcc
OUR_CXX=${wrkdir}/gcc-inst/bin/zg++
GCC_TARBALL_URL=ftp://ftp.mirrorservice.org/sites/ftp.gnu.org/gnu/gcc/gcc-${GCC_V}/gcc-${GCC_V}.tar.gz
build_gcc() {
    echo "\n===> Download and build GCC\n"
    if [ -f ${OUR_CC} ]; then return; fi
    cd ${wrkdir}
    if ! [ -f ${wrkdir}/gcc-${GCC_V}.tar.gz ]; then
        wget ${GCC_TARBALL_URL} || exit $?
    fi
    if ! [ -d ${wrkdir}/gcc ]; then
        tar xfzp gcc-${GCC_V}.tar.gz || exit $?;
        mv gcc-${GCC_V} gcc || exit $?
    fi
    cd gcc || exit $?

    if [ `uname` = "OpenBSD" ]; then
        for p in `ls ${PATCH_DIR}/openbsd_gcc_patches`; do
            patch -Ep0 < ${PATCH_DIR}/openbsd_gcc_patches/$p || exit $?
        done
    fi

    # download script uses fixed versions, so OK.
    ./contrib/download_prerequisites || exit $?

    mkdir sd_build || exit $?
    cd sd_build || exit $?

    ../configure \
        --prefix=${wrkdir}/gcc-inst \
        --disable-libcilkrts \
        --program-transform-name=s,^,z, \
        --verbose \
        --disable-libmudflap \
        --disable-libgomp \
        --disable-multilib \
        --disable-tls \
        --enable-languages=c,c++ \
        --with-system-zlib \
        --disable-tls \
        --enable-threads=posix \
        --enable-wchar_t \
        --disable-libstdcxx-pch \
        --enable-cpp \
        --enable-shared \
      || exit $?
    ${GMAKE} || exit $?
    ${GMAKE} install || exit $?
}

CPYTHONV=2.7.11
CFFI_V=1.5.0
SETUPTOOLS_V=20.1.1
CPYTHON=${wrkdir}/cpython-inst/bin/python
build_cpython() {
    cd ${wrkdir} || exit $?
    echo "\n===> Download and build CPython\n"
    if [ -f ${wrkdir}/cpython/python ]; then return; fi
    cd $wrkdir
    wget http://python.org/ftp/python/${CPYTHONV}/Python-${CPYTHONV}.tgz || exit $?
    tar xfz Python-${CPYTHONV}.tgz || exit $?
    mv Python-${CPYTHONV} cpython
    cd cpython
    CC=${OUR_CC} ./configure --prefix=${wrkdir}/cpython-inst || exit $?
    ${GMAKE} || exit $?
    ${GMAKE} install || exit $?

    # Install packages.
    # I would liked to have used virtualenv, but cffi fails to install using our manually
    # built CPython. I suspect a bug in setuptools/virtualenv in debian8.
    # Instead, install stuff manually.
    cd ${wrkdir} && wget https://pypi.python.org/packages/source/s/setuptools/setuptools-${SETUPTOOLS_V}.tar.gz || exit $?
    tar zxvf setuptools-${SETUPTOOLS_V}.tar.gz || exit $?
    cd setuptools-${SETUPTOOLS_V} && ${CPYTHON} setup.py install || exit $?

    cd ${wrkdir} && wget https://pypi.python.org/packages/source/c/cffi/cffi-${CFFI_V}.tar.gz || exit $?
    tar zxvf cffi-${CFFI_V}.tar.gz || exit $?
    cd cffi-${CFFI_V} && ${CPYTHON} setup.py install
}

LUAJITV=2.0.4
build_luajit() {
    cd ${wrkdir} || exit $?
    echo "\n===> Download and build LuaJIT\n"
    if [ -f ${wrkdir}/luajit/src/luajit ]; then return; fi
    wget http://luajit.org/download/LuaJIT-${LUAJITV}.tar.gz || exit $?
    tar xfz LuaJIT-${LUAJITV}.tar.gz
    mv LuaJIT-${LUAJITV} luajit
    cd luajit
    CFLAGS=-DLUAJIT_ENABLE_LUA52COMPAT ${GMAKE} CC=${OUR_CC} || exit $?
}

PYPYV=5.3.0
build_pypy() {
    cd ${wrkdir} || exit $?
    echo "\n===> Download and build PyPy\n"

    if ! [ -f "${wrkdir}/pypy2-v${PYPYV}-src.tar.bz2" ]; then
        url="https://bitbucket.org/pypy/pypy/downloads/pypy2-v${PYPYV}-src.tar.bz2"
        case `uname` in
            OpenBSD) ftp $url || exit $?;;
            *) wget $url || exit $?;;
        esac
    fi

    if ! [ -d "${wrkdir}/pypy" ]; then
        bunzip2 -c - pypy2-v${PYPYV}-src.tar.bz2 | tar xf - || exit $?
        mv pypy2-v${PYPYV}-src pypy || exit $?
        cd pypy
        case `uname` in
            OpenBSD) patch < ${PATCH_DIR}/pypy_openbsd.diff || exit $?;;
        esac
    fi

    if ! [ -f ${wrkdir}/pypy/pypy/goal/pypy-c ]; then
        cd ${wrkdir}/pypy/pypy/goal/ || exit $?
        usession=`mktemp -d`

        env CC=${OUR_CC} PYPY_USESSION_DIR=$usession $PYTHON \
            ../../rpython/bin/rpython -Ojit || exit $?

        rm -rf $usession
    fi
}

V8_V=5.1.281.65
build_v8() {
    cd ${wrkdir} || exit $?
    echo "\n===> Download and build V8\n"

    if [ -f ${wrkdir}/v8/out/native/d8 ]; then return; fi

    git clone "https://chromium.googlesource.com/chromium/tools/depot_tools.git" || exit $?
    cd depot_tools || exit $?

    # The build actually requires that you clone using this git wrapper tool
    cd ${wrkdir}
    OLDPATH=${PATH}
    # v8's build needs python 2.7.11; as we've already built that, we might
    # as well use it rather than forcing the user to install their own.
    PATH=${wrkdir}/cpython-inst/bin:${wrkdir}/depot_tools:${PATH}
    # XXX we should check for errors when fetching and syncing, but
    # currently that causes problems because fetch runs a script which
    # aborts on OpenBSD
    fetch v8
    cd v8 || exit $?
    git checkout ${V8_V}
    gclient sync
    patch -Ep1 < ${PATCH_DIR}/v8_various.diff || exit $?

    # The build fails for silly reasons near the very end, even though the main
    # v8 binary has been built. So we simply check that the binary exists and
    # suppress unrelated build errors.
    # Bug report https://code.google.com/p/v8/issues/detail?id=4500
    #
    # This used to be only the case on OpenBSD, but since we started building
    # our own gcc, the tests also fail in strange ways on linux.
    #
    # V8 also mistakes our compiler for clang for some reason, hence
    # setting GYP_DEFINES.
    env GYP_DEFINES="clang=0" CC=${OUR_CC} CXX=${OUR_CXX} ${GMAKE} native
    test -f out/native/d8 || exit $?
    PATH=${OLDPATH}
}

# There is a bug in the JDK8 build system which makes it incompatible with GNU make 4
# http://stackoverflow.com/questions/21246042/scrambled-arguments-when-building-openjdk
# Let's build 3.82 then.
GMAKE_V=3.82
build_gmake() {
    echo "\n===> Download and build gmake-${GMAKE_V}\n"
    if [ -f ${wrkdir}/make-${GMAKE_V}/make ]; then return; fi
    cd ${wrkdir} || exit $?
    wget http://ftp.gnu.org/gnu/make/make-${GMAKE_V}.tar.gz || exit $?
    tar zxvf make-${GMAKE_V}.tar.gz || exit $?
    cd make-${GMAKE_V} || exit $?
    CC=${OUR_CC} ./configure || exit $?
    ${GMAKE} || exit $?
    cp make gmake
}

# We use the JDK we just built for all consequent Java compilation (and as a
# basis for the Graal compiler).
case `uname` in
    Linux)   OUR_JAVA_HOME=${wrkdir}/openjdk/build/linux-x86_64-normal-server-release/images/j2sdk-image/;;
    OpenBSD) OUR_JAVA_HOME=${wrkdir}/openjdk/build/bsd-x86_64-normal-server-release/images/j2sdk-image/;;
    *) unknown_platform;;
esac
JDK_TARBALL_BASE=openjdk-8u72b15-bsd-port-20160220
build_jdk() {
    echo "\n===> Download and build JDK8\n"
    if [ -f ${OUR_JAVA_HOME}/bin/javac ]; then return; fi
    cd ${wrkdir} || exit $?
    if ! [ -f "${wrkdir}/${JDK_TARBALL_BASE}.tar.xz" ]; then
        wget http://www.intricatesoftware.com/distfiles/${JDK_TARBALL_BASE}.tar.xz || exit $?
    fi
    if ! [ -d ${wkrdir}/openjdk ]; then
        xzdec ${JDK_TARBALL_BASE}.tar.xz | tar xf - || exit $?
        mv ${JDK_TARBALL_BASE} openjdk
    fi
    cd openjdk || exit $?
    JDK_BUILD_PATH=`dirname ${OUR_CC}`:${PATH}
    case `uname` in
        Linux)
	    env CC=zgcc CXX=zg++ PATH=${JDK_BUILD_PATH} bash configure \
	      --disable-option-checking \
	      --with-cups-include=/usr/local/include \
	      --with-jobs=8 \
		      --with-debug-level=release \
	      --with-debug-level=release \
	      --disable-ccache \
	      --disable-freetype-bundling \
	      --disable-zip-debug-info \
	      --disable-debug-symbols \
	      --enable-static-libjli \
	      --with-zlib=system \
	      --with-milestone=fcs \
	      || exit $?
		PATH=${JDK_BUILD_PATH} ../make-${GMAKE_V}/make all || exit $?
	    ;;
        OpenBSD)
            env CPPFLAGS=-I/usr/local/include \
              LDFLAGS=-L/usr/local/lib \
              CC=zgcc CXX=zg++ PATH=${JDK_BUILD_PATH} ac_cv_path_NAWK=awk bash configure \
              --disable-option-checking \
              --with-cups-include=/usr/local/include \
              --with-jobs=8 \
          	    --with-debug-level=release \
              --with-debug-level=release \
              --disable-ccache \
              --disable-freetype-bundling \
              --disable-zip-debug-info \
              --disable-debug-symbols \
              --enable-static-libjli \
              --with-zlib=system \
              --with-giflib=system \
              --with-milestone=fcs \
	      || exit $?
	    PATH=${JDK_BUILD_PATH} \
	    COMPILER_WARNINGS_FATAL=false \
	    DEFAULT_LIBPATH="/usr/lib:/usr/X11R6/lib:/usr/local/lib"\
	    ../make-${GMAKE_V}/make all || exit $?
	    ;;
        *)
            unknown_platform;;
    esac
    chmod -R 755 ${wrkdir}/openjdk/build || exit $?
}

# The latest Graal and MX at the time of writing. Note that Graal will be part
# of JDK9 soon, so the build steps you see here will be out of date soon. Also
# note that MX doesn't have releases.
MX_VERSION=9405be47481c8ce1ef14e2c04e9f8182c4a49cf1
GRAAL_VERSION=graal-vm-0.12
MX="env JAVA_HOME=${OUR_JAVA_HOME} python2.7 ${wrkdir}/mx/mx.py"
build_graal() {
    echo "\n===> Download and build graal\n"

    if [ ! -d ${wrkdir}/mx ]; then
        cd ${wrkdir} && git clone https://github.com/graalvm/mx || exit $?
        cd mx && git checkout ${MX_VERSION} && cd .. || exit $?
    fi

    if [ -f ${wrkdir}/jvmci/jdk1.8*/product/bin/javac ]; then return; fi

    cd ${wrkdir}
    if ! [ -d ${wrkdir}/graal ]; then
        # Officially you are supposed to use mx to get the latest graal, but since
        # we need a fixed version, we deviate.
        git clone https://github.com/graalvm/graal-core graal || exit $?
        cd graal && git checkout ${GRAAL_VERSION} || exit $?

        if ! [ -d ${wrkdir}/jvmci ]; then
            # Then graal has in mx.graal/suite.py specifies a fixed version
            # of jvmci8 that is known to work with this version of graal.
            # To fetch it we use the sforceimports feature of mx.
            ${MX} sforceimports || exit $?
        fi
    fi

    # mx won't listen to CC/CXX
    ln -sf ${OUR_CC} `dirname ${OUR_CC}`/gcc
    ln -sf ${OUR_CXX} `dirname ${OUR_CXX}`/g++
    GRAAL_PATH=`dirname ${OUR_CC}`:${PATH}

    # Then we can build as usual.
    env PATH=${GRAAL_PATH} ${MX} build || exit $?

    # remove the symlinks
    rm `dirname ${OUR_CC}`/gcc `dirname ${OUR_CC}`/g++ || exit $?
}


# 9.1.2.0 with build system fixes for the buildkit.
JRUBY_V=graal-vm-0.12-build-pack-compat
JRUBY_BUILDPACK_V=graal-vm-0.12
JRUBY_BUILDPACK_DIR=${wrkdir}/jruby-build-pack/maven

build_jruby_truffle() {
    echo "\n===> Download and build truffle+jruby\n"
    cd ${wrkdir}
    if [ -f ${wrkdir}/jruby/bin/jruby ]; then return; fi
    if ! [ -d ${wrkdir}/jruby ]; then
        git clone https://github.com/jruby/jruby.git || exit $?
    fi
    if [ ! -d jruby-build-pack ]; then
        git clone https://github.com/jruby/jruby-build-pack.git || exit $?
    fi
    cd ${wrkdir}/jruby-build-pack && git checkout ${JRUBY_BUILDPACK_V} || exit $?
    cd ${wrkdir}/jruby && git checkout ${JRUBY_V} || exit $?

    # Install our truffle version into into the buildpack.  Apparently this
    # should not be needed under normal circumstances, as truffle from the
    # graal build is supposed to be picked up automatically. For some reason
    # this doesn't work for us, but this explicit workaround does.
    #
    # Must be run from the truffle dir!
    cd ${wrkdir}/truffle || exit $?
    env JAVACMD=${OUR_JAVA_HOME}/bin/java \
        MAVEN_OPTS=-Dmaven.repo.local=${JRUBY_BUILDPACK_DIR} \
        ${MX} maven-install || exit $?

    # NOTE: At the time of writing, JRuby will only build Truffle support if
    # the build is initiated using JDK>=8.
    #
    # Note the use of a specific truffle version (the same cloned by mx during
    # the graal build). This means we force jruby to build against the truffle
    # version we installed into the buildpack earlier.
    cd ${wrkdir}/jruby && JAVACMD=${OUR_JAVA_HOME}/bin/java \
        ./mvnw -Dtruffle.version=`cd ${wrkdir}/truffle && git rev-parse HEAD` \
        -Dmaven.repo.local=${JRUBY_BUILDPACK_DIR} --offline || exit $?

    # Then to invoke the VM:
    # JAVACMD=${wrkdir}/jvmci/jdk1.8.0/product/bin/java \
    #     ./work/jruby/bin/jruby -J-Djvmci.Compiler=graal -X+T ...
}


HHVM_VERSION=HHVM-3.14.0
build_hhvm() {
    echo "\n===> Download and build HHVM\n"
    if [ -f ${wrkdir}/hhvm/hphp/hhvm/php ]; then return; fi
    cd ${wrkdir} || exit $?
    if ! [ -d ${wrkdir}/hhvm ]; then
        git clone https://github.com/facebook/hhvm.git || exit $?
    fi
    cd hhvm || exit $?
    git checkout ${HHVM_VERSION} || exit $?
    git submodule update --init --recursive || exit $?
    patch -Ep1 < ${PATCH_DIR}/hhvm_clock_gettime_monotonic.diff || exit $?
    patch -Ep1 < ${PATCH_DIR}/hhvm_cmake.diff || exit $?

    # Some parts of the build (e.g. OCaml)  won't listen to CC/CXX
    ln -sf ${OUR_CC} `dirname ${OUR_CC}`/gcc || exit $?
    ln -sf ${OUR_CXX} `dirname ${OUR_CXX}`/g++ || exit $?
    HHVM_PATH=`dirname ${OUR_CC}`:${PATH}

    env PATH=${HHVM_PATH} CC=${OUR_CC} CXX=${OUR_CXX} sh -c "cmake -DMYSQL_UNIX_SOCK_ADDR=/dev/null -DBOOST_LIBRARYDIR=/usr/lib/x86_64-linux-gnu/ . && ${GMAKE}" || exit $?

    # remove the symlinks
    rm `dirname ${OUR_CC}`/gcc `dirname ${OUR_CC}`/g++ || exit $?
}


fetch_external_benchmarks() {
    echo "\n===> Download and build misc benchmarks\n"

    if [ -f "${HERE}/benchmarks/richards/java/richards.java" ]; then return; fi

cat << EOF
In order to build these benchmarks, you need to agree to the licensing terms
of the Java Richards benchmark at:
  http://web.archive.org/web/20050825101121/http://www.sunlabs.com/people/mario/java_benchmarking/index.html
EOF

    echo -n "Have you read and agreed to these terms? [Ny] " || exit $?
    read answer || exit $?
    case "$answer" in
        y | Y) ;;
        *) exit 1;;
    esac

    t=`mktemp -d` || exit $?
    cd $t || exit $?
    wget http://www.wolczko.com/richdbsrc.zip || exit $?
    unzip richdbsrc.zip || exit $?
    mv Benchmark.java Program.java COM/sun/labs/kanban/richards_deutsch_acc_virtual/ || exit $?
    cd COM/sun/labs/kanban/richards_deutsch_acc_virtual || exit $?
    mv Richards.java richards.java || exit $?
    cp *.java ${HERE}/benchmarks/richards/java || exit $?
    cd ${HERE}/benchmarks/richards/java || exit $?
    patch ${PATCH_ARGS} < ${PATCH_DIR}/java_richards.patch || exit $?
    rm -fr $t
}


# XXX fix when benchmarking for real.
LIBKALIBERA_VERSION=master
fetch_libkalibera() {
    echo "\n===> Fetch libkalibera\n"
    cd ${wrkdir}
    if ! [ -d libkalibera ]; then \
        git clone https://github.com/softdevteam/libkalibera.git || exit $?
        cd ${wrkdir}/libkalibera || exit $?
        git checkout ${LIBKALIBERA_VERSION} || exit $?
    fi
}


fetch_external_benchmarks
build_gcc

# Put GCC libs into linker path
# Needed for (e.g.) V8 to find libstdc++
case `uname` in
    Linux) export LD_LIBRARY_PATH=${wrkdir}/gcc-inst/lib64;;
    OpenBSD) export LD_LIBRARY_PATH=${wrkdir}/gcc-inst/lib;;
    *) unknown_platform;;
esac


case `uname` in
    Linux)
	fetch_libkalibera
	fetch_krun
	build_cpython
	build_luajit
	build_pypy
	build_v8
	build_gmake
	build_jdk
	build_graal
	build_jruby_truffle
	build_hhvm
    ;;
    OpenBSD)
	fetch_libkalibera
	fetch_krun
	build_cpython
	build_luajit
	build_pypy
	build_v8
	build_gmake
	build_jdk
    ;;
    *) unknown_platform;;
esac
