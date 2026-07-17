
# Manual OCI Container Setup with `runc`

This project documents how I manually created and ran a container with **`runc`**. The purpose was to understand what higher-level tools such as Docker normally do for us: prepare a root filesystem, create an OCI runtime specification, and start the container process.

> `runc` is a low-level OCI runtime for Linux. Do this in a Linux machine, VM, or WSL2 environment—not directly on macOS or Windows.

## What I learned

An `runc` container needs an **OCI bundle**:

```text
my-runc-container/
├── config.json     # OCI runtime configuration
└── rootfs/          # Filesystem visible inside the container
    ├── bin/
    ├── etc/
    ├── proc/
    └── ...
```

The most important idea is that `runc` starts a process **inside `rootfs`**. Therefore, the command configured in `config.json` must exist inside that filesystem.

## Prerequisites

- Linux, WSL2, or a Linux virtual machine.
- `runc` installed.
- Docker installed, used only to export a small root filesystem for this lab.
- `jq` installed, used to edit JSON safely.
- Kernel user namespaces enabled if using the rootless method below.


