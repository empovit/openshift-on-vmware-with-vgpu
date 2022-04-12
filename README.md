# Installing SNO OpenShift on VMware vSphere with vGPU

## Requirements

* A bare metal server with a GPU model [supported by NVIDIA vGPU for vSphere 7.0](https://docs.nvidia.com/grid/latest/product-support-matrix/index.html#abstract__vmware-vsphere). For an [Equinix Metal](https://metal.equinix.com/) server, you will need an Equinix Metal account.
* An NVIDIA account with access to the [vGPU packages for vSphere 7.0](https://ui.licensing.nvidia.com/software).
* A VMware account with access to ESXi and vSphere installation packages, e.g. the [evaluation versions](https://customerconnect.vmware.com/group/vmware/evalcenter).
* A Red Hat account with access to [assisted installer OpenShift clusters](https://console.redhat.com/openshift/assisted-installer/clusters/~new).

## Steps

1. If needed, provision a bare metal machine with a compatible NVIDIA GPU.
2. Install VMware ESXi 7.0 on the bare metal machine.
3. Install and configure a VMware vSphere 7.0 virtual appliance.
4. Install and configure the vGPU host driver for ESXi using a vSphere Installation Bundle (VIB).
5. Install an SNO cluster on a vSphere virtual machine.
6. Deploy the GPU operator on the SNO cluster. The cluster must have access to a vGPU.
