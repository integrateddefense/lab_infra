# Raspberry Pi Management Node

This folder includes documentation, setup, and other notes on the Raspberry Pi Management Node

## Architecture

The Management Pi represents a secluded, administrative enclave to support IaC functions without exposing them to the larger ecosystem.
It is egress-only, and can only be accessed directly.
In a larger architecture, the Management Pi would fill a similar role as a Red Forest, "black hole", or other network segment that supports privileged functions.

## Setup

As the first node of the lab environment, it requires largely manual setup.
See [SETUP](setup.md) for the full documentation.