# Remote state in the shared portfolio backend (same storage account as the
# other Azure projects). Matches the azure-landing-zone / azure-incident-responder
# convention. Run: terraform init
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfbackend-jordprojs"
    storage_account_name = "sttfbejordprojs8557"
    container_name       = "tfstate"
    key                  = "vm-hardening.tfstate"
  }
}
