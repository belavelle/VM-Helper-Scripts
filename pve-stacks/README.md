pve-stacks is an extensible system to add services via LXC containers into Proxmox.  Services can be added individually or all at once.

bash -c "$(curl -fsSL https://raw.githubusercontent.com/belavelle/VM-Helper-Scripts/main/pve-stacks/deploy.sh)" -- all

bash -c "$(curl -fsSL https://raw.githubusercontent.com/belavelle/VM-Helper-Scripts/main/pve-stacks/deploy.sh)" -- qdrant

Available services:

neo4j, searxng, flowise, langfuse, qdrant and caddy.
