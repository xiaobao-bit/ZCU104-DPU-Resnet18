#!/bin/bash

set -e
workdir=$(readlink -f $(dirname $0))
xsadir=${workdir}/../hw
recipesdir=${workdir}/meta-vitis/
plnxdir=${workdir}/xilinx-zcu104-dpu-petalinux
zcu104_bsp=${workdir}/xilinx-zcu104-v2022.2-10141622.bsp

PKG_OPTIONAL=( \
	resize-part \
	dnf \
	nfs-utils \
	cmake \
	opencl-headers \
	opencl-clhpp-dev \
	packagegroup-petalinux-x11 \
	packagegroup-petalinux-opencv \
	packagegroup-petalinux-gstreamer \
	packagegroup-petalinux-self-hosted \
	vitis-ai-library \
	vitis-ai-library-dev \
	vitis-ai-library-dbg \
	openssh\
	openssh-scp\
	openssh-sshd\
	openssh-sftp-server\
)

echo_info() {
	echo -e "\033[42;30mINFO: $@\033[0m"
}

echo_error() {
	echo -e "\033[41;30mERROR: $@\033[0m"
}

create_proj() {
	#set petalinux tools
	if [ "$PETALINUX" == "" ]; then
		echo_error "Please set petalinux tools before start"
		exit 1
	fi

	cd ${workdir}
	# check xsa 
	if [ ! -e "$zcu104_bsp" ]; then
		echo_error "Please download bsp"
		exit 1
	fi

	if [ "3f78071cd31a8d4e2f9f8eaf6717256c" != "$(md5sum $zcu104_bsp | cut -d' ' -f1)" ]; then
		echo_error "bsp check sum incorrect"
		exit 1
	fi

	# create and config a petalinux project, and rename project with ${plnxdir}
	if [ -d "${plnxdir}" ];then
		echo_info "deleting old petalinux project..."
		rm -rf ${plnxdir}
	fi

	petalinux-create -t project -s $zcu104_bsp  && sync
	if [ -d "${workdir}/xilinx-zcu104-2022.2" ];then
		mv ${workdir}/xilinx-zcu104-2022.2   ${plnxdir}
	else
		echo_error "petalinux create project failed"
		exit 1
	fi

	if [ -f ${xsadir}/system.xsa ]; then
		cd ${plnxdir} && petalinux-config --get-hw-description=${xsadir} --silentconfig
	else
		echo_error "No XSA files found under path ${xsadir}"
		exit 1
	fi
}

customize_proj()
{
	# 2.2.1 enable dpu driver & linux-xlnx master
	echo_info "> enable dpu driver"
	cp -arf ${recipesdir}/recipes-kernel ${plnxdir}/project-spec/meta-user/

	# # 2.2.2 disable zocl & xrt
	# echo_info "> disable zocl & xrt for vivado flow"
	# sed -i 's/CONFIG_xrt=y/\# CONFIG_xrt is not set/' ${plnxdir}/project-spec/configs/rootfs_config
	# sed -i 's/CONFIG_xrt-dev=y/\# CONFIG_xrt-dev is not set/' ${plnxdir}/project-spec/configs/rootfs_config
	# sed -i 's/CONFIG_zocl=y/\# CONFIG_zocl is not set/' ${plnxdir}/project-spec/configs/rootfs_config

	# 2.2.3 install recommended packages to rootfs
	echo_info "> add packages installed to rootfs"
	# cp -arf ${recipesdir}/recipes-apps ${plnxdir}/project-spec/meta-user/
	# cp -arf ${recipesdir}/recipes-core ${plnxdir}/project-spec/meta-user/
	cp -arf ${recipesdir}/recipes-vitis-ai ${plnxdir}/project-spec/meta-user/

	for ((item=0; item<${#PKG_OPTIONAL[@]}; item++))
	do
		echo "IMAGE_INSTALL:append=\" ${PKG_OPTIONAL[item]} \""   >> ${plnxdir}/project-spec/meta-user/conf/petalinuxbsp.conf
	done
	
	echo_info "> setting openssh connection"
	sed -i 's/CONFIG_imagefeature-ssh-server-dropbear=y/\# CONFIG_imagefeature-ssh-server-dropbear is not set/' ${plnxdir}/project-spec/configs/rootfs_config
	sed -i '/# CONFIG_imagefeature-ssh-server-openssh is not set/c CONFIG_imagefeature-ssh-server-openssh\=y' ${plnxdir}/project-spec/configs/rootfs_config
	echo_info "> Force disable dropbear completely"
	sed -i '/packagegroup-core-ssh-dropbear/d' ${plnxdir}/project-spec/meta-user/conf/petalinuxbsp.conf || true
	sed -i '/packagegroup-core-ssh-dropbear/d' ${plnxdir}/project-spec/meta-user/conf/user-rootfsconfig || true

	echo "# CONFIG_packagegroup-core-ssh-dropbear is not set" >> ${plnxdir}/project-spec/configs/rootfs_config
	echo "# CONFIG_ssh-server-dropbear is not set" >> ${plnxdir}/project-spec/configs/rootfs_config


	# 2.2.3 enable package management and auto login
	echo_info "> enable auto login and package management"
	sed -i '/# CONFIG_imagefeature-package-management is not set/c CONFIG_imagefeature-package-management\=y' ${plnxdir}/project-spec/configs/rootfs_config
	sed -i '/# CONFIG_imagefeature-debug-tweaks is not set/c CONFIG_imagefeature-debug-tweaks\=y'		${plnxdir}/project-spec/configs/rootfs_config
	sed -i '/# CONFIG_auto-login is not set/c CONFIG_auto-login\=y' ${plnxdir}/project-spec/configs/rootfs_config

	# 2.2.4 set rootfs type EXT4
	echo_info "> set rootfs format to EXT4"
	sed -i 's|CONFIG_SUBSYSTEM_ROOTFS_INITRD=y|# CONFIG_SUBSYSTEM_ROOTFS_INITRD is not set|' ${plnxdir}/project-spec/configs/config
	sed -i 's|# CONFIG_SUBSYSTEM_ROOTFS_EXT4 is not set|CONFIG_SUBSYSTEM_ROOTFS_EXT4=y|' ${plnxdir}/project-spec/configs/config
	sed -i '/CONFIG_SUBSYSTEM_INITRD_RAMDISK_LOADADDR=/d' ${plnxdir}/project-spec/configs/config
	echo 'CONFIG_SUBSYSTEM_SDROOT_DEV="/dev/mmcblk0p2"' >> ${plnxdir}/project-spec/configs/config

	# set hostname to xilinx-zcu104-trd
	sed -i '/CONFIG_SUBSYSTEM_HOSTNAME=/c CONFIG_SUBSYSTEM_HOSTNAME\="xilinx-zcu104-trd"' ${plnxdir}/project-spec/configs/config
}

build_proj() {
	cd ${plnxdir}
	petalinux-config -c kernel --silentconfig
	petalinux-config -c rootfs --silentconfig
	petalinux-build
	cd ${plnxdir}/images/linux
	petalinux-package --boot --fsbl zynqmp_fsbl.elf --u-boot u-boot.elf --pmufw pmufw.elf --fpga system.bit --force
	petalinux-package --wic --bootfile "BOOT.BIN boot.scr Image system.dtb" --wic-extra-args "-c gzip"
}

usage() {
	echo "Usage:"
	echo "     ./helper_build_bsp.sh [<xsadir>]"
	echo "     Example: ./helper_build_bsp.sh"
	echo "     Example: ./helper_build_bsp.sh ../hw/prj"
}

main() {
	if [ $# -gt 0 ]; then
		if [ -d "$1" ]; then
			xsadir=$1
		else
			usage; exit
		fi
	fi
	if [ ! -d "$xsadir" ]; then
		echo_error "STOP: xsadir: $xsadir not exit!"; exit 1
	fi
	create_proj
	customize_proj
	build_proj
}

main "$@"
