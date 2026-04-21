Pinned upstream WAMP conformance vectors used by Connectanum.

Source:
- repository: `https://github.com/wamp-proto/wamp-proto`
- branch: `fix_556`
- commit: `59303fd1290f472b29a40392caeca525d0324e37`

Status:
- upstream PR: `wamp-proto/wamp-proto#557`
- upstream suite is still open, so this repo vendors the currently useful
  single-message subset for CI and regression coverage

Included here:
- `singlemessage/basic/*.json`
- `singlemessage/advanced/cancel.json`
- `singlemessage/advanced/interrupt.json`
- `singlemessage/advanced/publish_with_publisher_exclusion_disabled.json`

Deliberately not included yet:
- message families we do not implement locally, such as `EVENT_RECEIVED`
- upstream sequence/router-level vectors that are not fully checked in or are
  still evolving in the open PR
