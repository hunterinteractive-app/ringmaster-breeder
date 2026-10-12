# Device calendar subscriptions

Calendar → Connect device calendar creates a private per-user, per-herd iCalendar URL.
Apple Calendar can open the webcal link directly. Google Calendar requires initial setup in a desktop browser: Other calendars → From URL; the subscribed calendar then syncs to Android. Subscribe rather than importing a static file.

The feed contains all-day breeding milestones, health dates, and active entries from the herd owner's linked Show account. Windows use start/final markers. Health timestamps use the browser timezone saved when creating the link. Calendar providers control polling; the six-hour refresh hint is not a guarantee.

Anyone holding the URL can read the feed. Tokens are cryptographically random, stored only in the private schema, and accessible through an authenticated owner-scoped management function. Every feed request rechecks active account and herd access. Rotation and revocation invalidate the old URL; calendar apps may retain cached events until the subscription is removed. Calendar changes must be made in Breeder.

The calendar-feed Edge Function intentionally disables gateway JWT verification because calendar clients cannot supply app sessions. It authenticates the 256-bit private bearer token and calls a service-only resolver. Responses are non-cacheable at the HTTP layer; errors return 503 rather than an empty calendar. Tokens are never logged by application code.

Verification: Node feed tests, SQL rollback access/lifecycle tests, Flutter analyzer and suite. Native builds currently use UTC for health-date projection; the deployed web app captures the device IANA timezone.
