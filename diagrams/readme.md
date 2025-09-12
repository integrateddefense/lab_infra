# Diagrams

The architectural diagrams in this directory document the overall structure of the lab infrastructure.

## Draw.io

Unless otherwise specified, all documentation is generated with [Draw.io](https://draw.io). Contributors can upload files ending in ".drawio" to update the diagram in place instead of creating it from scratch.

## Physical Architecture

The physical architecture focuses primarily on emulating enterprise- or data-center level documentation, primarily rack and cabling diagrams.
It also communicates the high level cabling model in use, showing primary connection links as well as an inactive fallback to restore access to external services in the event the lab environment crashes.
Lastly, it diagrams the use of the patch panel and high level segmentation of ports on the core switch.

## Logical Architecture

The logical architecture focuses on taking advantage of Software Defined Networking (SDN) components that come with ProxMox to enforce microsegmentation.
At a high level, it aligns key functions to VLANs and provides the basis for the physical switch configurations, supporting user access, core services, external WAN (to allow the virtual infrastructure to provide the north-south firewall in lieu of a physical firewall), and DMZ.

## Microsegmentation Approach

TBD
