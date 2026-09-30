## ADDED Requirements

### Requirement: Reuse normalized searchable text for immediate search
Copythat SHALL reuse each item's already-normalized searchable text across repeated query changes while its searchable metadata is unchanged. Each item SHALL establish that text once when created or restored, and a link-preview enrichment SHALL replace the affected item's derived text before refreshed results are exposed. Search SHALL remain synchronous without introducing debounce or a background search delay, and SHALL preserve existing searchable fields, their order, space delimiter, localized case normalization, file-path matching, query trimming and Pinboard intersection behavior.

#### Scenario: Repeated queries over a full configured history
- **WHEN** 1000 items are created and at least five different search queries are applied without item enrichment
- **THEN** normalized searchable text is built exactly once per created item
- **AND** constructing the history view and changing queries cause zero additional corpus builds
- **AND** each query returns the matching items in their existing history order

#### Scenario: Every searchable field remains independently searchable
- **WHEN** a query matches a token unique to an item's title, preview, link title, source app, kind label or file path
- **THEN** that item matches through that field independently of the other searchable fields
- **AND** uppercase and lowercase queries, surrounding query whitespace and Chinese searchable text retain existing matching behavior

#### Scenario: Organization changes reuse normalized text
- **WHEN** items are pinned, unpinned, assigned to or removed from a Pinboard, or their Pinboard assignments are renamed or cleared
- **THEN** those changes produce zero additional corpus builds
- **AND** search results continue to intersect with the current Pinboard filter

#### Scenario: Media residency changes reuse normalized text
- **WHEN** an item's image or link-image bytes are storage-optimized, released after durable save or materialized for paste without link-preview enrichment
- **THEN** its normalized searchable text remains unchanged with zero additional corpus builds
- **AND** the item retains the same searchable metadata matches

#### Scenario: Link-preview enrichment replaces stale searchable text
- **WHEN** a link-preview enrichment replaces an item's displayed title and link title
- **THEN** exactly that item rebuilds its corpus once before search results refresh
- **AND** the new title immediately matches search
- **AND** a token present only in the replaced titles no longer matches that item
- **AND** unrelated items reuse their existing corpora

#### Scenario: Link-preview enrichment retains existing nil-title semantics
- **WHEN** an enrichment provides no title for an item with an existing link title
- **THEN** the displayed title remains and the link title is cleared
- **AND** the affected corpus is rebuilt once and reflects those resulting fields
- **AND** enrichment with unchanged titles or only a preview image also rebuilds the affected corpus once

### Requirement: Keep normalized searchable text out of persisted history
Normalized searchable text SHALL remain runtime-derived. Copythat MUST rebuild it from decoded metadata rather than read a persisted corpus. Legacy encoded items and V2 history manifests MUST NOT acquire `searchText` or `searchCorpus` fields or corpus blobs, and the V2 schema version SHALL remain 2 without migration.

#### Scenario: Legacy item round-trip
- **WHEN** an item is encoded in the legacy payload format and decoded again
- **THEN** the encoded item contains no search corpus fields
- **AND** decoding builds its corpus exactly once and retains correct metadata search matches
- **AND** unexpected input corpus fields do not override metadata-derived search

#### Scenario: V2 history is saved and restored into a new session
- **WHEN** items are saved as V2 history and restored into a new Store
- **THEN** the manifest version is 2 and neither manifest nor item records contain search corpus fields
- **AND** restoring each item builds its corpus once from metadata without corpus blob storage or migration
- **AND** subsequent Store initialization and queries cause zero additional corpus builds and retained metadata is searchable
