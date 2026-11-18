# Security policy

Glance Bar reads hardware counters and sensors with the rights of the user who runs it. It has no
helper process, asks for no permission and opens no network connection, and reports that show
otherwise are taken seriously.

## Report a vulnerability

Report it privately through
[GitHub's private vulnerability reporting](https://github.com/RobinVivant/glance-bar/security/advisories/new).
Do not open a public issue.

Include the version or commit you run, your macOS version and Mac model, what you did and what
happened. This is a personal project, so answers come as time allows. Fixes land on `main`, the
only supported version; there are no release branches.

## What is in scope

- A way to make the app write to the System Management Controller, or to any file other than its
  own user defaults (`local.glance-bar`).
- A way to make the app open a network connection, or start any program other than Activity
  Monitor, which its menu opens.
- A way for [`scripts/get.sh`](scripts/get.sh) to install something other than the release it
  downloaded and checked.

A report about macOS, its sensors or the drivers behind them belongs to Apple.

## What the app can reach

- It opens the `AppleSMC` service to read temperatures. It sends that service only the read
  commands, never a write.
- It reads CPU, memory, GPU, network, battery and disk figures from the kernel and from IOKit,
  all of them readable by any process of the user.
- It registers itself as a login item when you turn on Open at Login, and stores its settings in
  its user defaults. It writes nothing else.
- It has no telemetry, no update check and no other network call.
- The release build is signed ad hoc and not notarized by Apple. The install script checks the
  download against the SHA-256 file published with the release and verifies the signature
  before it copies the app.
