
# Connecting to a Setup

## VPN Connection

A [L2TP/IPsec VPN](https://metal.equinix.com/developers/guides/vmware/#connect-to-the-environment) will be automatically set up on the bastion host. This VPN can be used to access ESXi hosts, as well as vCenter and OpenShift from your local computer if they were deployed to private networks.

In case of private networks, you can also set up an SSH tunnel or a reverse proxy on the bastion server to connect to the vCenter and/or OpenShift instance from your local computer. However, those methods aren't implemented by this repository.

Alternatively, it is possible to SSH to the bastion server and issue vCenter or OpenShift commands from there (see below).

## Connecting to the Router/Bastion

The bastion host's IP address is printed out by Ansible after it becomes available. You will already have the right SSH key for a password-less access in your _~./ssh_ directory.

```
ssh root@<bastion>
```

## Connecting to ESXi hosts

From the bastion host, you can reach the ESXi host(s). Assuming you haven't change the private subnet _172.16.0.0/24_, the IP address of the first ESXi host is _172.16.0.4_ (i.e. _subnet + 3_):

```
ssh -i ~/.ssh/esxi_key root@172.16.0.4
```

If you're using VPN to access the ESXi hosts, you will need to copy the SSH key over to your local machine.

Useful commands:

* List all VMs

  ```
  vim-cmd vmsvc/getallvms
  ```

* Get the power state of a VM

  ```
  vim-cmd vmsvc/power.getstate <vm_id>
  ```

## Connecting to vCenter

Connect with a browser through HTTPS to the vCenter IP address printed out by the Ansible script and accept the self-signed CA certificate. Use the vCenter credentials saved to _&lt;temp_directory&gt;/vcenter.txt_ &mdash; a username (usually _Administrator@vsphere.local_) and a randomly generated password.

If you prefer the command line, one of the methods is using the `govc` utility. It can be ran from the bastion host or from the local machine (when deploying with public IP addresses, or using VPN).

1. Install `govc`

```
curl -L -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz" | tar -C /usr/local/bin -xvzf - govc
```

2. Set connection parameters &mdash; IP address, username, password and CA certificate (or ignore the certificate). Example:

```
export GOVC_URL='https://172.16.3.2'
export GOVC_USERNAME='Administrator@vsphere.local'
export GOVC_PASSWORD='<password>'
export GOVC_INSECURE=true
```

Useful govc commands

* Viewing the inventory, including VMs:

  ```
  govc tree
  ```

* Viewing the devices of a VM:

  ```
  govc device.info -vm my-cluster-sno_vm
  ```

## Connecting to OpenShift

Use a _kubeconfig_ file that has the assisted installer cluster ID for its file extension, created in the temp directory. For instance, _&lt;temp_directory&gt;/kubeconfig.41610064-a819-4e66-9bb5-7c938e96ca38_. In addition, a _&lt;temp_directory&gt;/kubeadmin-password_ file will contain the password for accessing the cluster console with username _kubeadmin_ (e.g._tmp/kubeadmin-password.41610064-a819-4e66-9bb5-7c938e96ca38_).

The files will be saved into the local temp directory in case of public networks, and to a directory on the bastion server in case of private networks. When using VPN, you will need to copy the _kubeconfig_ file to your local machine.

In order to SSH to an OpenShift node, use `ssh -i /path/to/key core@<openshift_node>`. The SSH key be located in the local temp directory in case of public network, and in the remote (bastion) temp directory in case of private networks. Its full path will be printed to the console by Ansible.