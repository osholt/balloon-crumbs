# Name Options

`Balloon Crumbs` is the working title. The balloon leaves a trail of position
pings behind it, the chase crew follows that trail to the landing site, and the
name says so in two words. It also carries the champagne-landing association
(crumbs, bread, the basket) without using a protected term.

A trademark, app-store, and domain check is still required.

## Decision history

`Hot Pursuit` was the first working title, inherited from the initial scaffold.
It was dropped because it collides with Electronic Arts' `Need for Speed: Hot
Pursuit` franchise — a live trademark in a moving-vehicle software category,
which is the worst possible neighbour for a vehicle-tracking app.

`Champagne Landing` and `Champagne Chase` were strong intermediate candidates.
Both were dropped because the Comité Champagne actively polices the word
`Champagne` in trademarks outside the appellation, including in unrelated
categories.

## Options considered

| Name | Pun / angle | Verdict |
|---|---|---|
| Balloon Crumbs | Breadcrumb position trail the crew follows home | **chosen** |
| Breadbasket | Balloon basket, breadcrumbs, and farmland all at once | strong runner-up |
| Ground Track | The aviation term for a flight's path over the ground | strong runner-up |
| Champagne Chase | The post-landing ceremony plus the crew's job | trademark risk |
| Champagne Landing | The post-landing ceremony | trademark risk |
| Cork and Crown | Bottle cork plus the crown of the envelope | viable |
| Pilot Light | Burner pilot light, the pilot, and a guiding light | viable |
| Landing Party | The crew that arrives at the landing site | viable |
| Dawn Chase | Balloons fly at first light for the calm air | viable |
| Loft & Found | "Lost and found" for balloon and chase | name of a TV series |
| Hot Pursuit | Burner heat plus the chase operation | EA trademark |
| Basket Case | Memorable comic option | too chaotic for a safety product |
| Ground Control | Clear crew role | broadly used elsewhere |
| Balloonatics | What balloonists call themselves | weak safety signal |
| Inflated Expectations | Strong joke | weak safety/product signal |

## Outstanding rename work

The rename covered the product surface only. Two things were deliberately left
alone:

1. **Bundle identifiers.** `dev.osholt.hotpursuit` is still the iOS bundle ID,
   the Android `applicationId`, and the Play package. Changing it creates a new
   app identity: new provisioning profiles, a new Play listing, and a broken
   TestFlight/closed-alpha track. The Apple provisioning profile names
   (`Hot Pursuit CarPlay Navigation Development` / `… App Store`) are portal
   artifacts that must be recreated in the Apple Developer console first.

2. **The sweep-rider role name.** `RideRole.tailEndCharlie` renders as
   `Hot Pursuit` in ~60 strings. That is the inherited motorcycle back-marker
   role, not the product, so it was not renamed to `Balloon Crumbs`. Ballooning
   has no equivalent role, so this is balloon-domain migration work — see
   [backlog.md](backlog.md).
