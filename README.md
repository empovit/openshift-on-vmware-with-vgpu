# Installing SNO OpenShift on VMware vSphere with vGPU

## Requirements

* An [Equinix Metal](https://metal.equinix.com/) account for provisioning a bare metal server with a GPU model [supported by NVIDIA vGPU for vSphere 7.0](https://docs.nvidia.com/grid/latest/product-support-matrix/index.html#abstract__vmware-vsphere).
* An existing Equinix Metal project where you can provision servers.
* An NVIDIA account with access to the [vGPU packages for vSphere 7.0](https://ui.licensing.nvidia.com/software).
* A VMware account with access to ESXi and vSphere installation packages, e.g. the [evaluation versions](https://customerconnect.vmware.com/group/vmware/evalcenter).
* A Red Hat account with access to [assisted installer OpenShift clusters](https://console.redhat.com/openshift/assisted-installer/clusters/~new).

## Steps

1. Prepare the required artifacts in an AWS S3 compatible storage (e.g. Minio)
2. Provision a bare metal machine with a compatible NVIDIA GPU.
3. Install VMware ESXi 7.0 on the bare metal machine.
4. Install and configure a VMware vSphere 7.0 virtual appliance.
5. Install and configure the vGPU host driver for ESXi using a vSphere Installation Bundle (VIB).
6. Install an SNO cluster on a vSphere virtual machine.
7. Deploy the GPU operator on the SNO cluster. The cluster must have access to a vGPU.

## VMware vSphere 7.0 on Equinix Metal

The Equinix Metal server plan that has a vGPU-compatible GPU is [g2.large.x86](https://metal.equinix.com/developers/docs/servers/server-specs/#g2largex86), but ESXi 7.0 isn't offered for it. The solution is to provision a machine with ESXi 6.5 and then upgrade to ESXi 7.0.

Based on https://github.com/enkelprifti98/packet-esxi-6-7 and https://github.com/equinix/terraform-metal-vsphere, explained in detail in [Using VMware ESXi on Equinix Metal](https://metal.equinix.com/developers/guides/vmware-esxi/) and [Setting up Multi-node vSphere Cluster with VSan Support on Equinix Metal](https://metal.equinix.com/developers/guides/vmware/), respectively.

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
    s3_url: https://s3.amazonaws.com # or http://<minio_ip>:9000 for Minio
    s3_bucket: <bucket_with_artifacts>
    s3_access_key: <access_key>
    s3_secret_key: <secret_key>

    equinix_metal_api_key: <api_key>
    equinix_metal_project_id: <existing_project_id>
    equinix_metal_hostname_prefix: <prefix> # to identify the vSphere deployment in a shared project, e.g. your username

    ocm_offline_token: <offline_token>
    pull_secret_path: <path/to/pull_secret>
    openshift_base_domain: <base_dns_domain>
    ssh_key: <path/to/public_ssh_key>
    ```

    Other variables that can be changed are declared in the playbooks.

## Running

ansible-playbook main.yml -e "@path/to/vars.yml"
