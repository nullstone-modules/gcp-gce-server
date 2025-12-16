data "ns_connection" "network" {
  name     = "network"
  contract = "network/gcp/vpc"
}

locals {
  vpc_name            = data.ns_connection.network.outputs.vpc_name
  public_subnet_names = data.ns_connection.network.outputs.public_subnet_names
}
