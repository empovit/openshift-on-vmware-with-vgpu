#!/usr/bin/python3
import os
import ipaddress
import urllib.request as urllib2
import random
from vars import (
    private_subnets,
    private_vlans,
    public_subnets,
    public_vlans,
    public_cidrs,
    domain_name,
    vcenter_network,
)


# Select only 4- and 5-letter words
def words_list():
    word_site = "https://raw.githubusercontent.com/taikuukaits/SimpleWordlists/master/Wordlist-Nouns-Common-Audited-Len-3-6.txt"
    response = urllib2.urlopen(word_site)
    word_list = response.read().splitlines()
    words = []
    for word in word_list:
        if 4 <= len(word) <= 5:
            words.append(word.decode().lower())
    return words


# Get random word list
words = words_list()

# Persist iptables IPv4 rules
os.system(
    "echo 'iptables-persistent iptables-persistent/autosave_v4 boolean true' | sudo debconf-set-selections"
)

# Persist iptables IPv6 rules
os.system(
    "echo 'iptables-persistent iptables-persistent/autosave_v6 boolean true' | sudo debconf-set-selections"
)

# Install Apt Packages
os.system(
    "echo 'deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main' > /etc/apt/sources.list.d/google-cloud-sdk.list"
)
os.system(
    "curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -"
)
os.system("DEBIAN_FRONTEND=noninteractive apt-get update -y")
os.system(
    'DEBIAN_FRONTEND=noninteractive apt-get install -o Dpkg::Options::="--force-confold" --force-yes -y dnsmasq vlan iptables-persistent conntrack python3-pip expect unzip python3-defusedxml google-cloud-sdk'
)

# Build single subnet map with all vlans, cidrs, etc...
subnets = private_subnets

for i in range(0, len(private_vlans)):
    subnets[i]["vlan"] = private_vlans[i]

for i in range(0, len(public_vlans)):
    # Update the public subnets with their VLANs and CIDRs
    public_subnets[i]["vlan"] = public_vlans[i]
    public_subnets[i]["cidr"] = public_cidrs[i]
    subnets.append(public_subnets[i])

# Wipe second Network Interface from config file
# TODO: This doesn't seem to do anything useful, because the lines will be later written back to the file
readFile = open("/etc/network/interfaces")
lines = readFile.readlines()
readFile.close()
interface = "bond0"

# Ensure 8021q is loaded (working with VLAN tagging on the host)
os.system("modprobe 8021q")

# Make sure 8021q is loaded at startup
modules_file = open("/etc/modules-load.d/modules.conf", "a+")
modules_file.write("\n8021q\n")
modules_file.close()

# Setup sysctl parameters for routing
sysctl_file = open("/etc/sysctl.conf", "a+")
sysctl_file.write("\n\n#Routing parameters\n")
sysctl_file.write("net.ipv4.conf.all.rp_filter=0\n")
sysctl_file.write("net.ipv4.conf.default.rp_filter=0\n")
sysctl_file.write("net.ipv4.ip_forward=1\n")
sysctl_file.write("net.ipv4.tcp_mtu_probing=2\n")
sysctl_file.close()

# Apply sysctl parameters
os.system("sysctl -p")

# Remove old conf for second interface
interface_file = open("/etc/network/interfaces", "w")
# TODO: This seems to dump the original lines back to the file
for line in lines:
    interface_file.write(line)

# Open dnsmasq config for writing
dnsmasq_conf = open("/etc/dnsmasq.d/dhcp.conf", "w")

# Loop though all subnets and setup Interfaces, DNSMasq, & IPTables
for subnet in subnets:
    if subnet["name"] == vcenter_network:
        vcenter_ip = list(ipaddress.ip_network(subnet["cidr"]).hosts())[1].compressed
    if subnet["routable"]:
        # Find vCenter IP
        if subnet["vsphere_service_type"] == "management":
            management_gateway = list(ipaddress.ip_network(subnet["cidr"]).hosts())[
                0
            ].compressed
            sed_cmd = (
                "sed -i '1i nameserver " + management_gateway + "' /etc/resolv.conf"
            )
            os.system(sed_cmd)
        # Gather network facts about this subnet
        router_ip = list(ipaddress.ip_network(subnet["cidr"]).hosts())[0].compressed
        low_ip = list(ipaddress.ip_network(subnet["cidr"]).hosts())[1].compressed
        if "reserved_ip_count" in subnet:
            high_ip = list(ipaddress.ip_network(subnet["cidr"]).hosts())[
                -subnet["reserved_ip_count"]
            ].compressed
        else:
            high_ip = list(ipaddress.ip_network(subnet["cidr"]).hosts())[-1].compressed
        netmask = ipaddress.ip_network(subnet["cidr"]).netmask.compressed

        # Setup VLAN interface for this subnet
        # See https://metal.equinix.com/developers/docs/layer2-networking/overview/
        interface_file.write("\nauto {}.{}\n".format(interface, subnet["vlan"]))
        interface_file.write(
            "iface {}.{} inet static\n".format(interface, subnet["vlan"])
        )
        interface_file.write("\taddress {}\n".format(router_ip))
        interface_file.write("\tnetmask {}\n".format(netmask))
        interface_file.write("\tvlan-raw-device {}\n".format(interface))
        interface_file.write("\tmtu 9000\n")

        # Generate random name for the network
        word = random.choice(words)
        words.remove(word)

        # Write dnsmasq dhcp scopes
        dnsmasq_conf.write("dhcp-range=set:{},{},{},2h\n".format(word, low_ip, high_ip))
        dnsmasq_conf.write(
            "dhcp-option=tag:{},option:router,{}\n".format(word, router_ip)
        )

        # Create NAT rule for this network if the network is tagged as NAT
        if subnet["nat"]:
            os.system(
                "iptables -t nat -A POSTROUTING -o bond0 -j MASQUERADE -s {}".format(
                    subnet["cidr"]
                )
            )

interface_file.close()

# Reserve the vCenter IP
dnsmasq_conf.write(
    "\ndhcp-host=00:00:00:00:00:99, {} # vCenter IP\n".format(vcenter_ip)
)

dnsmasq_conf.close()

# DNS record for vCenter
etc_hosts = open("/etc/hosts", "a+")
etc_hosts.write("\n{}\tvcva\tvcva.{}\n".format(vcenter_ip, domain_name))
etc_hosts.close()

# Add domain to host
resolv_conf = open("/etc/resolv.conf", "a+")
resolv_conf.write("\ndomain {}\nsearch {}\n".format(domain_name, domain_name))
resolv_conf.close()

# Block DNSMasq out the WAN (via bond0)
os.system("iptables -I INPUT -p udp --dport 67 -i bond0 -j DROP")
os.system("iptables -I INPUT -p udp --dport 53 -i bond0 -j DROP")
os.system("iptables -I INPUT -p tcp --dport 53 -i bond0 -j DROP")

# Bring up newly configured interfaces
os.system("ifup --all")

# Remove a saftey measure from dnsmasq that blocks VPN users from using DNS
os.system("sed -i 's/ --local-service//g' /etc/init.d/dnsmasq")

# Restart dnsmasq service
os.system("systemctl restart dnsmasq")

# Save iptables rules
os.system("iptables-save > /etc/iptables/rules.v4")

# Install python modules
os.system("pip3 install --upgrade pip pyvmomi packet-python")
