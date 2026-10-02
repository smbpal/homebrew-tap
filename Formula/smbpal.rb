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
  url "https://github.com/smbpal/smbpal-desktop/archive/refs/tags/v0.2.6.tar.gz"
  sha256 "692ba27bc0d1cf29876a113dbca0849d0ba985e954e5ff2930a89dc68737b54a"
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
      macOS support is in progress. What works today is the client half:

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

      Serving shares is not ported yet: it needs a privileged helper, and
      `smbpald` is a Linux service. The command line says so rather than
      pretending.
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

    # No daemon is listening and exit 3 is the documented code for that. The
    # assertion is on what it tells a Mac user to do: `systemctl` would be a
    # command this platform does not have.
    output = shell_output("#{bin}/smbpal ping 2>&1", 3)
    assert_match "no SMBPal daemon", output
    refute_match "systemctl", output

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
