# ZCU104 + DPU + Resnet18

This repository do the following things:
+ Create ZCU104 + DPU IP platform in Vivado (HW)
+ Build Petalinux based on ZCU104 .bsp and .xsa exported from Vivado (OS)
+ Use Vitis-Ai tool to inspect, quantize and compile the model (SW)
+ Modify the .cpp file to perform Resnet18 on ZCU104

This repository do the following things:
**N.B.** The tools used in this repository are (It is highly not recommended to use the version later then 2023 since it may cause error in Petalinux build flow. If you insist the version after 2023, then do not use this repository):
+ Ubuntu 20.04.6 LTS with R9-9950X + 64GB RAM
+ Vivado 2022.2
+ Petalinux 2022.2
+ Vitis-AI 3.0

## 1. Create ZCU104 + DPU IP platform in Vivado
### 1.1 Download DPU IP
The DPU used for ZCU104 is. Since DPU IP is not pre-integrated into the Vivado, one should download it first via this [link](https://www.xilinx.com/bin/public/openDownload?filename=DPUCZDX8G_VAI_v3.0.tar.gz). The structre of the DPU file should be as follows:
```
DPUCZDX8G_VAI_v3.0
├── app
│   ├── dpu_sw_optimize.tar.gz
│   ├── model
│   └── samples
├── config_gui.cfg
├── description.json
├── dpu_ip
│   ├── DPUCZDX8G_v4_1_0
│   └── Vitis
├── prj
│   ├── Vitis
│   └── Vivado
└── README.md
```
(I have downloaded the dpu_ip to the hw folder, you can use it directly as well).

### 1.2 Create Vivado block diagram
Go into the zcu104_dpu_resnet18/hw and open the terminal, do:
```
source <Vivado install path>/Vivado/2022.2/settings64.sh
vivado -source system.tcl
```

After executing the script, open the block diagram and the Vivado IP block design will be shown as follow:

![img](/img/bd_dpu.png)

+ Go to **Source** -> **Design source** -> right click **system** and choose **Create HDL Wrapper**. Choose **Let Vivado manage wrapper** and **auto-update** in the Create HDL Wrapper window
+ Generate pre-synth design: Select **Generate Block Design** from Flow Navigator. Select Synthesis Options to **Global**, it will skip IP synthesis during generation. Click Generate.
+ Change implamentation strategy from Default to **Performance_ExplorePostRoutPhysOpt** strategy. Navigate to Post-Route Phys Opt Design, expand -directive option and choose **AggressiveExplore**. The timing issue happened when using Default implementation strategy.
+ Then click on “**Generate Bitstream**” (Note: If the user gets any pop-up with “No implementation Results available”. Click “Yes”. Then, if any pop-up comes up with “Launch runs”, Click "OK”.)

After the bitstream is generated
+ Go to **File** -> **Export** -> **Export Hardware**
+ In the Export Hardware window select "Fixed -> **Include bitstream**" and click "OK". Then the .xsa file should be created.

Alternatively you can execute the generation automatically by:
```
source auto_generate_bitstream.tcl
```
in Tcl console.

## 2. Build Petalinux based on ZCU104 .bsp and .xsa exported from Vivado
In this part, the Petalinux will be built. And pay attention that from now on, everything should be done on your Ubuntu (No Windows!!!). If you haven't install the petalinux yet, you can refer to the official [UG1144](https://docs.amd.com/r/2022.2-English/ug1144-petalinux-tools-reference-guide/Overview) for installation. Also download the [BSP](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/embedded-design-tools/archive.html) for ZCU104 along with the Petalinux .run.
### 2.1 Create Petalinux project
In this part, the Petalinux project will be created.
+ Set Petalinux environment:
```
source <path/to/petalinux-installer>/settings.sh
```

+ Create petalinux project from ZCU104 BSP. We will use the official ZCU104 BSP as basic and do some configuration to it:
```
petalinux-create -t project -s <name of zcu104 bsp>.bsp
```

+ Import the hardware description with by giving the path of the directory containing the .xsa file as follows:
```
cd xilinx-zcu104-trd
petalinux-config --get-hw-description=<path to your .xsa>
```

### 2.2 Customize RootFS, Kernel, Device Tree and U-boot
For this part, please refer to the official ZCU102 flow in this [link](https://github.com/Xilinx/Vitis-AI/blob/3.0/dpu/ref_design_docs/README_DPUCZ_Vivado_sw.md). But please pay attention that:
+ Do not exclude **zocl** and **xrt** packages
+ Comment out every configuration that contains "**vcu**" (since ZCU104 has no vcu) in <your_petalinux_project_dir>/project-spec/meta-user/conf/user-rootfsconfig
+ Enable OpenSSH and disable dropbear Dropbear is the default SSH tool in Vitis Base Embedded Platform (since we need to transfer our Vitis AI apps to the board). Since Vitis-AI applications may use remote display feature to show machine learning results, using OpenSSH can improve the display experience.

    + a) Still in the RootFS configuration window, go to root directory by select Exit once.
    + b) Go to Image Features.
    + c) Disable ssh-server-dropbear and enable ssh-server-openssh and click Exit.
    + d) Go to Filesystem Packages-> misc->packagegroup-core-ssh-dropbear and disable packagegroup-core-ssh-dropbear. Go to Filesystem Packages level by Exit twice.
    + e) Go to console -> network -> openssh and enable openssh, openssh-sftp-server, openssh-sshd, openssh-scp. Go to root level by Exit four times.

After everything is configured and the img is generated, use [balenaEtcher](https://etcher.balena.io/) to burn the img into the sd card and boot the ZCU104.

Alternatively you can run
```
./helper_build_bsp.sh
```
in terminal to execute the build of Petalinux automatically.
There is no need to go very deep into which packages should be appended and why they should be appended. This is just a bridge between your Vitis AI model inference and your DPU.

## 3. Use Vitis-AI tool to inspect, quantize and compile the model
This part please refer to sw/README.md

## 4. Modify the .cpp file to perform Resnet18 on ZCU104