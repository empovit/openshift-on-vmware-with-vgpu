# Troubleshooting

An OpenShift with vGPU setup has lost of moving parts. Error messages printed by Ansible are usually  easy to understand. However, troubleshooting the Terraform part of the automation scripts can be more challenging.

### Terraform

If the Terraform task is failing, but you don't have enough information to understand the problem, try re-running the Terraform script manually (it's idempotent).
First, review the generated _&lt;temp_directory&gt;/terraform.tfvars_ file, change to the _&lt;temp_directory&gt;/equinix\_metal_ directory, then run `terraform apply -var-file=../terraform.tfvars`.

Full Terraform output is also dumped into _&lt;temp_directory&gt;/terraform.stdout.[.timestamp]_ and _&lt;temp_directory&gt;/terraform.stderr[.timestamp]_.

If you are seeing a dependency incompatibility error similar to the one below, most likely upgrading the ESXi version has silently failed for some reason:

```
[DependencyError]
...
VIB NVD-XXXXXXX requires vmkapi_2_2_0_0, but the requirement cannot be satisfied within the ImageProfile
```

Make sure that `update_esxi` is set to `true` in the generated Terraform variables file, then re-run Terraform. Verify that the ESXi version is `VMware ESXi 7.0.x build-xxxx` by running the following command on the ESXi host:

```
vmware -v
```

### Other Components

See [Connecting to setup](connecting.md) to learn how to connect to the bastion server, ESXi host, vCenter, and OpenShift console of a setup.