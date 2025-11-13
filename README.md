# RootLock

RootLock is a Swift CLI that packages:

- an **AES-GCM–encrypted admin password**, bound to a single Mac, and  
- an **embedded shell script** that is executed with root privileges,

into a **single self-contained binary**.

The core idea: you get a “drop-in” root utility that can run privileged setup tasks (like configuring iPhone USB network interfaces) **without ever storing the plaintext password in the source tree or the binary**, and **without working through LaunchDaemons / SMJobBless / LaunchConstraints** during development.

---

## What it actually does

At build time:

 - A helper tool (`EmbedCredentials.swift`, invoked from `build_secure.sh`)  
 - reads the **admin password** from the command line,  
 - reads the **machine hardware UUID** (`IOPlatformUUID`),  
 - generates a random **KDF salt**,  
 - derives a **32-byte key via HKDF-SHA256** from:
  
  ```text
   key material = IOPlatformUUID || "NETWORK_SETUP_ENCRYPTION"
   salt         = 16 random bytes
   info         = "password-encryption"
  ```
 
 - encrypts the password with **AES-256-GCM**,  
 - outputs **Base64-encoded KDF salt and ciphertext blob**, which are then inlined into `SecureNetworkSetup.swift`.
 
 - `build_secure.sh` also takes `Script.sh`, injects its contents into a Swift multiline string literal, and produces a final Swift source where both:
 - `encryptedPassword` + `kdfSalt`  
 - the full script body  
 are **compiled directly into the binary**.
 
 At runtime:
 
1. The CLI reads `IOPlatformUUID` again.
2. It recomputes the HKDF-SHA256 key using the embedded salt.
3. It splits the embedded blob into:
   - AES-GCM **nonce** (12 bytes),
   - **ciphertext + tag**.
4. It calls `AES.GCM.open` to recover the admin password **in memory only**.  
   If the binary is run on a different Mac, HKDF derives a different key, decryption fails, and the password is unrecoverable.

5. The embedded shell script is written to a temporary file, made executable, and then invoked via a small wrapper that runs:

   ```sh
   printf '%s\n' '<decrypted-password>' | sudo -S /path/to/script.sh
   ```
   
   6. Temporary files are cleaned up after execution.

Result: the **repo** and the **binary on disk** only ever contain:

- HKDF salt (random)
- AES-GCM ciphertext + tag + nonce
- the embedded script content

The admin password never appears in plaintext outside of process memory or the `sudo -S` pipe.

---

## About `Script.sh` (pluggable root logic)

`Script.sh` in this repository is only an **example payload**: it configures the iPhone USB network interface using `networksetup`.  
The mechanism itself is fully generic.

You can replace `Script.sh` with **any root-privileged logic**—a shell script, a configuration script, or even a more advanced workflow. After running `build_secure.sh`, the new script is embedded directly into the binary and executed with root privileges through the same secure mechanism.

This makes `SecureNetworkSetup` a **template** for “embed script + machine-bound encrypted credentials”, not a tool limited to a single purpose.

---

## Relation to Apple’s privileged execution model

Apple’s recommended production-grade way to run code as root involves:

- **LaunchDaemons** (via launchd)
- **SMJobBless** (now deprecated)
- Strict **LaunchConstraints**
- Full **code signing** + **notarization**
- Sandbox and hardened runtime requirements

macOS has tightened these mechanisms significantly, making it harder to ship ad-hoc root utilities without deep integration into Apple’s security stack.

This project intentionally serves as a **quick, controlled, internal alternative**:

- No LaunchDaemon plist
- No SMJobBless setup
- No helper-tool installation pipeline
- No notarization requirement for basic internal use
- No reliance on the sandbox or LaunchConstraints

Instead, it focuses on:

- **no plaintext passwords ever touching disk**
- **per-device encryption** via `IOPlatformUUID`
- maintaining a **single self-contained binary** that only works on its provisioned Mac

This is not meant to replace Apple’s full security model for distributed software—it’s a practical shortcut for trusted environments where simplicity is more important than formal sandbox compliance.

---

## Future direction

This pattern can be extended to align better with Apple’s expectations while keeping the “single locked binary” design:

- Wrap the tool in a **signed and notarized** application bundle
- Or embed it inside a LaunchDaemon that calls it safely
- Add **policy checks** before execution (signed configs, machine attestations, etc.)
- Integrate with secure storage mechanisms if required, while still benefiting from HKDF + per-device binding

For now, this repository serves as a **lean, cryptographically sound prototype**:

> A single Swift CLI embedding a machine-bound AES-GCM encrypted admin password and any arbitrary root script, decrypting the password in memory with HKDF derived from the local hardware UUID, and feeding it to `sudo` to execute privileged operations—remaining useless and unable to reveal the password on any machine except the one it was provisioned for.
