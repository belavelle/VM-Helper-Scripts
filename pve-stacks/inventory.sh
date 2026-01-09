#!/usr/bin/env bash
PVE_STORAGE="local-lvm"
PVE_BRIDGE="vmbr0"
PVE_DNS="1.1.1.1"
PVE_GATEWAY=""
PVE_TEMPLATE_STORAGE="local"
PVE_TEMPLATE_FLAVOR="debian-12"

SERVICES=(
  "neo4j:201:neo4j:dhcp"
  "searxng:202:searxng:dhcp"
  "flowise:203:flowise:dhcp"
  "langfuse:204:langfuse:dhcp"
  "qdrant:205:qdrant:dhcp"
  "caddy:206:caddy:dhcp"
)
