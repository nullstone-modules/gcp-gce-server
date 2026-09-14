data "ns_connection" "network" {
  name     = "network"
  contract = "network/gcp/vpc"
}

locals {
  vpc_name = data.ns_connection.network.outputs.vpc_name
  # Private subnet: VMs have no public IP; egress goes through Cloud NAT and
  # Google APIs via Private Google Access (both only exist on private subnets).
  private_subnet_names = data.ns_connection.network.outputs.private_subnet_names
  # Public subnet: ingress devices (NAT, load balancer addresses). Internal LB addresses live here.
  public_subnet_names = data.ns_connection.network.outputs.public_subnet_names
}
