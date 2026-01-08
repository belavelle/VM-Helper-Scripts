#!/usr/bin/env bash
PVE_STORAGE="local-lvm"
PVE_BRIDGE="vmbr0"
PVE_DNS="192.168.0.1"
PVE_GATEWAY=""
PVE_OSTEMPLATE="local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst"

SERVICES=(
  "neo4j:201:neo4j:dhcp"
  "searxng:202:searxng:dhcp"
  "flowise:203:flowise:dhcp"
  "langfuse:204:langfuse:dhcp"
  "qdrant:205:qdrant:dhcp"
  "caddy:206:caddy:dhcp"
)
