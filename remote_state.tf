terraform {
  backend "azurerm" {
    resource_group_name  = "devopsb28state"
    storage_account_name = "devopsb28devstate"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }

}

