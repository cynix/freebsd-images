#!/bin/sh
set -ex

sysctl net.inet.ip.forwarding=1

mkdir -p /usr/local/etc/pkg/repos
cat > /usr/local/etc/pkg/repos/FreeBSD.conf <<'EOF'
FreeBSD: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/latest"
}
FreeBSD-base: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/base_release_${VERSION_MINOR}",
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg",
  enabled: yes
}
FreeBSD-kmods: {
  enabled: no
}
EOF
pkg install -y podman-suite

truncate -s 16G /var/tmp/z
mkdir -p /var/db/containers/storage
zpool create -R /var/db/containers/storage -O mountpoint=/ -O compression=lz4 z /var/tmp/z

buildah login --username="$GITHUB_ACTOR" --password="$GITHUB_TOKEN" ghcr.io

version=''

mkdir cache repos
export IGNORE_OSVERSION=yes
export PKG_CACHEDIR=$(pwd)/cache

for img in runtime dynamic static; do
  manifest=freebsd:$INPUT_RELEASE-$img
  podman manifest create $manifest

  for arch in amd64 arm64-aarch64; do
    c=$(buildah from --pull=always --arch=${arch%-*} docker://ghcr.io/freebsd/freebsd-$img:$INPUT_RELEASE)
    m=$(buildah mount $c)

    abi=FreeBSD:${INPUT_RELEASE%.*}:${arch#*-}

    env ABI=$abi OSVERSION=${INPUT_RELEASE%.*}0${INPUT_RELEASE#*.}000 pkg --rootdir $m upgrade -y

    if [ -z "$version" ]; then
      version=$(env ABI=$abi pkg --rootdir $m query '%v' FreeBSD-runtime)
    fi

    rm -rf $m/var/db/pkg/repos

    buildah unmount $c
    buildah config --arch=${arch%-*} --annotation=org.freebsd.version=$version $c
    buildah commit --manifest=$manifest --rm $c
  done

  podman manifest inspect $manifest

  if [ "$GITHUB_REF" = 'refs/heads/main' ]; then
    podman manifest push --all $manifest ghcr.io/"$GITHUB_REPOSITORY_OWNER"/$manifest

    if [ "$version" != "$INPUT_RELEASE" ]; then
      podman manifest push --all $manifest ghcr.io/"$GITHUB_REPOSITORY_OWNER"/freebsd:$version-$img
    fi

    if [ "$INPUT_TAGS" = 'major' -o "$INPUT_TAGS" = 'latest' ]; then
      podman manifest push --all $manifest ghcr.io/"$GITHUB_REPOSITORY_OWNER"/freebsd:${INPUT_RELEASE%.*}-$img
    fi

    if [ "$INPUT_TAGS" = 'latest' ]; then
      podman manifest push --all $manifest ghcr.io/"$GITHUB_REPOSITORY_OWNER"/freebsd:$img
    fi
  fi

  podman manifest rm $manifest
done
