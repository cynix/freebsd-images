#! /bin/sh

. lib.sh

fixup() {
    local m=$1
    local c=$2
    local workdir=$3

    cat > ${workdir}/repos/FreeBSD.conf <<EOF
FreeBSD: {
  url: "pkg+https://pkg.FreeBSD.org/\${ABI}/latest",
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg",
}
EOF

    install_packages ${workdir} $m \
		autoconf \
		automake \
		cmake \
		gmake \
		jq \
		ninja \
		pkgconf

    local desc=$(cat <<EOF
In addition to the contents of small, contains:
- development tools
- development libraries
EOF
	  )
    add_annotation $c "org.opencontainers.image.title=Image for development workloads"
    add_annotation $c "org.opencontainers.image.description=${desc}"
}

parse_args "$@"

if [ ${BUILD} = yes ]; then
    build_image small dev "" fixup \
		FreeBSD-clang \
		FreeBSD-clang-dev \
		FreeBSD-clibs-dev \
		FreeBSD-elftoolchain \
		FreeBSD-libarchive-dev \
		FreeBSD-libcompiler_rt-dev \
		FreeBSD-libexecinfo-dev \
		FreeBSD-libsqlite3-dev \
		FreeBSD-libucl-dev \
		FreeBSD-lld \
		FreeBSD-openssl-lib-dev \
		FreeBSD-runtime-dev \
		FreeBSD-utilities-dev
fi
if [ ${PUSH} = yes ]; then
    push_image dev
fi
