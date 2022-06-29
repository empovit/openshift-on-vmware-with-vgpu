#!/usr/bin/env python3

import argparse

from pyVmomi import vim
from pyVim import connect

graphics_types = ["shared", "sharedDirect"]


def update_graphics(vcenter_host, vcenter_user, vcenter_passwd, graphics_type, ignore_certs=False):
    conn = connect.SmartConnect(host=vcenter_host, user=vcenter_user,
                                pwd=vcenter_passwd, disableSslCertValidation=ignore_certs)

    content = conn.RetrieveContent()
    host_view = content.viewManager.CreateContainerView(
        content.rootFolder, [vim.HostSystem], True)
    esxi_hosts = host_view.view
    host_view.Destroy()

    for host in esxi_hosts:
        graphics_manager = host.configManager.graphicsManager
        graphics_config = graphics_manager.graphicsConfig
        graphics_config.hostDefaultGraphicsType = graphics_type

        for device in graphics_config.deviceType:
            device.graphicsType = graphics_type
        graphics_manager.UpdateGraphicsConfig(graphics_config)


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Set graphic type of the ESXi hosts in a cluster")
    parser.add_argument("--host", type=str, required=True,
                        help="vCenter hostname or IP address")
    parser.add_argument("--user", type=str, required=True, help="vCenter user")
    parser.add_argument("--passwd", type=str, required=True,
                        help="vCenter password")
    parser.add_argument("--graphics", type=str, required=True,
                        choices=graphics_types, help="Host graphics type")
    parser.add_argument("--ignore-certs", dest="ignore_certs", action="store_true",
                        default=False, help="Ignore certificate validation")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_arguments()
    update_graphics(vcenter_host=args.host, vcenter_user=args.user, vcenter_passwd=args.passwd,
                    graphics_type=args.graphics, ignore_certs=args.ignore_certs)
