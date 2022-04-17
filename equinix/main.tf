# Equinix Metal API token
provider "metal" {
  auth_token = var.auth_token
}

# Generate the de-duplication part of an SSH key name
resource "random_string" "ssh_unique" {
  length  = 5
  special = false
  upper   = false
}

locals {
  ssh_user               = "root"

  # Generate a unique SSH key name out of the project name and a random string
  project_name_sanitized = replace(var.project_name, "/[ ]/", "_")
  ssh_key_name = format("%s-%s-key", local.project_name_sanitized, random_string.ssh_unique.result)

  # List the specified GCS key file in current working directory or empty filename
  gcs_keys_cwd = flatten([[fileset(path.cwd, var.gcs_key_name)], ""])

  # Find the first GCS key path that's not empty, i.e. was either explicitly specified or found.
  # If no files were found, take the module's path. Note that the relative path is deprecated.
  gcs_key_path = coalesce(abspath(var.path_to_gcs_key), path.module, var.relative_path_to_gcs_key, local.gcs_keys_cwd[0])

  # Reference:
  # https://www.terraform.io/language/functions/flatten
  # https://www.terraform.io/language/functions/fileset
  # https://www.terraform.io/language/expressions/references#path-cwd
  # https://www.terraform.io/language/functions/coalesce
}

# Create a metal project or use an existing one
resource "metal_project" "new_project" {
  count           = var.create_project ? 1 : 0
  name            = var.project_name
  organization_id = var.organization_id
}

# Remember the ID of a newely created project (if requested), or take the ID given by the user
locals {
  depends_on = [metal_project.new_project]
  count      = var.create_project ? 1 : 0
  project_id = var.create_project ? metal_project.new_project[0].id : var.project_id
}

# Generate a secure private key
# https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key
resource "tls_private_key" "ssh_key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# TODO: Allow re-using an existing key pair instead of generating a new one every time

# Manage the unique user SSH key that will be injected in the project's machines.
# Must explicitely depend on the project
# https://registry.terraform.io/providers/equinix/metal/latest/docs/resources/ssh_key
resource "metal_ssh_key" "ssh_pub_key" {
  depends_on = [metal_project.new_project]
  name       = local.ssh_key_name
  public_key = chomp(tls_private_key.ssh_key_pair.public_key_openssh)
}

# Save the private SSH key to a local file
resource "local_file" "project_private_key_pem" {
  content         = chomp(tls_private_key.ssh_key_pair.private_key_pem)
  filename        = pathexpand("~/.ssh/${local.ssh_key_name}")
  file_permission = "0600"

  # Back up the private SSH key associated with the project. Why?
  provisioner "local-exec" {
    command = "cp ~/.ssh/${local.ssh_key_name} ~/.ssh/${local.ssh_key_name}.bak"
  }
}

# Reserve blocks of public IPs, a block per user-requested subned
# https://registry.terraform.io/providers/equinix/metal/latest/docs/resources/reserved_ip_block
resource "metal_reserved_ip_block" "ip_blocks" {
  count      = length(var.public_subnets)
  project_id = local.project_id
  facility   = var.facility == "" ? null : var.facility
  metro      = var.metro == "" ? null : var.metro
  quantity   = element(var.public_subnets.*.ip_count, count.index)
}

# Reserve blocks of 8 IP addresses per ESXi host (for VMs?)
resource "metal_reserved_ip_block" "esx_ip_blocks" {
  count      = var.esxi_host_count
  project_id = local.project_id
  facility   = var.facility == "" ? null : var.facility
  metro      = var.metro == "" ? null : var.metro
  quantity   = 8
}

# Create private VLANs, by default these are: a private VM network (management), vMotion, and vSAN
# https://registry.terraform.io/providers/equinix/metal/latest/docs/resources/vlan
resource "metal_vlan" "private_vlans" {
  count       = length(var.private_subnets)
  facility    = var.facility == "" ? null : var.facility
  metro       = var.metro == "" ? null : var.metro
  project_id  = local.project_id
  description = jsonencode(element(var.private_subnets.*.name, count.index))
}

# Create public VLANs, by default this is a public VM network
resource "metal_vlan" "public_vlans" {
  count       = length(var.public_subnets)
  facility    = var.facility == "" ? null : var.facility
  metro       = var.metro == "" ? null : var.metro
  project_id  = local.project_id
  description = jsonencode(element(var.public_subnets.*.name, count.index))
}

# Create a router(?), by default it's an "c3.small.x86" Ubuntu machine.
resource "metal_device" "router" {
  depends_on              = [metal_ssh_key.ssh_pub_key]
  hostname                = var.router_hostname
  plan                    = var.router_size
  facilities              = var.facility == "" ? null : [var.facility]
  metro                   = var.metro == "" ? null : var.metro
  operating_system        = var.router_os
  billing_cycle           = var.billing_cycle
  project_id              = local.project_id
  hardware_reservation_id = lookup(var.reservations, var.router_hostname, "")
}

# Equinix Metal facility datastore. Find out the facility the router is deployed in,
# when the user specified only a metro, but not a particular facility
# https://registry.terraform.io/providers/equinix/metal/latest/docs/data-sources/facility
data "metal_facility" "facility" {
  code = metal_device.router.deployed_facility
}

# Find out if the facility is an IBX (International Business Exchange™) one
locals {
  hybrid_bonded_router = contains(data.metal_facility.facility.features, "ibx") ? true : false
}

# A network port on the router. In an IBX facility, that will be the bonded interface, otherwise eth1
# https://metal.equinix.com/developers/docs/layer2-networking/overview/
# https://registry.terraform.io/providers/equinix/metal/latest/docs/resources/port
resource "metal_port" "router" {
  bonded   = local.hybrid_bonded_router
  port_id  = [for p in metal_device.router.ports : p.id if p.name == (local.hybrid_bonded_router ? "bond0" : "eth1")][0]
  vlan_ids = concat(metal_vlan.private_vlans.*.id, metal_vlan.public_vlans.*.id)

  # A VLAN can't be deleted when there are ports connected to it.
  # If the device is deleted without first disconnecting it from VLANs,
  # we won't be able to detach ports properly and the VLAN
  # delete will fail until the device instance is completely
  # deleted. This option will reset the port to its default setting, meaning 
  # a bond port will be converted to Layer3 without VLANs attached, and eth ports 
  # will be bonded without a native VLAN and VLANs attached
  reset_on_delete = true
}

# Assign the ESXi subnet to the router device
# https://registry.terraform.io/providers/equinix/metal/latest/docs/resources/ip_attachment
resource "metal_ip_attachment" "block_assignment" {
  depends_on    = [metal_port.router]
  count         = length(metal_reserved_ip_block.ip_blocks)
  device_id     = metal_device.router.id
  cidr_notation = element(metal_reserved_ip_block.ip_blocks.*.cidr_notation, count.index)
}

# Create ESXi hosts
resource "metal_device" "esxi_hosts" {
  depends_on              = [metal_ssh_key.ssh_pub_key]
  count                   = var.esxi_host_count
  hostname                = format("%s%02d", var.esxi_hostname, count.index + 1)
  plan                    = var.esxi_size
  facilities              = var.facility == "" ? null : [var.facility]
  metro                   = var.metro == "" ? null : var.metro
  operating_system        = var.vmware_os
  billing_cycle           = var.billing_cycle
  project_id              = local.project_id
  hardware_reservation_id = lookup(var.reservations, format("%s%02d", var.esxi_hostname, count.index + 1), "")

  # Assign a public IPv4 address from the reserved block
  ip_address {
    type            = "public_ipv4"
    cidr            = 29
    reservation_ids = [element(metal_reserved_ip_block.esx_ip_blocks.*.id, count.index)]
  }

  # Assing a private IPv4 address
  ip_address {
    type = "private_ipv4"
  }

  # Assign a public IPv6 address
  ip_address {
    type = "public_ipv6"
  }
}

# Wait for the post provision reboot process to complete before updating ESXi
resource "null_resource" "reboot_pre_upgrade" {

  depends_on = [metal_device.esxi_hosts]
  count      = var.update_esxi ? 1 : 0

  provisioner "local-exec" {
    command = "sleep 250"
  }
}

# Generate an ESXi version update script file
data "template_file" "upgrade_script" {
  count    = var.update_esxi ? length(metal_device.esxi_hosts) : 0
  template = "${file("${path.module}/templates/update_esxi.sh.tpl")}"
  vars = {
    esxi_update_filename = "${var.esxi_update_filename}"
  }
}

# Run the ESXi update script file in each server.
# If you make changes to the shell script, you need to update the sed command line number to get rid of te { at the end of the file which gets created by Terraform for some reason.
resource "null_resource" "upgrade_nodes" {

  depends_on  = [null_resource.reboot_pre_upgrade]
  count       = var.update_esxi ? length(metal_device.esxi_hosts) : 0

  connection {
    user        = local.ssh_user
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
    host        = "${element(metal_device.esxi_hosts.*.access_public_ipv4, count.index)}"
  }

  provisioner "file" {
    content     = "${element(data.template_file.upgrade_script.*.rendered, count.index)}}"
    destination = "/tmp/update_esxi.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i '27d' /tmp/update_esxi.sh",
      "echo 'Running update script on remote host.'",
      "chmod +x /tmp/update_esxi.sh",
      "/tmp/update_esxi.sh"
    ]
  }
}

# Wait for the post provision reboot process to complete before updating ESXi
resource "null_resource" "reboot_post_upgrade" {

  depends_on = [null_resource.upgrade_nodes]
  count      = var.update_esxi ? 1 : 0

  provisioner "local-exec" {
    command = "sleep 250"
  }
}

# Network ports on the ESXi hosts. The eth1 will be taken out of the bond0, and connected to the VLANs - private & public
resource "metal_port" "esxi_hosts" {
  depends_on  = [null_resource.reboot_post_upgrade]
  count       = length(metal_device.esxi_hosts)
  bonded      = false
  port_id     = [for p in metal_device.esxi_hosts[count.index].ports : p.id if p.name == "eth1"][0]
  vlan_ids    = concat(metal_vlan.private_vlans.*.id, metal_vlan.public_vlans.*.id)

  reset_on_delete = true

  lifecycle {
    # vlan_ids will move to the bond0 port during the ssh provisioning conversion to L2-Bonded mode
    ignore_changes = [vlan_ids]
  }
}

# SSH to the router's public IPv4 address and create remote files, populating them with user-assigned and TF-generated values
# * $HOME/bootstrap/vars.py
# * $HOME/bootstrap/pre_reqs.py
# Then, remotely execute `$HOME/bootstrap/pre_reqs.py`
# https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource
resource "null_resource" "run_pre_reqs" {
  connection {
    type        = "ssh"
    user        = local.ssh_user
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
    host        = metal_device.router.access_public_ipv4
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p $HOME/bootstrap/"]
  }

  provisioner "file" {
    content = templatefile("${path.module}/templates/vars.py", {
      private_subnets      = jsonencode(var.private_subnets),
      private_vlans        = jsonencode(metal_vlan.private_vlans.*.vxlan),
      public_subnets       = jsonencode(var.public_subnets),
      public_vlans         = jsonencode(metal_vlan.public_vlans.*.vxlan),
      public_cidrs         = jsonencode(metal_reserved_ip_block.ip_blocks.*.cidr_notation),
      domain_name          = var.domain_name,
      vcenter_network      = var.vcenter_portgroup_name,
      vcenter_fqdn         = format("vcva.%s", var.domain_name),
      vcenter_user         = var.vcenter_user_name,
      vcenter_domain       = var.vcenter_domain,
      sso_password         = random_password.sso_password.result,
      vcenter_cluster_name = var.vcenter_cluster_name,
      plan_type            = var.esxi_size,
      esx_passwords        = jsonencode(metal_device.esxi_hosts.*.root_password),
      dc_name              = var.vcenter_datacenter_name,
      metal_token          = var.auth_token,
    })

    destination = "$HOME/bootstrap/vars.py"
  }

  provisioner "file" {
    content     = file("${path.module}/templates/pre_reqs.py")
    destination = "$HOME/bootstrap/pre_reqs.py"
  }

  provisioner "remote-exec" {
    inline = ["python3 $HOME/bootstrap/pre_reqs.py"]
  }
}

# Populate locally the script for downloading a vCenter ISO via either AWS S3 or GCS protocol
data "template_file" "download_vcenter" {
  template = file("${path.module}/templates/download_vcenter.sh")
  vars = {
    object_store_bucket_name = var.object_store_bucket_name
    object_store_tool        = var.object_store_tool
    s3_url                   = var.s3_url
    s3_access_key            = var.s3_access_key
    s3_secret_key            = var.s3_secret_key
    s3_version               = var.s3_version
    vcenter_iso_name         = var.vcenter_iso_name
    ssh_private_key          = chomp(tls_private_key.ssh_key_pair.private_key_pem)
  }
}

# Copy the local GCS keys (if using GCS) over to the router
resource "null_resource" "copy_gcs_key" {
  count      = var.object_store_tool == "gcs" ? 1 : 0
  depends_on = [null_resource.run_pre_reqs]
  connection {
    type        = "ssh"
    user        = local.ssh_user
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
    host        = metal_device.router.access_public_ipv4
  }
  provisioner "file" {
    content     = file(local.gcs_key_path)
    destination = "$HOME/bootstrap/gcp_storage_reader.json"
  }
}

# Copy the rendered script for downloading vCenter and run it
resource "null_resource" "download_vcenter_iso" {
  depends_on = [
    null_resource.run_pre_reqs,
    null_resource.copy_gcs_key,
  ]
  connection {
    type        = "ssh"
    user        = local.ssh_user
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
    host        = metal_device.router.access_public_ipv4
  }

  provisioner "file" {
    content     = data.template_file.download_vcenter.rendered
    destination = "$HOME/bootstrap/download_vcenter.sh"
  }

  provisioner "remote-exec" {
    inline = ["bash $HOME/bootstrap/download_vcenter.sh"]
  }
}

resource "random_password" "ipsec_psk" {
  length           = 20
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "$!?@*"
  special          = true
}

resource "random_password" "vpn_pass" {
  length           = 16
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "$!?@*"
  special          = true
}


data "template_file" "vpn_installer" {
  template = file("${path.module}/templates/l2tp_vpn.sh")
  vars = {
    ipsec_psk = random_password.ipsec_psk.result
    vpn_user  = var.vpn_user
    vpn_pass  = random_password.vpn_pass.result
  }
}

# Set up an IPsec VPN server on the router
resource "null_resource" "install_vpn_server" {
  depends_on = [
    null_resource.run_pre_reqs,
    null_resource.download_vcenter_iso,
  ]
  connection {
    type        = "ssh"
    user        = local.ssh_user
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
    host        = metal_device.router.access_public_ipv4
  }

  provisioner "file" {
    content     = data.template_file.vpn_installer.rendered
    destination = "$HOME/bootstrap/vpn_installer.sh"
  }

  provisioner "remote-exec" {
    inline = ["bash $HOME/bootstrap/vpn_installer.sh"]
  }
}

resource "random_password" "vcenter_password" {
  length           = 16
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "$!?@*"
  special          = true
}

resource "random_password" "sso_password" {
  length           = 16
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "$!?@*"
  special          = true
}

# Populate the deployment configuration of the vCenter Virtual Appliance (vcva) and copy it to the router
resource "null_resource" "copy_vcva_template" {
  depends_on = [
    null_resource.run_pre_reqs,
  ]
  connection {
    type        = "ssh"
    user        = local.ssh_user
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
    host        = metal_device.router.access_public_ipv4
  }

  provisioner "file" {
    content = templatefile("${path.module}/templates/vcva_template.json", {
      vcenter_password        = random_password.vcenter_password.result,
      sso_password            = random_password.sso_password.result,
      first_esx_pass          = metal_device.esxi_hosts.0.root_password,
      domain_name             = var.domain_name,
      vcenter_network         = var.vcenter_portgroup_name,
      vcenter_domain          = var.vcenter_domain,
      vcva_deployment_option  = var.vcva_deployment_option
    })

    destination = "$HOME/bootstrap/vcva_template.json"
  }
}

# Copy the Python script for updating uplinks on the ESXi hosts to the router
resource "null_resource" "copy_update_uplinks" {
  depends_on = [null_resource.run_pre_reqs]
  connection {
    type        = "ssh"
    user        = local.ssh_user
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
    host        = metal_device.router.access_public_ipv4
  }

  provisioner "file" {
    content     = file("${path.module}/templates/update_uplinks.py")
    destination = "$HOME/bootstrap/update_uplinks.py"
  }
}

# Copy the Python script for updating ESXi host networking to the router
resource "null_resource" "esx_network_prereqs" {
  depends_on = [null_resource.run_pre_reqs]
  connection {
    type        = "ssh"
    user        = local.ssh_user
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
    host        = metal_device.router.access_public_ipv4
  }

  provisioner "file" {
    content     = file("${path.module}/templates/esx_host_networking.py")
    destination = "$HOME/bootstrap/esx_host_networking.py"
  }
}

# Update the networking of each ESXi host by running the Python scrips on the router
# https://metal.equinix.com/developers/guides/vmware-esxi/#quirks-of-standard-vswitch
resource "null_resource" "apply_esx_network_config" {
  count = length(metal_device.esxi_hosts)
  depends_on = [
    null_resource.reboot_post_upgrade,
    null_resource.esx_network_prereqs,
    null_resource.copy_update_uplinks,
    null_resource.install_vpn_server
  ]

  connection {
    type        = "ssh"
    user        = local.ssh_user
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
    host        = metal_device.router.access_public_ipv4
  }

  provisioner "remote-exec" {
    inline = ["python3 $HOME/bootstrap/esx_host_networking.py --host '${element(metal_device.esxi_hosts.*.access_public_ipv4, count.index)}' --user root --pass '${element(metal_device.esxi_hosts.*.root_password, count.index)}' --id '${element(metal_device.esxi_hosts.*.id, count.index)}' --index ${count.index} --ipRes ${element(metal_reserved_ip_block.esx_ip_blocks.*.id, count.index)}"]
  }
}

# Deploy vCenter Virtual Apliance (VCVA)
resource "null_resource" "deploy_vcva" {
  depends_on = [
    null_resource.apply_esx_network_config,
    null_resource.download_vcenter_iso
  ]
  connection {
    type        = "ssh"
    user        = local.ssh_user
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
    host        = metal_device.router.access_public_ipv4
  }

  # If there's only one ESXi server (without vSAN), the default datastore might not be enought in install vCenter. 
  # This script extends the datastore to span all the available disks of an ESXi host.
  provisioner "file" {
    source      = "${path.module}/templates/extend_datastore.sh"
    destination = "$HOME/bootstrap/extend_datastore.sh"
  }

  provisioner "file" {
    content     = file("${path.module}/templates/vsan_claim.py")
    destination = "$HOME/bootstrap/vsan_claim.py"
  }

  provisioner "file" {
    content     = file("${path.module}/templates/deploy_vcva.py")
    destination = "$HOME/bootstrap/deploy_vcva.py"
  }

  provisioner "remote-exec" {
    inline = ["python3 $HOME/bootstrap/deploy_vcva.py"]
  }
}

# Set up vSAN if there are more than one ESXi host
resource "null_resource" "vsan_claim" {
  depends_on = [null_resource.deploy_vcva]
  count      = var.esxi_host_count == 1 ? 0 : 1
  connection {
    type        = "ssh"
    user        = local.ssh_user
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
    host        = metal_device.router.access_public_ipv4
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'vCenter Deployed... Waiting 60 seconds before configuring vSan...'",
      "sleep 60",
      "python3 $HOME/bootstrap/vsan_claim.py"
    ]
  }
}

data "external" "get_vcenter_ip" {
  # The following command will test this script
  # echo '{"private_subnets":"[{\"cidr\":\"172.16.0.0/24\",\"name\":\"VM Private Net 1\",\"nat\":true,\"reserved_ip_count\":100,\"routable\":true,\"vsphere_service_type\":\"management\"},{\"cidr\":\"172.16.1.0/24\",\"name\":\"vMotion\",\"nat\":false,\"routable\":false,\"vsphere_service_type\":\"vmotion\"},{\"cidr\":\"172.16.2.0/24\",\"name\":\"vSAN\",\"nat\":false,\"routable\":false,\"vsphere_service_type\":\"vsan\"}]","public_cidrs":"[\"147.75.35.160/29\"]","public_subnets":"[{\"ip_count\":8,\"name\":\"VM Public Net 1\",\"nat\":false,\"routable\":true,\"vsphere_service_type\":null}]","vcenter_network":"VM Public Net 1"}' | python3 get_vcenter_ip.py
  program = ["python3", "${path.module}/scripts/get_vcenter_ip.py"]
  query = {
    "private_subnets" = jsonencode(var.private_subnets)
    "public_subnets"  = jsonencode(var.public_subnets)
    "public_cidrs"    = jsonencode(metal_reserved_ip_block.ip_blocks.*.cidr_notation)
    "vcenter_network" = var.vcenter_portgroup_name
  }
}
