# icalendar

A standalone Racket package using Gregor and `net/mime` for reading `.ics` files and
extracting useful calendar event information. See [SPEC.md](SPEC.md) for its
public API, exact parsing rules, limits, conformance scope and non-goals.

```sh
rackup run <toolchain> -- raco pkg install --auto https://github.com/samth/icalendar.git
rackup run <toolchain> -- raco test -p icalendar
```

```racket
(require icalendar)
(for ([event (calendar-events (call-with-input-file "invite.ics" parse-ics))])
  (displayln (event->text event)))
```

For development, clone this repository and use a linked package installation.
The mail clients pin this repository as a submodule and use a relative require;
no global package-manager changes are required to run them.
