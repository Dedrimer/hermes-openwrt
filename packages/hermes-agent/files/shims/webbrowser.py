"""Stand-in for CPython's `webbrowser` module, which OpenWrt does not ship.

This is not a Hermes patch. It is a missing piece of the standard library:
OpenWrt's python3 packaging splits the stdlib into ~20 subpackages and
`webbrowser.py` is in none of them -- there is no `python3-webbrowser` to
depend on. Upstream imports it at module top level in `hermes_cli/auth.py` and
`hermes_cli/portal_cli.py`, and `main()` imports both while building its
argument parser, so without this file *every* subcommand dies before it starts:

    File ".../hermes_cli/portal_cli.py", line 24, in <module>
        import webbrowser
    ModuleNotFoundError: No module named 'webbrowser'

Only `open()` and `get()` are ever used (11 and 2 call sites). Both are
implemented here with the behaviour the stdlib documents for "no usable
browser", which is also the truth on a router: `open()` returns False and
`get()` raises Error. Callers already handle both -- Hermes prints the URL for
the user to open somewhere else, which is exactly right when the machine has no
display.

Lives in a shims directory that hermes-wrapper appends *after* the private
site-packages, so it can never shadow a real dependency.
"""

__all__ = ['Error', 'open', 'open_new', 'open_new_tab', 'get', 'register']


class Error(Exception):
    """Raised when no browser is available, as the stdlib does."""


def open(url, new=0, autoraise=True):  # noqa: A001 - stdlib name
    """Report that nothing could be opened.

    False is the stdlib's documented return for a failed launch, so callers
    fall back to printing the URL instead of assuming a browser appeared.
    """
    return False


def open_new(url):
    return False


def open_new_tab(url):
    return False


def get(using=None):
    raise Error('no runnable browser on OpenWrt')


def register(name, klass, instance=None, *, preferred=False):
    """Accept registrations and forget them; there is nothing to register with."""
    return None
