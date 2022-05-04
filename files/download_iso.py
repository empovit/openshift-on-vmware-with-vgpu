#!/usr/bin/env python3

import esxi_hosts
import os
import sys


if __name__ == "__main__":

    iso_url = sys.argv[1]
    iso_filename = sys.argv[2]

    ip = str(esxi_hosts.ips[0])
    print(f"ESXi host: {ip}")
    exit_status = os.system(
        f'ssh -i "$HOME/.ssh/esxi_key" "root@{ip}" "sh -c wget -O /vmfs/volumes/datastore1/{iso_filename} \'{iso_url}\'"')
    sys.exit(1 if exit_status else 0)
