---
id: 11
title: Let utils download backends advertise what they can do (U13)
status: open
needs: 1
touches: gap/fetch.gi
---

# Let utils download backends advertise what they can do (U13)

`Download_Methods` is the documented extension point, but a backend says
nothing about itself, so a caller who needs one that streams to a file, or
follows redirects, has to match on backend *names*. `AM_BackendRank` in
`gap/fetch.gi` is exactly that hack, and it is the last download workaround
left here once task 1 lands.

A per-backend record — `streamsToFile`, `followsRedirects`, `supportsTimeout`,
`supportsHttps`, and after utils#105 `supportsResume` — turns the ranking into
a query.

There is a real bug behind this: IO's `SingleHTTPRequest` reports a 302 as a
*successful* download of an empty body. Any caller that does not checksum what
it got installs nothing at all, which is precisely the complaint in
gap-system/gap#4285 about technology transitions breaking packages.
