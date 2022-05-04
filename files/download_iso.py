#!/usr/bin/env python3

import esxi_hosts
import os
import sys


if __name__ == "__main__":

    iso_url = sys.argv[1]
    iso_filename = sys.argv[2]

    ip = str(esxi_hosts.ips[0])
    print(f"ESXi host: {ip}")
    # Download to the bastion first, because downloading directly from the cloud to an ESXi is too slow
    exit_status = os.system(f'''
        wget -O "{iso_filename}" \'{iso_url}\' &&
        scp -i "$HOME/.ssh/esxi_key" "{ iso_filename }" "root@{ip}:/vmfs/volumes/datastore1/{iso_filename}"
    ''')
    sys.exit(1 if exit_status else 0)
