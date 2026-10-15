# The macOS distribution, and a formula rather than a notarized `.app` by
# decision rather than by default (plan §11.1, D11).
#
# GTK 4 is the hardest of the four toolkits to bundle on macOS, and not for its
# dylib count: its data files carry absolute paths — GObject Introspection
# typelibs, GSettings schemas, the gdk-pixbuf `loaders.cache`, the icon theme.
# A formula sidesteps every one of them by depending on `gtk4` and `pygobject3`
# the way the `.deb` depends on `libgtk-4-1` and `python3-gi`. A cask would not:
# casks are quarantined by default and presuppose the notarized app this exists
# to defer.
class Smbpal < Formula
  include Language::Python::Virtualenv

  desc "Share folders over SMB, and connect to the ones other machines share"
  homepage "https://smbpal.app"
  # The tag must contain `smbpal-agent`, which is what `caveats` tells people to
  # run and what v0.2.5's tarball did not have — the `test do` block below is
  # what caught that, and it is why the url and the test move together.
  url "https://github.com/smbpal/smbpal-desktop/archive/refs/tags/v0.2.15.tar.gz"
  sha256 "cca3791a7a33002aae3b69e961e76d0299a1fc32ea89e94d7beb461a24c9362c"
  license "GPL-3.0-or-later"
  head "https://github.com/smbpal/smbpal-desktop.git", branch: "main"

  # Four dependencies, in the alphabetical order `brew style` insists on — which
  # separates the two that belong together, so the reasoning is here rather than
  # beside each line.
  #
  # **`gtk4` and `pygobject3` are 48 formulae** in the union of their closures,
  # measured 30 September 2026 and reproduced on 2 October. Homebrew cannot
  # express `Recommends`, so unlike the `.deb` a headless macOS install still
  # pays for the GUI stack: D11 took one formula over an `smbpal`/`smbpal-gui`
  # split, and recorded the split as the thing to revisit if anybody asks for
  # headless macOS.
  #
  # **`:macos` is not a preference.** Linux has a `.deb` and an `.rpm` that
  # register a systemd unit, a polkit policy and a `smbpal` group; a Homebrew
  # install there would shadow them with a copy that does none of it.
  #
  # **`python@3.14` is not a free choice.** `pygobject3` is bottled against one
  # interpreter and installs `gi` into that interpreter's site-packages, so this
  # line is whatever `brew deps pygobject3` names. Verified 2 October 2026:
  # pygobject3 3.56.3 depends on python@3.14, and `gi` imports Gtk 4.22.4 from
  # /opt/homebrew/lib/python3.14/site-packages. Moving it without moving
  # pygobject3 produces a GUI that cannot import its own toolkit.
  depends_on "gtk4"
  depends_on :macos
  depends_on "pygobject3"
  depends_on "python@3.14"

  # No `service do` block, and that is this formula's one structural decision.
  # Homebrew allows exactly one service per formula and macOS needs two: a root
  # LaunchDaemon for sharepoints and accounts, which is not ported, and D13's
  # per-user agent for mounting, which is. So the block is reserved for the
  # daemon, and the agent installs its own LaunchAgent — see `caveats`. The
  # agent's plist needs `LimitLoadToSessionType` anyway, which the DSL has no
  # way to say.

  def install
    # `system_site_packages` defaults to true, which is the whole reason this
    # works: `gi` lives in the Homebrew python's site-packages, not in ours, and
    # a sealed virtualenv could not see it. The console scripts are **symlinked**
    # into `bin` rather than wrapped, which matters beyond tidiness — the agent
    # writes its own launchd plist from `sys.argv[0]`, so running
    # `/opt/homebrew/bin/smbpal-agent` must keep that path rather than resolve
    # to a version-numbered one inside the Cellar.
    virtualenv_install_with_resources
  end

  def caveats
    <<~EOS
      macOS support is in progress. Connecting to shares works fully:

        smbpal browse                 find machines sharing over SMB
        smbpal connection add ...     mount a share
        smbpal-agent --install        start the agent that does the mounting

      The agent runs in your login session and not as root, because that is
      where the Keychain it reads lives, and because mounting on macOS needs no
      elevation. `smbpal-agent --status` says whether launchd has it.

      Before `brew uninstall`, take the agent back out:

        smbpal-agent --uninstall

      launchd keeps restarting what it has been given, so a plist left behind
      points at a program that is no longer there.

      To run the daemon, which keeps the configuration and answers `smbpal`:

        smbpal setup

      It prints the commands rather than running them, and nothing of SMBPal's
      runs as root until the last one — by which point the thing being run as
      root is a root-owned copy. Changing anything then asks for an
      administrator password, through the same dialog the rest of the system
      uses. After the install you need a new terminal: a shell keeps the groups
      it started with.

      Sharing your own folders works once the daemon is set up:

        smbpal share add <name> <folder> [--user <account>]

      The folder must be inside /Users or /Volumes, and a whole home folder is
      refused -- share a folder inside it. Guest access is always off. File
      Sharing has to be on in System Settings > General > Sharing, and turning
      it on serves every shared folder on the Mac, not only SMBPal's.

      Shares are served to accounts that already exist. On a Mac the SMB
      password is the login password, so SMBPal does not set one: tick the
      account under File Sharing > Options. `smbpal share make-writable <name>`
      then lets that account write, and lets the folder's owner open what it
      writes. Not yet: read-only shares.

      After `brew upgrade`, the daemon and the agent keep running the old
      version until they restart:

        sudo launchctl kickstart -k system/app.smbpal.daemon
        smbpal-agent --install

      The agent reconnects your shares at login, after sleep and when a server
      comes back; a share you eject or disconnect stays disconnected.

      Upgrading with the daemon installed? The helper is a separate, root-owned
      binary that `brew upgrade` does not touch. From a checkout of this
      release's source, build it as yourself and install it as root:

        make -C helper && sudo make -C helper install

      That also re-registers it with launchd, waiting for launchd to finish
      with the old one first; replacing the binary by hand leaves the new
      helper unable to start.
    EOS
  end

  test do
    # The licence notice travels with the binary because GPLv3 §6(d) lets a
    # public repository stand in for a source tarball only if the directions to
    # it go with the object code, so it is an invariant rather than decoration.
    banner = shell_output("#{bin}/smbpal --version")
    assert_match "GPL-3.0-or-later", banner
    assert_match "github.com/smbpal/smbpal-desktop", banner
    # On a `--HEAD` build `version` is "HEAD-<sha>" while the program keeps
    # reporting the number in `pyproject.toml`, so these two only have to agree
    # on a release. Found by running `brew test` against HEAD rather than by
    # reading about it.
    unless head?
      assert_match version.to_s, banner
      assert_match version.to_s, shell_output("#{bin}/smbpald --version")
    end

    # The platform check, which is the agent's own answer rather than ours.
    assert_equal "supported", shell_output("#{bin}/smbpal-agent --check").strip

    # A config it has never seen validates as empty rather than failing, and
    # `--check` binds nothing — so this exercises the daemon's parser with no
    # socket, no root and no Samba.
    assert_match "config is valid",
      shell_output("#{bin}/smbpald --check --config #{testpath}/config.json 2>&1")

    # Exit 3 is the documented code for "could not reach the daemon", and both
    # of the ways that happens take it: no socket at all, and a socket this user
    # may not connect to.
    #
    # **It no longer asserts which of the two, and that was a real failure.**
    # The test asserted "no SMBPal daemon", which was an invariant only while
    # macOS could not run one. 0.2.10 makes installing the daemon a documented
    # step, so on any Mac where `smbpal setup` has been run the message is
    # "not allowed to connect" instead, and the test failed on a machine that
    # was working correctly. A test that depends on whether the person has
    # installed the rest of the product is testing their machine.
    #
    # So it pins what is true either way, and both halves are former bugs:
    output = shell_output("#{bin}/smbpal ping 2>&1", 3)
    # The macOS socket path. `/run` cannot exist on the Signed System Volume,
    # and 0.2.9 fixed a client that looked for it there anyway.
    assert_match "/var/run/smbpal/smbpald.sock", output
    # The advice has to be runnable on this platform. `systemctl` is not a
    # command macOS has -- and `usermod` is not either, which 0.2.9 told people
    # to run and 0.2.10 fixed to `dscl`. One of these is a regression test for
    # a sentence that shipped.
    refute_match "systemctl", output
    refute_match "usermod", output

    # The toolkit the two heaviest dependencies are here for. Importing it from
    # the installed virtualenv is the only check that `system_site_packages` did
    # its job; everything above is standard library.
    #
    # **It stops short of `from gi.repository import Gtk`, and that is not
    # timidity.** PyGObject's Gtk override calls `gtk_init_check()` at import,
    # which on macOS opens a GDK display, which registers the process with the
    # window server — and in a context that has no window server, such as this
    # one, `HIServices _RegisterApplication` calls `abort()`. The process dies
    # with `Abort trap: 6`, no Python exception and no message. Diagnosed from
    # the crash report on 2 October 2026 after `shell_output` reported only
    # "Expected: 0, Actual: nil".
    #
    # So this asserts exactly what the dependencies are here to provide: `gi`
    # importable from the venv, and a Gtk 4.0 typelib for it to find.
    (testpath/"toolkit.py").write <<~PYTHON
      import gi

      gi.require_version("Gtk", "4.0")
      from gi.repository import GLib

      print("gi", gi.__version__, "glib", GLib.MAJOR_VERSION)
    PYTHON
    assert_match "glib 2",
      shell_output("#{libexec}/bin/python #{testpath}/toolkit.py 2>&1")
  end
end
