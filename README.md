# Deploying an OpenShift Cluster with vGPU on VMware vSphere

> **NOTE:** Currently the procedure is for deploying a Single Node OpenShift (SNO). Multi-node OpenShift clusters with vGPU will be addressed later.

## Requirements

* An [Equinix Metal](https://metal.equinix.com/) account for provisioning a bare metal server with a GPU model [supported by NVIDIA vGPU for vSphere 7.0](https://docs.nvidia.com/grid/latest/product-support-matrix/index.html#abstract__vmware-vsphere).
* An existing Equinix Metal project where you can provision servers.
* An NVIDIA account with access to the [vGPU packages for vSphere 7.0](https://ui.licensing.nvidia.com/software).
* A VMware account with access to ESXi and vSphere installation packages, e.g. the [evaluation versions](https://customerconnect.vmware.com/group/vmware/evalcenter) (make sure you're logged in at [VMware Customer Connect](https://customerconnect.vmware.com/dashboard) before accessing the link).
* A Red Hat account with access to [assisted installer OpenShift clusters](https://console.redhat.com/openshift/assisted-installer/clusters/~new).

## Steps

1. Prepare the required artifacts in an AWS S3 compatible storage.
2. Provision a bare metal machine that has a [vGPU-compatible NVIDIA GPU](https://docs.nvidia.com/grid/latest/product-support-matrix/index.html#abstract__vmware-vsphere).
3. Install VMware ESXi 7.0 on the bare metal machine.
4. Install and configure the VMware vSphere 7.0 virtual appliance.
5. Install from a vSphere Installation Bundle (VIB), and configure the vGPU host driver for ESXi.
6. Install an OpenShift cluster in vSphere virtual machines.
7. Add a vGPU device to the OpenShift cluster's workers.
8. Deploy the NVIDIA GPU Operator on the OpenShift cluster. The cluster must have access to a vGPU.

For manual steps for deploying OpenShift with vGPU on VMware vSphere, refer to the [OpenShift Container Platform on VMware vSphere with NVIDIA vGPUs](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/openshift/nvaie-with-ocp.html#openshift-container-platform-on-vmware-vsphere-with-nvidia-vgpus) guide.


## VMware vSphere 7.0 on Equinix Metal

The Equinix Metal server plan that has a vGPU-compatible GPU is [g2.large.x86](https://metal.equinix.com/developers/docs/hardware/legacy-servers/#g2largex86), but ESXi 7.0 isn't offered for it. The solution is to provision a machine with ESXi 6.5 and then upgrade to ESXi 7.0, as explained in detail in [Using VMware ESXi on Equinix Metal](https://metal.equinix.com/developers/guides/vmware-esxi/) and [Setting up Multi-node vSphere Cluster with VSan Support on Equinix Metal](https://metal.equinix.com/developers/guides/vmware/), respectively.

## Required VMware & NVIDIA Artifacts

During installation, the scripts will need access to the following artifacts stored in an S3-compatible storage.

* An ISO of the VMware vCenter Virtual Appliance, e.g. _VMware-VCSA-all-7.0.3-19234570.iso_.
* The NVIDIA vGPU host driver for VMware ESXi 7.0, extracted from the NVIDIA AI Enterprise Software for VMware vSphere 7.0 package, e.g. _NVD-AIE_510.47.03-1OEM.702.0.0.17630552_19298122.zip_.

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
    equinix_metal_hostname_prefix: <prefix> # to identify the vSphere deployment in a shared project, e.g. your username

    # OpenShift
    ocm_offline_token: <offline_token>
    pull_secret_path: <path/to/pull_secret>
    openshift_base_domain: <base_dns_domain>
    ssh_key: <path/to/public_ssh_key>

    # NVIDIA
    # from https://ngc.nvidia.com/setup/api-key
    ngc_api_key: <ngc_api_key>
    ngc_email: <your@email.com>
    nls_client_token: <nls_client_license_token> # see https://docs.nvidia.com/license-system/latest/pdf/nvidia-license-system-user-guide.pdf
    ```

    Other variables that can be changed are declared in the playbooks.

## Selecting a vGPU Type (Profile)

>**IMPORTANT**: In order for the GPU Operator to work correctly with a vGPU, a supported vGPU type must be selected in the `vgpu_profile` variable.

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

## Running

> **WARNING:** Before running the Ansible playbook, make sure you do not have an old cluster named `<cluster_name>` (_sno-vmware_ by default) in your [Assisted Clusters](https://console.redhat.com/openshift/assisted-installer/clusters).


```sh
ansible-playbook main.yml -e "@path/to/vars.yml"
```

Take a note of the parameters for connecting to the VMware vSphere cluster, OpenShift node(s), etc. For example:

```json
{
    "msg": [
        "Bastion host: 147.28.143.219",
        "vCenter IP: 147.28.142.42",
        "vCenter credentials in tmp/vcenter.txt",
    ]
}
```

## Troubleshooting

### Terraform

If the Terraform task has failed, but you don't have enough information to understand the problem, try re-running the Terraform script manually (it's idempotent).
Review the generated _tmp/terraform.tfvars_ file, change to the _tmp/equinix\_metal_ directory, then run `terraform apply -var-file=../terraform.tfvars`.

Full Terraform output is also dumped into _tmp/terraform.stdout.[.timestamp]_ and _tmp/terraform.stderr[.timestamp]_.

### Connecting to the Router/Bastion

The bastion host IP address is printed out by Ansible after it becomes available. You will already have the right SSH key for a passwordless access.

`ssh root@<bastion>`

### Connecting to ESXi hosts

From the bastion host, you can reach the ESXi host(s). Assuming you haven't change the private subnet 172.16.0.0/24, the IP address of the first (and only, for SNO) ESXi host is _172.16.0.4_ (i.e. _subnet + 3_):

`ssh -i ~/.ssh/esxi_key root@172.16.0.4`

Useful commands:

* List all VMs: `vim-cmd vmsvc/getallvms`
* Get the power state of a VM: `vim-cmd vmsvc/power.getstate <vm_id>`

## Connecting to vCenter

Connect through HTTPS to the vCenter IP address printed out by the Ansible script, accept the self-signed CA certificate.
Use the vCenter credentials saved to _tmp/vcenter.txt_ &mdash; a username (usually _Administrator@vsphere.local_) and a randomly generated password .

## Connecting to OpenShift

Use a _kubeconfig_ file with the assisted installer cluster ID as the file extension, created in the _tmp_ directory. For instance, _tmp/kubeconfig.41610064-a819-4e66-9bb5-7c938e96ca38_. In addition, a _tmp/kubeadmin-password_ file will contain the password for accessing the cluster console with username _kubeadmin_ (e.g._tmp/kubeadmin-password.41610064-a819-4e66-9bb5-7c938e96ca38_).

In order to SSH to the SNO host, use `ssh core@<sno_host>`. Provide an SSH private key using `-i /path/to/key` if needed.

## Cleanup

In most cases it should be enough to:

1. Destroy the provisioned Equinix Metal machines

```sh
terraform destroy --var-file=../tmp/terraform.tfvars
```

2. Delete the SNO cluster from the [Red Hat Cloud Console](https://console.redhat.com/openshift/assisted-installer/clusters/)

You can also clean up automatically by running:

```sh
ansible-playbook destroy.yml -e "@path/to/vars.yml"
```

Terraform destroy logs will be saved in _tmp/terraform-destroy.stdout[.timestamp]_ and _tmp/terraform-destroy.stderr[.timestamp]_.