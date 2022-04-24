#!/bin/sh

ESXI_HOST="$1"
VIB_FILENAME="$2"

scp "$HOME/bootstrap/${VIB_FILENAME}" "root@${ESXI_HOST}:/vmfs/volumes/datastore1/${VIB_FILENAME}"
scp "$HOME/bootstrap/install_vib.sh" "root@${ESXI_HOST}:/vmfs/volumes/datastore1/install_vib.sh"
