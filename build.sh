#!/bin/sh
set -ex

freebsd-version -ru

sysctl net.inet.ip.forwarding=1

mkdir -p /usr/local/etc/pkg/repos
cat > /usr/local/etc/pkg/repos/FreeBSD.conf <<'EOF'
FreeBSD-ports: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/latest"
}
FreeBSD-base: {
  enabled: yes
}
EOF

pkg install -y FreeBSD-zfs podman-suite

truncate -s 16G /var/tmp/z
mkdir -p /var/db/containers/storage
zpool create -R /var/db/containers/storage -O mountpoint=/ -O compression=lz4 z /var/tmp/z

buildah login --username="$GITHUB_ACTOR" --password="$GITHUB_TOKEN" ghcr.io

version=''

mkdir cache repos
export IGNORE_OSVERSION=yes
export PKG_CACHEDIR=$(pwd)/cache

imgs="runtime dynamic static"

version_major="${INPUT_RELEASE%.*}"
if [ "$version_major" -ge 15 ]; then
  imgs="toolchain notoolchain $imgs"
fi

for img in $imgs; do
  manifest=freebsd:$INPUT_RELEASE-$img
  podman manifest create $manifest

  for arch in amd64 arm64-aarch64; do
    c=$(buildah from --pull=always --arch=${arch%-*} docker://ghcr.io/freebsd/freebsd-$img:$INPUT_RELEASE)
    m=$(buildah mount $c)

    rm -f $m/usr/local/etc/pkg/repos/base.conf
    cp /usr/local/etc/pkg/repos/FreeBSD.conf $m/usr/local/etc/pkg/repos/

    abi=FreeBSD:${INPUT_RELEASE%.*}:${arch#*-}

    if [ "$version_major" -lt 15 ]; then
      ln -s pkg $m/usr/share/keys/pkgbase-$version_major
    fi

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
      podman manifest push --all $manifest ghcr.io/"$GITHUB_REPOSITORY_OWNER"/freebsd:$version_major-$img
    fi

    if [ "$INPUT_TAGS" = 'latest' ]; then
      podman manifest push --all $manifest ghcr.io/"$GITHUB_REPOSITORY_OWNER"/freebsd:$img
    fi
  fi

  podman manifest rm $manifest
done
