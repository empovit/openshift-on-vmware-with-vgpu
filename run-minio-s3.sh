#!/bin/sh

# Run minio s3-compatible storage as a container
podman run \
    -d \
    -p 9000:9000 \
    -p 9001:9001 \
    --name minio \
    -v /root/s3-data:/data \
    -e "MINIO_ROOT_USER=$1" \
    -e "MINIO_ROOT_PASSWORD=$2" \
    quay.io/minio/minio server /data --console-address ":9001"

# Create a bucket for vCenter installation files
mkdir -p /root/.aws
podman run \
    --rm -it \
    -v /root/.aws:/root/.aws \
    amazon/aws-cli \
    --endpoint-url http://127.0.0.1:9000 \
    s3 mb "s3://$3"