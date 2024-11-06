resource "azurerm_resource_group" "prod_rg" {
  location = var.resource_group_location
  name     = azurerm_resource_group.prod_rg.id
}

# Create virtual network
resource "azurerm_virtual_network" "prod_network" {
  name                = "prodvnet"
  address_space       = var.vnet_cidr
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create subnet
resource "azurerm_subnet" "prod_subnet-1" {
  name                 = "prod_subnet-1"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.prod_subnet-1.name
  address_prefixes     = var.prod_subnet-1_cidr
}

# Create public IPs
resource "azurerm_public_ip" "prod_public_ip" {
  name                = "prod_public_ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "prod_nsg" {
  name                = "prod_nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create network interface
resource "azurerm_network_interface" "prod_nic" {
  name                = "${var.vm_name}-NIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "prod_nic_configuration"
    subnet_id                     = azurerm_subnet.prod_subnet-1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.prod_public_ip.id
  }

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = {

    #MONITORING = "YES"
    #"ASSET CLASSIFICATION" = "Non-Critical"

  }
}



# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "prod_int-nsg_association" {
  network_interface_id      = azurerm_network_interface.prod_nic.id
  network_security_group_id = azurerm_network_security_group.prod_nsg.id
}

# Generate random text for a unique storage account name
resource "random_id" "random_id" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.rg.name
  }

  byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "prod_storage_account" {
  name                     = "diag${random_id.random_id.hex}"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "prod_vm" {
  name                  = "prod_vm"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.prod_nic.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "prodOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  computer_name  = "hostname"
  admin_username = var.username

  admin_ssh_key {
    username   = var.username
    public_key = azapi_resource_action.ssh_public_key_gen.output.publicKey
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.my_storage_account.primary_blob_endpoint
  }
}

#Create data disk and attach to virtual machine
resource "azurerm_managed_disk" "data_disk-1" {
  name                 = "data_disk-1"
  location             = azurerm_resource_group.example.location
  resource_group_name  = azurerm_resource_group.example.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 10
}

resource "azurerm_virtual_machine_data_disk_attachment" "datadisk_attach" {
  managed_disk_id    = azurerm_managed_disk.data_disk-1.id
  virtual_machine_id = azurerm_virtual_machine.prod_vm.id
  lun                = "10"
  caching            = "ReadWrite"
}

# backup policy assignment
data "azurerm_backup_policy_vm" "protection_policy" {
  name                = "DefaultPolicy"
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_resource_group.rsv.name
}

resource "azurerm_backup_protected_vm" "protection_assignment" {
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_resource_group.rsv.name
  source_vm_id        = azurerm_virtual_machine.prod_vm.id
  backup_policy_id    = data.azurerm_backup_policy_vm.protection_policy.id
}

# VM Extensions
#resource "azurerm_virtual_machine_extension" "MicrosoftMonitoringAgent" {
#
# name                 = "${var.vm_name}-MMA"
#  location             = "${var.countrylocation}"
#  resource_group_name  = "${data.azurerm_resource_group.myterraformgroup.name}"
#  virtual_machine_name = "${azurerm_virtual_machine.vm-cis-windows.id}"
#  publisher            = "Microsoft.EnterpriseCloud.Monitoring"
#  type                 = "MicrosoftMonitoringAgent"
#  type_handler_version = "1.0"
#
#  settings = <<SETTINGS
#    {
#        "commandToExecute": "hostname && uptime"
#    }
#SETTINGS
#
# tags = {
#    #environment = "Production"
#	#LVSMON = "YES"
#  }
#}

#Extension BGInfo
#resource "azurerm_virtual_machine_extension" "BGInfo" {
#  name                 = "${var.vm_name}-BGInfo"
#  location             = "${var.countrylocation}"
#  resource_group_name  = "${data.azurerm_resource_group.myterraformgroup.name}"
#  virtual_machine_name = "${azurerm_virtual_machine.vm-cis-windows.id}"
#  publisher            = "Microsoft.Compute"
#  type                 = "BGInfo"
#  type_handler_version = "2.1"
#}


