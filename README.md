# homebrew-tap

The Homebrew tap for [SMBPal](https://smbpal.app).

```sh
brew tap smbpal/tap
brew install smbpal
```

**The stable pin is one release behind on purpose.** `brew install smbpal`
fetches v0.2.5, whose tarball predates `smbpal-agent` — so until v0.2.6 is
tagged, use:

```sh
brew install --HEAD smbpal
```

The formula says the same thing in a comment above its `url`, and its `test do`
block fails against the stable tarball rather than passing quietly. That is
what caught the mismatch in the first place.

**macOS support is in progress.** What installs today is the client half — browse
the network, mount a share, and the per-user agent that does the mounting
(`smbpal-agent --install`). Serving shares needs a privileged helper that is not
ported yet, and the command line says so rather than pretending.

On Linux, install the `.deb` or the `.rpm` from
[smbpal-desktop](https://github.com/smbpal/smbpal-desktop) instead. The formula
declines to build there: those packages register a systemd unit, a polkit policy
and a `smbpal` group, and a Homebrew install would shadow them with a copy that
does none of it.

## Why a formula and not a cask

A cask presupposes a notarized `.app`, which SMBPal does not ship in its first
macOS release — and casks are quarantined by default, so Gatekeeper would be
deferred rather than avoided. A formula depends on `gtk4` and `pygobject3` the
way the `.deb` depends on `libgtk-4-1` and `python3-gi`, which sidesteps the real
difficulty of bundling GTK 4 on macOS: its data files carry absolute paths.

Reasoning in full: §11.1 of the project plan, and D11.

## The name

`homebrew-tap` breaks the project's own repository convention — every other repo
is `smbpal-` prefixed and named for the thing rather than the technology. The
prefix is Homebrew's requirement for `brew tap smbpal/tap` to resolve, so this
is one of two documented exceptions rather than drift. The other is `.github`.
