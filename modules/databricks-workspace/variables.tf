variable "name" {
  description = "Workspace name."
  type        = string

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 30
    error_message = "The name must be 3 to 30 characters long."
  }
}

variable "resource_group_name" {
  description = "Resource group that holds the workspace."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "sku" {
  description = "Workspace tier: standard or premium."
  type        = string
  default     = "premium"

  validation {
    condition     = contains(["standard", "premium"], var.sku)
    error_message = "The sku must be standard or premium."
  }
}

variable "public_network_access_enabled" {
  description = "Allow access to the workspace from the public internet."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags for all resources."
  type        = map(string)
  default     = {}
}
