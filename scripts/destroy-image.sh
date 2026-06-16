#!/usr/bin/env bash
# Deletes the Packer-built managed image. The image is NOT in Terraform state,
# so terraform destroy leaves it behind. Run this as part of teardown.
set -euo pipefail

IMAGE_RG="${1:-rg-vmhardening-images}"
IMAGE_NAME="${2:-img-hardened-ubuntu-2204}"

echo "Deleting managed image ${IMAGE_NAME} in ${IMAGE_RG}..."
az image delete --resource-group "${IMAGE_RG}" --name "${IMAGE_NAME}"
echo "Done. Confirm the image resource group is empty if it is no longer needed:"
echo "  az resource list --resource-group ${IMAGE_RG} -o table"
