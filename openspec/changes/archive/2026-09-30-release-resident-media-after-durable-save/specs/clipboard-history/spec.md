## ADDED Requirements

### Requirement: Release resident heavy media after durable commit
Copythat SHALL eventually release resident image and link-preview image bytes from history and its filtered copies after the corresponding item and media identity have successfully completed the existing blob-first, atomic-manifest persistence transaction and release no longer disrupts visible previews. Release MUST preserve stable blob references, all item metadata, source icons, content identity, payload presence, and search and organization behavior. Copythat MUST NOT release an identity that has not successfully committed, infer commitment from a requested save or elapsed time, or request persistence solely because residency changed.

#### Scenario: Image commits while history is not visible
- **WHEN** a snapshot containing resident image bytes successfully commits and history is not visible
- **THEN** matching image bytes are released from both history and filtered history after committed-media cache seeding
- **AND** the image reference, metadata, content key, and image payload presence remain unchanged
- **AND** release requests no additional save generation or manifest write

#### Scenario: Link-preview image commits
- **WHEN** a snapshot containing a resident link-preview image successfully commits and release will not disrupt a visible preview
- **THEN** matching preview bytes are released from history and filtered history after committed-media cache seeding
- **AND** its image reference, link title, restorable URL, source context, and pinboard state remain unchanged
- **AND** the image remains present for enrichment eligibility without another metadata or browser request

#### Scenario: Save fails and is retried
- **WHEN** a required blob write or manifest commit fails for resident heavy media
- **THEN** that failed transaction does not authorize release or committed-media seeding
- **AND** uncommitted resident bytes and the latest retry snapshot remain available
- **WHEN** retry successfully commits the matching media identity
- **THEN** the bytes become eligible for release under the same visibility and identity rules
- **AND** normal Quit retains its Retry, Quit Anyway, and Cancel Quit behavior

#### Scenario: Older commit meets a newer payload
- **WHEN** an older generation commits media A for an item whose current resident media of that role is B with a different blob identity
- **THEN** the older commit does not release B
- **AND** B remains resident until its own identity successfully commits
- **AND** image and link-preview image eligibility are evaluated independently

#### Scenario: Intermediate snapshots are coalesced
- **WHEN** pending generations are superseded while another generation is saving
- **THEN** only snapshots that actually commit authorize media release
- **AND** an older successful generation does not discard the latest pending or failed retry snapshot

#### Scenario: Latest retry snapshot is no longer needed
- **WHEN** the latest requested generation successfully commits
- **THEN** the save coordinator stops retaining that snapshot for retry
- **AND** callback completion leaves no durable-release queue retaining its media bytes

#### Scenario: Media commits while previews are visible
- **WHEN** resident media commits while its preview is visible
- **THEN** committed bytes are offered to the bounded cache without a resident-to-placeholder display regression
- **AND** history ownership is released when the visibility boundary permits it
- **AND** reopening uses the existing on-demand media path

#### Scenario: State changes during committed-media handling
- **WHEN** an item is removed or replaced, or the panel closes or reopens, while committed-media seeding is pending
- **THEN** release uses the current item identity and visibility when seeding completes
- **AND** removed items are not recreated, newer unmatched media remain resident, and visible previews remain stable

#### Scenario: Flush waits for committed-media handling
- **WHEN** a normal save flush is waiting on a successful commit whose media handling is still in progress
- **THEN** successful flush completion waits for cache seeding and the release-or-defer decision
- **AND** a visible panel does not make flush wait for the user to close it

#### Scenario: Metadata changes after release
- **WHEN** a released image or preview item is pinned, moved to a pinboard, or affected by pinboard rename
- **THEN** its blob references and content identity survive the mutation and subsequent save
- **AND** the metadata operation performs zero heavy-media reads and zero media hashes

#### Scenario: Paste and drag after release
- **WHEN** a user pastes or drags an image whose resident history bytes have been released
- **THEN** the existing on-demand media path supplies its image payload
- **AND** residency alone does not cause a missing payload, text fallback, or link-preview refetch
- **AND** actual blob-read failures retain the existing local failure behavior

## MODIFIED Requirements

### Requirement: Bound on-demand media retention
Copythat SHALL read and verify persisted heavy media outside MainActor and reuse successful loads through a byte-cost LRU cache keyed by blob ID with an internal 32 MiB budget. The same cache SHALL accept trusted finalized resident media after successful durable commit and before history releases those bytes, without disk reads, hashing, or re-encoding. Each hit SHALL refresh recency; insertion and eviction SHALL keep retained byte cost within budget, including repeated identities. A single blob exceeding the budget SHALL be returned by a load without caching and SHALL be skipped by committed-media seeding without preventing history release. Loading and seeding SHALL NOT populate the history array with media bytes, request persistence, change selection or start link enrichment. Actual disk reads SHALL retain existing integrity verification.

#### Scenario: Reuse and evict cached media
- **WHEN** a blob is loaded twice while retained
- **THEN** only the first access reads disk and the second refreshes recency
- **WHEN** subsequent insertion exceeds the byte budget
- **THEN** least recently used entries are evicted until retained byte cost is within budget

#### Scenario: Oversized blob
- **WHEN** a verified blob exceeds the cache byte budget
- **THEN** it is returned to the caller without being retained by the cache
- **AND** the next access reads disk again

#### Scenario: Load completes without history mutation
- **WHEN** display, paste or drag loads a restored payload
- **THEN** its history item retains references and empty heavy Data fields
- **AND** no save, selection update or link enrichment is caused by that load

#### Scenario: Reuse freshly committed media
- **WHEN** committed resident media is seeded and requested while still retained in the cache
- **THEN** seeding and the subsequent cache hit perform zero disk reads and zero media hashes
- **AND** the returned bytes match the finalized payload without re-encoding

#### Scenario: Batch seeding respects the budget
- **WHEN** committed-media seeding includes repeated identities or combined media larger than the budget
- **THEN** each retained identity is accounted for once and LRU eviction preserves the byte budget
- **AND** an evicted media identity can be released from history and subsequently loaded from disk

#### Scenario: Oversized committed media
- **WHEN** successfully committed resident media individually exceeds the cache budget
- **THEN** seeding does not retain it or increase the budget
- **AND** matching history ownership can still be released
- **AND** subsequent access reads and verifies the durable blob
