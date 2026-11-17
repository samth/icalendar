# iCalendar reader package specification, version 0.1

This package parses iCalendar data and presents event information. Its normative
reference is [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545), with scheduling
METHOD semantics from [RFC 5546](https://www.rfc-editor.org/rfc/rfc5546) and
parameter caret escapes from [RFC 6868](https://www.rfc-editor.org/rfc/rfc6868).
This document specifies the supported behavior; this is a reader-oriented parser,
not a claim to implement every RFC validation rule or a calendar scheduling engine.
The package has no account, mail-client, GUI or database dependencies. It uses
Gregor for date/datetime values, validation and formatting, and Racket’s existing
`net/mime` parser for MIME structure and transfer decoding; it performs no network
operations.

## Public API

`(require icalendar)` after installing this directory as a linked package, or
require `main.rkt` directly. Runtime dependencies are `base`, `net-lib` and `gregor-lib`.

- `parse-ics source #:max-bytes [4194304] -> ical-component`: accepts a UTF-8
  string, bytes, or caller-owned input port. Reads at most `max-bytes + 1` bytes
  from a port and never closes it. Returns exactly one VCALENDAR tree.
- `component-properties component name -> (listof ical-property)`: matches a
  property name case-insensitively and retains duplicates in source order.
- `property-text property -> string`: decodes RFC TEXT escapes `\\`, `\,`,
  `\;` and `\n`/`\N`. Unknown escapes remain literal. Raw property values remain
  available separately. Call this for TEXT values, not arbitrary URIs.
- `calendar-events calendar -> (listof ical-event)`: projects direct VEVENT
  children in source order. Unknown components/properties remain in the tree.
  Does not synthesize recurring occurrences or merge updates with equal UIDs.
- `format-ical-time time-or-#f -> string` and `event->text event -> string`:
  deterministic plain-text presentation without HTML/Markdown interpretation,
  host time-zone conversion, URL fetching, or side effects.

Transparent immutable records:

| Record | Fields |
|---|---|
| `ical-component` | uppercase `name`, ordered `properties`, ordered child `children` |
| `ical-property` | uppercase `name`, immutable `parameters` hash from uppercase names to ordered string lists, raw unfolded `value` |
| `ical-time` | `value` as a Gregor `date` or wall-clock `datetime`, `zone` as UTC/TZID/empty, `leap-second?` |
| `ical-part` | MIME `name`, MIME `method`, parsed `calendar` or `#f`, `error` string or `#f` |
| `ical-person` | decoded `name`, address (mailto prefix removed), `role`, participation `status`, `rsvp?` |
| `ical-event` | `uid`, `title`, `start`, `end`, `duration`, `location`, `organizer`, `attendees`, `status`, `method`, `recurrence`, `recurrence-id`, `sequence`, `description`, `url`, `warnings` |
| `exn:fail:ical` | ordinary failure message and logical content `line` number, or `#f` for a document-wide failure |

Absent scalar event strings are empty; absent times/organizer are `#f`; absent
lists are empty. Missing SUMMARY becomes `Untitled event`. Repeated scalar
properties use the first value for presentation; every value remains available
in the source tree. ATTENDEE remains an ordered list. Recurrence and DURATION are
preserved strings, not evaluated programs or expanded schedules.

`ical-time-date` and `ical-time-clock` return display strings; `ical-time-all-day?`
distinguishes Gregor date values from datetimes. A leap second is explicitly
flagged while its Gregorian value uses second 59; formatting restores `60`. The
package never silently shifts that value into a different date.

`read-calendar-mime source #:max-bytes [4194304] -> (listof ical-part)` uses
`net/mime: mime-analyze` for MIME structure, multipart boundaries and base64/
quoted-printable decoding. It selects `text/calendar` entities or `.ics` attachment
filenames case-insensitively, including nested multipart/message entities.
Non-calendar parts are ignored. `racket/port` reencodes declared non-UTF-8 text
charsets before ICS parsing; absent/us-ascii declarations tolerate RFC 5545 UTF-8.
An invalid calendar part produces a part with `calendar=#f` and an error, allowing
other calendar parts to remain readable. Invalid MIME structure raises
`exn:fail:ical`. Empty byte/string/port sources are rejected consistently.
Inputs have the same caller-owned-port and byte-limit rules as
`parse-ics`; MIME traversal depth is limited to 32 after library parsing.
Filename/header support follows `net/mime` rather than a second hand-written MIME
parser. No attachment path is opened or URL fetched.

`calendar-part-events part` applies a MIME `method` only when VCALENDAR has no
METHOD. A conflicting MIME/body METHOD is reported as an event warning, with the
calendar body’s METHOD taking precedence. Errors yield no projected events.

## Syntax and decoding

1. Enforce the byte bound before parsing. Unfold CRLF (or tolerated LF) followed
   by one space or tab **at the byte level**, before UTF-8 decoding. Thus folding
   through a multibyte code point is handled correctly. A UTF-8 BOM is tolerated.
2. Accept CRLF or LF content lines and ignore empty lines. Parse the first colon
   outside quoted parameter values as the property/value separator. Semicolons,
   commas and equals signs in quoted parameters are not separators. URI colons
   and all content after the property/value separator remain opaque.
3. Names are ASCII letters/digits/hyphens and normalized to uppercase. Parameter
   values retain case, lose surrounding double quotes, and decode `^^`, `^n`
   and `^'`. Repeated parameter values accumulate in source order.
4. Match nested BEGIN/END names case-insensitively. Reject properties outside a
   component, mismatched/unclosed components, malformed content lines, unclosed
   parameter quotes, invalid UTF-8 and multiple/non-VCALENDAR roots.
5. Preserve unknown properties (including X- extensions), unknown components,
   VTIMEZONE definitions, VALARM contents and duplicates. Generic parsing does
   not enforce mandatory VERSION/PRODID/UID fields or every property cardinality.

Limits: 4 MiB by default (caller can choose another positive byte bound), 100000
logical lines, 262144 characters per logical line, nesting depth 32, and 4096
components. Fail with `exn:fail:ical` on a syntax/resource limit violation.

## Event projection and presentation

Support SUMMARY, UID, DTSTART, DTEND, DURATION, LOCATION, ORGANIZER, ATTENDEE,
STATUS, METHOD, RRULE, RECURRENCE-ID, SEQUENCE, DESCRIPTION and URL. Nested VALARM
properties cannot overwrite VEVENT fields. METHOD:CANCEL yields CANCELLED even
if STATUS is missing. METHOD:REPLY and attendee PARTSTAT/RSVP remain visible.

DATE and DATE-TIME values are distinguished. Use Gregor to validate Gregorian dates, leap
years and clock ranges and a possible leap second (60). Preserve UTC `Z`,
TZID values, and floating local time as distinct cases. Reject conflicting
VALUE/TZID combinations in the projection. A bad projected time becomes `#f`
plus a warning containing its field and original value; other event information
remains readable. Invalid syntax still rejects the entire document.

All-day DTEND is **exclusive** and renders as `Ends before`; it must never be
presented as an inclusive final day. A missing end is not invented. A DURATION
is displayed as supplied; supplying both DTEND and DURATION produces a warning.
Floating times explicitly say that the time zone is unspecified. Custom and IANA
TZID values are shown as written rather than guessed or silently converted.
Organizer names, attendee participation/RSVP, cancellation, recurrence rules,
exception RECURRENCE-ID and update sequence are included in the event summary.

No recurrence expansion (including EXDATE/RDATE evaluation), VTIMEZONE arithmetic,
calendar import, alarms, RSVP sending or serialization is performed. Those raw
properties remain accessible for future consumers. Callers must escape plain
text appropriately for their own rich-text renderer; this package never executes
URLs, attachments, descriptions or alarm actions.

## Verification

Run `rackup run <toolchain> -- raco test -y tests`. Tests cover folding across
UTF-8 octets, quoted parameters/caret escapes, TEXT escapes, nested components,
multiple events, cancellation/replies, recurrence preservation, UTC/TZID/floating
and all-day dates, leap days, malformed inputs and resource bounds. Mail-client
integration tests separately cover MIME discovery, attachment hydration, caching
and presentation; they are not dependencies of this package.
