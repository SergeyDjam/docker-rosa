#!/usr/bin/env bash
#
# Script to create Rosa Linux base images for integration with VM containers (docker, lxc , etc.).
# 
# Based on mkimage-urpmi.sh (https://github.com/juanluisbaptiste/docker-brew-mageia)
#


# check root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root. Example: sudo ./mkimage-urpmi.sh"
    exit
fi


set -efu

#TIME="${TIME:-5}"
arch="${arch:-x86_64}"
rosaVersion="${rosaVersion:-rosa2014.1}"
rootfsDir="${rootfsDir:-./BUILD_rootfs}" 
outDir="${outDir:-"."}"
# branding-configs-fresh, rpm-build have problems with dependencies, so let's install them in chroot
basePackages="${basePackages:-basesystem-minimal urpmi}"
#chrootPackages="${chrootPackages:-systemd initscripts termcap dhcp-client locales locales-en git-core htop iputils iproute2 squashfs-tools tar timezone passwd branding-configs-fresh}"
chrootPackages="${chrootPackages:-bash}"
mirror="${mirror:-http://mirror.yandex.ru/rosa/${rosaVersion}/repository/${arch}/}"
outName="${outName:-"rootfs-${rosaVersion}_${arch}_$(date +%Y-%m-%d)"}"
tarFile="${outDir}/${outName}.tar.xz"
sqfsFile="${outDir}/${outName}.sqfs"

(
        urpmi.addmedia --distrib \
                --mirrorlist "$mirror" \
                --urpmi-root "$rootfsDir"
        urpmi ${basePackages} \
                --auto \
                --no-suggests \
                --urpmi-root "$rootfsDir" \
                --root "$rootfsDir" \
                --clean
#        urpme --auto --root "$rootfsDir" \
#	      --auto-orphans -a vim
)

# make sure /etc/resolv.conf has something useful in it
mkdir -p "$rootfsDir/etc"
#cat > "$rootfsDir/etc/resolv.conf" <<'EOF'
#nameserver 8.8.8.8
#nameserver 77.88.8.8
#nameserver 8.8.4.4
#nameserver 77.88.8.1
#EOF

# Those packages, installation of which fails when they are listed in $basePackages, are installed in chroot
# Fix SSL in chroot (/dev/urandom is needed)
###### mount --bind -v /dev "${rootfsDir}/dev"
###### chroot "$rootfsDir" /bin/sh -c "urpmi ${chrootPackages} --auto --no-suggests"
chroot "$rootfsDir" /bin/sh -c "rpm --nodeps -a -e vim-enhanced"
chroot "$rootfsDir" /bin/sh -c "rpm --nodeps -a -e vim-common"
chroot "$rootfsDir" /bin/sh -c "urpmi --auto vim-minimal"

# Try to configure root shell
# package 'initscripts' contains important scripts from /etc/profile.d/
# package 'termcap' containes /etc/termcap which allows the console to work properly
chroot "$rootfsDir" /bin/sh -c "chsh --shell /bin/bash root"

if [ ! -d "${rootfsDir}/root" ]; then mkdir -p "${rootfsDir}/root"; fi
while read -r line
do
	cp -vp "${rootfsDir}/${line}" "${rootfsDir}/root/"
done < <(chroot "$rootfsDir" /bin/sh -c 'rpm -ql bash | grep ^/etc/skel')

# clean-up
for i in dev sys proc; do
	umount "${rootfsDir}/${i}" || :
	rm -fr "${rootfsDir:?}/${i:?}/*"
done

# systemd-networkd makes basic network configuration automatically
# After it, you can either make /etc/systemd/network/*.conf or
# `systemctl enable dhclient@eth0`, where eth0 is your network interface from `ip a`
chroot "$rootfsDir" /bin/sh -c "systemctl enable systemd-networkd"

# disable pam_securetty to allow logging in as root via `systemd-nspawn -b`
# https://bugzilla.rosalinux.ru/show_bug.cgi?id=9631
# https://github.com/systemd/systemd/issues/852
sed -e '/pam_securetty.so/d' -i "${rootfsDir}/etc/pam.d/login"

 pushd "$rootfsDir"

  # Clean.
        #  urpmi cache
        rm -rf var/cache/urpmi var/cache/ldconfig etc/ld.so.cache var/lib/urpmi usr/share/man usr/share/doc
        mkdir -p --mode=0755 var/cache/urpmi var/cache/ldconfig etc/ld.so.cache var/lib/urpmi usr/share/man usr/share/doc
#       rm -rf var/cache/urpmi
#       mkdir -p --mode=0755 var/cache/urpmi
#       rm -rf etc/ld.so.cache var/cache/ldconfig
#       mkdir -p --mode=0755 var/cache/ldconfig
#       rm -rf var/lib/urpmi
#       mkdir -p --mode=0755 var/lib/urpmi
#       rm -rf usr/share/man
#       mkdir -p --mode=0755 usr/share/man
#       rm -rf usr/share/doc
#       mkdir -p --mode=0755 usr/share/doc
 popd



touch "$tarFile"

(
        set -x
#       tar --numeric-owner -cf - "$rootfsDir" --transform='s,^./,,' | xz --compress -9 --threads=0 - > "$tarFile"
	pushd "$rootfsDir"
	    tar --numeric-owner -c -f "../$tarFile" --xz --transform='s,^./,,' .
	popd
        ln -s "$tarFile" "./rootfs.tar.xz" 
        #|| :
#        mksquashfs "$rootfsDir" "$sqfsFile" -comp xz
        
)

( set -x; rm -rf "$rootfsDir" )
