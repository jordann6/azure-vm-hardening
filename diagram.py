"""Architecture diagram for azure-vm-hardening.

Renders docs/architecture.png. Requires the diagrams package and Graphviz:
    pip install diagrams   # and: brew install graphviz
    python diagram.py
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.azure.compute import VMImages, VM
from diagrams.azure.network import (
    VirtualNetworks,
    NetworkSecurityGroupsClassic,
    Firewall,
    RouteTables,
)
from diagrams.onprem.network import Internet
from diagrams.onprem.iac import Ansible, Terraform
from diagrams.onprem.ci import GithubActions
from diagrams.programming.framework import Flask  # stand-in icon for Packer

graph_attr = {"fontsize": "20", "bgcolor": "white", "pad": "0.5"}

with Diagram(
    "Azure VM Hardening",
    filename="docs/architecture",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    ci = GithubActions("Molecule CI\n(converge / verify / idempotence)")

    with Cluster("Image pipeline"):
        role = Ansible("cis_baseline role")
        packer = Flask("Packer\nazure-arm bake")
        image = VMImages("img-hardened-ubuntu-2204")
        ci >> Edge(label="tests") >> role
        role >> Edge(label="provisioner") >> packer >> image

    with Cluster("Z1-style hub VNet (10.0.0.0/16)"):
        net = VirtualNetworks("hub")

        with Cluster("Palo Alto VM-Series perimeter (opt-in)"):
            inet = Internet("Internet")
            fw = Firewall("VM-Series NGFW\nuntrust / trust / mgmt")
            udr = RouteTables("UDR: 0.0.0.0/0\n-> trust 10.0.6.4")
            inet >> Edge(label="untrust") >> fw

        with Cluster("snet-management 10.0.3.0/24"):
            nsg = NetworkSecurityGroupsClassic("nsg: deny inbound,\nSSH from admin only")
            jump = VM("hardened jump host")
            nsg >> jump

        # Defense in depth: all jump-host egress is forced through the firewall
        # trust interface, with the subnet NSG still applied underneath.
        fw >> Edge(label="trust") >> udr >> Edge(label="inspected egress") >> jump

    tf = Terraform("Terraform")
    image >> Edge(label="source_image_id") >> jump
    tf >> Edge(label="provisions", style="dashed") >> net
