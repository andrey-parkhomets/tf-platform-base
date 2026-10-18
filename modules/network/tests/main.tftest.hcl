mock_provider "azurerm" {}

variables {
  name                = "tp-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
  address_space       = ["10.10.0.0/16"]
  subnets = {
    apps = {
      address_prefixes  = ["10.10.0.0/24"]
      service_endpoints = ["Microsoft.Storage"]
    }
    data = {
      address_prefixes = ["10.10.1.0/24"]
    }
  }
}

run "creates_one_subnet_and_nsg_per_key" {
  command = plan

  assert {
    condition     = length(azurerm_subnet.this) == 2
    error_message = "Expected one subnet for each key in var.subnets."
  }

  assert {
    condition     = length(azurerm_network_security_group.this) == 2
    error_message = "Expected one network security group for each subnet."
  }

  assert {
    condition     = length(azurerm_subnet_network_security_group_association.this) == 2
    error_message = "Every subnet must be associated with its network security group."
  }
}

run "names_follow_the_convention" {
  command = plan

  assert {
    condition     = azurerm_virtual_network.this.name == "vnet-tp-test"
    error_message = "The virtual network name must start with vnet-."
  }

  assert {
    condition     = azurerm_subnet.this["apps"].name == "snet-apps"
    error_message = "Subnet names must start with snet-."
  }
}

run "rejects_invalid_address_space" {
  command = plan

  variables {
    address_space = ["not-a-cidr"]
  }

  expect_failures = [var.address_space]
}

run "accepts_several_address_ranges" {
  command = plan

  variables {
    address_space = ["10.10.0.0/16", "10.20.0.0/16"]
  }

  assert {
    condition     = length(azurerm_virtual_network.this.address_space) == 2
    error_message = "Every address range given in var.address_space must reach the virtual network."
  }
}

run "subnet_address_prefixes_reach_the_subnet" {
  command = plan

  assert {
    condition     = azurerm_subnet.this["apps"].address_prefixes[0] == "10.10.0.0/24"
    error_message = "The address prefix of the apps subnet must come from var.subnets."
  }
}

run "service_endpoints_reach_the_subnet" {
  command = plan

  assert {
    condition     = contains(azurerm_subnet.this["apps"].service_endpoints, "Microsoft.Storage")
    error_message = "The service endpoint requested for the apps subnet must be set on it."
  }

  assert {
    condition     = length(azurerm_subnet.this["data"].service_endpoints) == 0
    error_message = "A subnet that requests no service endpoints must get none."
  }
}

run "subnet_and_nsg_names_follow_the_convention" {
  command = plan

  assert {
    condition     = azurerm_subnet.this["data"].name == "snet-data"
    error_message = "Subnet names must be snet- followed by the subnet key."
  }

  assert {
    condition     = azurerm_network_security_group.this["data"].name == "nsg-tp-test-data"
    error_message = "NSG names must be nsg-, the network name and the subnet key."
  }
}

run "tags_reach_the_network_resources" {
  command = plan

  variables {
    tags = {
      env = "test"
    }
  }

  assert {
    condition     = azurerm_virtual_network.this.tags["env"] == "test"
    error_message = "Tags must be set on the virtual network."
  }

  assert {
    condition     = azurerm_network_security_group.this["apps"].tags["env"] == "test"
    error_message = "Tags must be set on every network security group."
  }
}

run "no_subnets_creates_only_the_network" {
  command = plan

  variables {
    subnets = {}
  }

  assert {
    condition     = length(azurerm_subnet.this) == 0 && length(azurerm_network_security_group.this) == 0
    error_message = "With no subnets requested, no subnet or network security group may be created."
  }

  assert {
    condition     = length(azurerm_virtual_network.this.address_space) == 1
    error_message = "The virtual network must still be created when there are no subnets."
  }
}

run "outputs_list_every_subnet_by_key" {
  command = plan

  assert {
    condition     = length(output.subnet_ids) == 2
    error_message = "subnet_ids must hold one entry per subnet key."
  }

  assert {
    condition     = contains(keys(output.subnet_ids), "apps") && contains(keys(output.subnet_ids), "data")
    error_message = "subnet_ids must be keyed by the subnet keys from var.subnets."
  }
}
