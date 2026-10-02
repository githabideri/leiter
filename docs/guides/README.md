# Guides

Step-shaped, human-facing material for building pieces of the estate.
Unlike the practice docs (which describe how the *agent* works) and the
skills (which teach the *agent* to work), guides are for the person
building the shape: "how do I set this up on my hardware".

| Guide | What it covers |
|---|---|
| [agent-on-small-box](agent-on-small-box.md) | Running an agentic AI stack on modest hardware: the reference machine (1-liter mini PC), the design principles (local-first CPU inference, GPU on-demand, Proxmox as base layer, harness on host / experiments in LXC), the model strategy (MoE, quantization, a measured performance table), and the alternative hardware paths |
| [agent-security](agent-security.md) | The threat model for autonomous agents on your network: prompt injection, context-window compromise, model hijacking, data leakage; segmentation options from managed-switch VLANs down to the minimum viable unmanaged setup; per-agent-type measures (email, browser, sysadmin) and the standing best practices |

**Provenance note.** Both were written for one specific estate's
primary agent host and salvaged here when that project's dedicated
repository was retired; the machine-specific names were generalized to
roles. They are "growing" documents: the estate keeps finding out new
things, and these pages are where that keeps.
