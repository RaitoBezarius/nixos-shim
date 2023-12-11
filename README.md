# NixOS shim signing

The goal of this project is to enable building NixOS installer images that will boot on systems that have Secure Boot enabled and only Microsoft keys installed.

## Status

We have an ISO that will boot on Secure Boot-enabled systems with test keys.

You can try it out by running `nix run`.
This will build a Secure Boot ISO image, with signatures from the test keys, and run it in a QEMU VM that has the test keys preconfigured.

This will be bootable on systems without the test keys once our [shim-review application](https://github.com/lheckemann/shim-review) has been approved.

## How?

We will be using [shim](https://github.com/rhboot/shim), which is the mechanism through which other distributions also do this.

The idea is:

- We build shim, embedding a _vendor certificate_ whose private component is managed by us;
- This shim build is signed by Microsoft(?) in order to allow it to boot on unconfigured systems (via https://github.com/rhboot/shim-review );
- We build installer images incorporating the signed shim, and where the next stages of the boot are signed with our vendor certificate.
