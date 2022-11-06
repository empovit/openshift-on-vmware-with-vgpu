# Deploying an OpenShift Cluster with vGPU on VMware vSphere

This repository contains Ansible scripts for deploying an OpenShift cluster with NVIDIA vGPU on VMware to Equinix Metal servers. Currently, only Single Node OpenShift (SNO) is supported.

## Requirements

* An [Equinix Metal](https://metal.equinix.com/) account for provisioning a bare metal server with a GPU model [supported by NVIDIA vGPU for vSphere 7.0](https://docs.nvidia.com/grid/latest/product-support-matrix/index.html#abstract__vmware-vsphere).
* An existing Equinix Metal project where you can provision servers.
* An NVIDIA account with access to the [vGPU packages for vSphere 7.0](https://ui.licensing.nvidia.com/software).
* A VMware account with access to ESXi and vSphere installation packages, e.g. the [evaluation versions](https://customerconnect.vmware.com/group/vmware/evalcenter) (make sure you're logged in at [VMware Customer Connect](https://customerconnect.vmware.com/dashboard) before accessing the link).
* A Red Hat account with access to [assisted installer OpenShift clusters](https://console.redhat.com/openshift/assisted-installer/clusters/~new).

## Steps Overview

1. Prepare the required artifacts in an AWS S3 compatible storage.
2. Provision a bare metal machine that has a [vGPU-compatible NVIDIA GPU](https://docs.nvidia.com/grid/latest/product-support-matrix/index.html#abstract__vmware-vsphere).
3. Install VMware ESXi 7.0 on the bare metal machine.
4. Install and configure the VMware vSphere 7.0 virtual appliance.
5. Install from a vSphere Installation Bundle (VIB), and configure the vGPU host driver for ESXi.
6. Install an OpenShift cluster inside vSphere virtual machines.
7. Add a vGPU device to the OpenShift cluster's workers.
8. Deploy the NVIDIA GPU Operator on the OpenShift cluster. The cluster will now have access to the vGPU.

For manual steps for deploying OpenShift with vGPU on VMware vSphere, refer to the [OpenShift Container Platform on VMware vSphere with NVIDIA vGPUs](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/openshift/nvaie-with-ocp.html#openshift-container-platform-on-vmware-vsphere-with-nvidia-vgpus) guide.


## VMware vSphere 7.0 on Equinix Metal

The Equinix Metal server plan that has a vGPU-compatible GPU is [g2.large.x86](https://metal.equinix.com/developers/docs/hardware/legacy-servers/#g2largex86), but ESXi 7.0 isn't available for it out of the box. The solution is to provision a machine with ESXi 6.5 and then upgrade to ESXi 7.0. VMware vSphere installation is explained in detail in [Multi-node vSphere with vSan support](https://metal.equinix.com/developers/guides/vmware/). Information on upgrading ESXi nodes can be found in [Deploy VMware ESXi 6.7 on Packet Bare Metal Servers](https://github.com/empovit/equinix-esxi-upgrade)

## Required VMware & NVIDIA Artifacts

During installation, the scripts will need access to the following artifacts stored in S3-compatible object storage.

* VMware vCenter Virtual Appliance ISO, e.g. _VMware-VCSA-all-7.0.3-19234570.iso_.
* NVIDIA vGPU host driver for VMware ESXi 7.0, e.g. _NVD-AIE_510.47.03-1OEM.702.0.0.17630552\_19298122.zip_. Extract the driver from the NVIDIA AI Enterprise Software for VMware vSphere 7.0 package you have downloaded from NVIDIA Licensing Portal.

In case of a multi-node _*VMware*_ cluster with vSAN, also extract the following files from _vsan-sdk-python.zip_:

* bindings/vsanmgmtObjects.py
* samplecode/vsanapiutils.py

You can store the files in an AWS S3 bucket, or a locally deployed S3 server (e.g. [Minio](https://min.io/download)).

## Setup

1. Install the required Ansible dependencies:

    ```sh
    ansible-galaxy install -r requirements.yml
    ```

2. Obtain an OpenShift offline token from https://console.redhat.com/openshift/token.

3. Download a pull secret file from https://console.redhat.com/openshift/install/pull-secret.

4. Create a YAML file (e.g. _vars.yml_) with the following mandatory parameters:

    ```yaml
    # Object storage
    s3_url: https://s3.amazonaws.com # or http://<minio_ip>:9000 for Minio
    s3_bucket: <bucket_with_artifacts>
    s3_access_key: <access_key>
    s3_secret_key: <secret_key>

    # Equinix Metal
    equinix_metal_api_key: <api_key>
    equinix_metal_project_id: <existing_project_id>

    equinix_metal_hostname_prefix: <prefix> # identify servers in a shared project, e.g. your username and/or OpenShift cluster name

    # OpenShift
    ocm_offline_token: <offline_token>
    pull_secret_path: <path/to/pull_secret>
    openshift_base_domain: <base_dns_domain>

    # NVIDIA
    # from https://ngc.nvidia.com/setup/api-key
    ngc_api_key: <ngc_api_key>
    ngc_email: <your@email.com>
    nls_client_token: <nls_client_license_token> # see https://docs.nvidia.com/license-system/latest/pdf/nvidia-license-system-user-guide.pdf
    ```

    Other variables that can be changed are declared in the playbooks.

## Running

* Specify a `local_temp_dir` that will store the Terraform state, temporary configuration, and credential files.
* Specify an `openshift_cluster_name` for your OpenShift cluster.

```sh
ansible-playbook sno.yml -e "@path/to/vars.yml" -e local_temp_dir="/path/to/temp/dir" -e openshift_cluster_name="<cluster_name>"
```

> **WARNING:** Before running the Ansible playbook, make sure you do not have an old cluster named `<openshift_cluster_name>` in your [Assisted Clusters](https://console.redhat.com/openshift/assisted-installer/clusters).

Take a note of the parameters for connecting to the VMware vSphere cluster, OpenShift node(s), etc. For example:

```json
{
    "msg": [
        "Bastion host: 147.28.143.219",
        "vCenter IP: 147.28.142.42",
        "vCenter credentials in tmp/vcenter.txt",
        "VPN connection details in tmp/vpn.txt"
    ]
}
```

## Private vs Public Networks

By default, the vCenter appliance and OpenShift cluster will be deployed with a public network, which means that they will be accessible on the Internet. Although it might be convenient, this is probably not the best choice from a security point of view. You can deploy the VMs in private networks by setting `use_private_networks=true`, and access vCenter API and the OpenShift cluster only via the bastion host. When using private networks, the OpenShift cluster's _kubeconfig_, credentials and SSH key pair will be saved to a directory on the bastion host.

## Deploying Multiple Setups

It is possible to deploy multiple vSphere clusters, each with its own OpenShift cluster:

1. Set the `local_temp_dir` variable so that the Terraform state and everything related to a new cluster is stored separately in a new directory and does not use an existing directory.

2. Set an `openshift_cluster_name` that does not conflict with an existing assisted OpenShift cluster.

> **WARNING:** You will need to specify the same directory and cluster name when destroying the cluster, otherwise you may destroy another cluster by mistake.

## Cleanup

In most cases it should be enough to:

1. Destroy the provisioned Equinix Metal machines

```sh
terraform destroy --var-file=../tmp/terraform.tfvars
```

2. Delete the SNO cluster from the [Red Hat Cloud Console](https://console.redhat.com/openshift/assisted-installer/clusters/)

You can also clean up automatically by running:

```sh
ansible-playbook destroy.yml -e "@path/to/vars.yml" -e local_temp_dir="/path/to/temp/dir" -e openshift_cluster_name="<cluster_name>"
```

Terraform destroy logs will be saved in _&lt;temp_directory&gt;/terraform-destroy.stdout[.timestamp]_ and _&lt;temp_directory&gt;/terraform-destroy.stderr[.timestamp]_.

## Selecting a vGPU Type (Profile)

> **IMPORTANT**: In order for the GPU Operator to work correctly with a vGPU, a supported vGPU type must be selected in the `vgpu_profile` variable.

For details on vGPU types refer to [Listing Supported vGPU Types](https://docs.nvidia.com/grid/14.0/grid-vgpu-user-guide/index.html#list-supported-vgpu-types).

The list of available vGPU type values can be obtained via the vCenter GUI, or by running `vim-cmd hostsvc/hostconfig | grep -A 20 sharedPassthruGpuTypes` on an ESXi host after configuring the host graphics.

Choose a vGPU type that [supports CUDA](https://docs.nvidia.com/grid/14.0/grid-vgpu-user-guide/index.html#cuda-open-cl-support-vgpu) &mdash; a C- or Q-series vGPU on Tesla V100, which is the GPU offered by the Equinix Metal machine type we use.

On Tesla V100 at the time of this writing:

* grid_v100dx-1b
* grid_v100dx-2b
* grid_v100dx-1b4
* grid_v100dx-2b4
* **grid_v100dx-1q**
* **grid_v100dx-2q**
* **grid_v100dx-4q**
* **grid_v100dx-8q**
* **grid_v100dx-16q**
* **grid_v100dx-32q**
* grid_v100dx-1a
* grid_v100dx-2a
* grid_v100dx-4a
* grid_v100dx-8a
* grid_v100dx-16a
* grid_v100dx-32a
* **grid_v100dx-4c**
* **grid_v100dx-8c**
* **grid_v100dx-16c**
* **grid_v100dx-32c**

## See Also

* [Connecting to setup](docs/connecting.md)
* [Troubleshooting](docs/troubleshooting.md)