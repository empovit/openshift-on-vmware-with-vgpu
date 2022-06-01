
import ipaddress
from vars import (
    private_subnets,
    public_subnets,
    public_cidrs,
    esx_passwords,
)


def calculate_esx_ips():

    subnets = private_subnets
    for i in range(len(public_cidrs)):
        public_subnets[i]["cidr"] = public_cidrs[i]
        subnets.append(public_subnets[i])

    esx = []
    for subnet in subnets:
        if subnet["vsphere_service_type"] == "management":
            for i in range(len(esx_passwords)):
                esx.append(list(ipaddress.ip_network(
                    subnet["cidr"]).hosts())[i + 3].compressed)

    return esx


ips = calculate_esx_ips()
