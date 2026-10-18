subscription_id    = "00000000-0000-0000-0000-000000000002"
tenant_id          = "00000000-0000-0000-0000-000000000000"
environment        = "prod"
vnet_address_space = ["10.30.0.0/16"]

# Temporary: the data team needs to reach the lake from the office network while the private link is being set up.
public_access_enabled = true

data_lakes = {
  raw     = { containers = ["landing", "bronze"] }
  curated = { containers = ["silver", "gold"] }
}
