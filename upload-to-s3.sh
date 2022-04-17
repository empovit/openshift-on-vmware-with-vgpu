#!/bin/sh

# Upload all files required for vSphere installation to S3-compatible storage
BUCKET="$1"
FILES="VMware-VCSA-all-7.0.3-19480866.iso vsanapiutils.py vsanmgmtObjects.py NVD-VGPU_510.47.03-1OEM.702.0.0.17630552_19297162.zip"

S3_OPTIONS=""
if [[ "$S3_ENDPOINT" != "" ]]
then    
    S3_OPTIONS="--endpoint-url $S3_ENDPOINT"
fi

for f in $FILES
do
    podman run --rm -it \
        -v ~/.aws:/root/.aws \
        -v $PWD:/vcsa-files \
        amazon/aws-cli $S3_OPTIONS s3 cp "/vcsa-files/$f" "s3://${BUCKET}/${f}"
done