# Agent on a Small Box: Architecture & Design Decisions

This document captures the architectural decisions and rationale behind the Locmox setup.

## Reference Hardware

### Primary Test Machine
- **Model:** HP ProDesk 600 G4 Mini (1-liter form factor)
- **CPU:** Intel i5-8500T (6-core/6-thread, 2.1GHz base, 3.7GHz turbo)
  - AVX2 support, no AVX-512
  - TDP: 35W (low-power "T" series)
- **RAM:** 64GB DDR4
- **Storage:** 500GB NVMe SSD
- **Network:** Gigabit Ethernet
- **Management:** Headless, SSH-only

### Infrastructure Context
The Proxmox host sits within a larger home lab infrastructure:

```
┌────────────────────────────────────────────────────────────────┐
│                     Home Lab Infrastructure                     │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐   │
│  │ agent host  │     │  GPU Server  │     │   Backup     │   │
│  │  (Proxmox)   │◄───►│  (3x RTX    │     │   Server     │   │
│  │  i5-8500T    │     │   3060 12GB) │     │  (Proxmox   │   │
│  │  64GB RAM    │     │  On-demand   │     │   + PBS)    │   │
│  └──────────────┘     └──────────────┘     └──────────────┘   │
│         │                                    │                 │
│         ▼                                    ▼                 │
│  ┌──────────────┐                     ┌──────────────┐        │
│  │   TrueNAS    │                     │   TrueNAS    │        │
│  │  (Flash NAS) │                     │  (Backup     │        │
│  │  4x4TB VM    │                     │   Storage)   │        │
│  └──────────────┘                     │  4x16TB HDDs │        │
│                                       └──────────────┘        │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

## Core Design Principles

### 1. Local-First Inference

**Decision:** CPU inference as primary, GPU as secondary/on-demand

**Rationale:**
- **Energy efficiency:** GPU server idles at 75W (more than a large fridge)
- **Heat management:** Summer months make continuous GPU operation impractical
- **Always-on capability:** CPU inference runs 24/7 without thermal/energy concerns
- **Cost:** Zero marginal cost for CPU vs. significant electricity for GPU

**Implementation:**
- Primary: llama.cpp on Proxmox host (CPU inference)
- Secondary: GPU server activated on-demand for heavy tasks
- Models: 4-8B dense models for CPU, or MoE with <5B active params; GPU handles larger models or whatever fits on VRAM

### 2. Proxmox as Base Layer

**Decision:** Proxmox VE 9.1-1 as host OS, not VM guest

**Rationale:**
- **Direct hardware access:** Best performance for inference server
- **LXC/VM isolation:** Test multiple harnesses without conflicts, clean separation for llama.cpp and other services
- **Backup integration:** Native Proxmox Backup Server support, clone/snapshot capabilities
- **Web UI:** Convenient management without SSH
- **ZFS:** Built-in filesystem with compression, snapshots, checksums

**Security consideration:** Running the harness on the host means careful network segmentation. Ideally, use a managed switch to isolate the machine from the rest of the LAN, giving selective access only. This controls blast radius in case of prompt injection attacks or model misbehavior (e.g., agents managing emails could leak information or delete messages if hijacked). Without managed switches, understand the risks and mitigate where possible.

**Trade-offs:**
- Slightly more overhead than bare Debian
- Learning curve for Proxmox-specific features
- Mitigated by: superior backup/clone capabilities

### 3. Harness on Host, Testing in LXC/VM

**Decision:** Primary agentic harness installed directly on Proxmox host

**Rationale:**
- **Performance:** No virtualization overhead for main agent
- **Resource access:** Direct access to hardware, models, network
- **Simplicity:** Fewer layers to debug
- **Testing isolation:** LXC containers for experimenting with alternative harnesses

**Implementation:**
- Host: Production harness (OpenClaw or chosen alternative)
- LXC: Sandbox environments for testing new harnesses
- VM: Full OS isolation when needed

## Software Stack

### Inference Layer
- **Primary:** llama.cpp (CPU-optimized, extensive existing knowledge base in llmlab repo: github.com/githabideri/llmlab)
- **Alternative:** ik_llama.cpp (fork optimized for CPU-only inference, under evaluation for this hardware)
- **Why not Ollama:** Ollama wraps llama.cpp but offers less control; self-compiled llama.cpp provides best model support and customization

### Model Strategy
- **CPU models:** 4-8B dense models, or MoE with <5B active params (expect 7-12 tokens/sec for A3B-class models)
- **GPU models:** Larger models or whatever fits on VRAM pool when GPU server activated
- **Preference:** MoE (Mixture of Experts) for large models: faster and more efficient
- **Quantization:** Q4_K_M to Q5_K_M balance (size vs quality)
- **Spectrum:** From sub-1B models (Raspberry Pi) to 50-60GB RAM models (this hardware)

### Agentic Harness (To Be Determined)
- **Candidates:** OpenClaw, picoclaw, nanoclaw, zeroclaw, and other OpenClaw variants
- **Selection criteria:** Resource efficiency, feature set, community activity, local-first philosophy
- **Investigation status:** Pending (docs/03-harness-comparison.md)

### Storage & Backup
- **Local:** ZFS RAID0 on NVMe (single drive, so no redundancy)
- **Backup:** Proxmox Backup Server on separate machine (recommended)
- **Long-term:** TrueNAS datasets for archival storage (recommended)
- **Strategy:** Consider 3-2-1 backup rule (3 copies, 2 media types, 1 offsite) as best practice

## Network Topology

For networking, you have several options:

- **Static IPs:** Simple, just assign fixed IPs to your servers
- **Custom domains:** Use internal DNS (e.g., Pi-hole, Bind9) with your own domain
- **Tailscale MagicDNS:** Zero-config mesh networking with automatic DNS

Choose what fits your infrastructure. The key is consistent naming so services can find each other.

### Security Note
Consider network segmentation for your agent host. A managed switch can isolate the machine from the rest of the LAN, limiting blast radius in case of compromise.

## Performance Expectations

### CPU Inference (i5-8500T)
- **Sub-1B models:** Very fast (10-30+ tokens/sec)
- **1-3B models:** Fast (5-15 tokens/sec)
- **4-8B models:** Moderate (2-5 tokens/sec)
- **MoE (A3B-class):** 7-12 tokens/sec (e.g., Qwen3.5-A3B, LFM2-A3B)
- **20B+ dense:** Very slow, consider GPU or smaller MoE

### Memory Constraints
- **64GB RAM:** Can load models up to ~50-60GB (leaving 4-8GB for OS)
- **MoE advantage:** Mixture-of-Experts models load fewer active parameters
- **Quantization:** Q4_K_M, Q5_K_M preferred balance of size/quality

## Alternative Hardware Paths

While this guide focuses on Proxmox, the concepts apply to:

- **Raspberry Pi 4/5:** Sub-4B models, ARM-optimized llama.cpp (a 4GB Pi 4 was considered; the mini PC won on performance)
- **Plain Debian/Ubuntu:** Same software stack, no Proxmox layer (Proxmox is "basically souped-up Debian")
- **WSL on Windows:** Possibly viable for Windows users
- **Gaming PC:** Full GPU acceleration, larger models
- **Dedicated Server:** 24/7 GPU operation if cooling/power permit

**Key insight:** Proxmox is not mandatory; results are transferable to any Linux setup. The advantage is testing multiple harnesses in isolated LXC/VM environments without affecting the host, clean separation for llama.cpp and other service LXCs, backup integration, and the ability to clone and snapshot.

## Version Information

- **Proxmox VE:** 9.1-1 (current at time of writing)
- **llama.cpp:** Latest stable (check for updates)

---

*A growing document: expect changes and improvements!*