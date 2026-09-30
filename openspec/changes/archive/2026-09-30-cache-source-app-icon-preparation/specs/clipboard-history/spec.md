## ADDED Requirements

### Requirement: Reuse prepared source application icons

Copythat SHALL reuse a successfully prepared source application icon's bytes and established SHA256 content address across observations of the same reliably identified running application while its cache entry remains retained. A cache hit MUST perform zero application-icon retrievals, rasterizations, PNG encodings, and media identity hashes. Each miss or uncached observation SHALL attempt the existing bounded 160px PNG preparation at most once and establish at most one identity hash, only when preparation succeeds. Source-icon cache state SHALL be session-only, owned by source tracking, and bounded to at most 32 successful entries with least-recently-used eviction. Reuse MUST preserve existing source-attribution precedence, per-observation capture timestamp and pasteboard change-count context, and per-item captured icon correctness.

#### Scenario: Repeated observations while the entry is retained
- **WHEN** Copythat successfully prepares an icon for a reliably identified running source application and observes that same identity multiple times while its entry remains retained
- **THEN** only the first observation retrieves and prepares the icon and establishes its content address
- **AND** subsequent observations reuse identical icon bytes and content address without retrieval, rendering, encoding, or identity hashing
- **AND** each observation receives its own supplied capture timestamp and pasteboard change-count context, including absent change counts

#### Scenario: Different process generations or installation locations
- **WHEN** a source application has a different process identifier, launch date, or bundle location from a retained application identity
- **THEN** Copythat resolves and prepares its icon independently of that entry
- **AND** restarting an application or reusing a PID with a different launch date does not reuse the prior process generation's entry
- **AND** sharing a display name or bundle identifier does not cause distinct running identities to share an entry

#### Scenario: Reliable process generation is unavailable
- **WHEN** a source candidate has no valid positive process identifier or its launch date is unavailable
- **THEN** Copythat performs normal source attribution and attempts icon preparation for that observation without consulting or populating the source-icon cache
- **AND** unavailable identity metadata does not cause rejection of an otherwise valid source candidate
- **AND** a later observation with a reliable identity can establish a cache entry

#### Scenario: Icon preparation is unavailable
- **WHEN** source icon preparation fails to produce PNG bytes
- **THEN** Copythat continues source attribution with the resolved application name and no icon
- **AND** that failure creates no cache entry and does not evict a successful entry
- **AND** a later observation can retry and cache a successful preparation

#### Scenario: Least recently used entry is evicted
- **WHEN** a successful insertion exceeds the cache capacity
- **THEN** Copythat evicts the least recently used successful entry and retains no more than the capacity
- **AND** each cache hit refreshes that entry's recency
- **AND** observing an evicted identity can prepare its icon again even if the application is still running

#### Scenario: Eviction preserves captured history
- **WHEN** a source-icon entry is evicted or a later application observation supplies a different icon
- **THEN** already created source observations and history items retain their captured icon bytes and content address
- **AND** earlier cards do not change source name or icon because of cache mutation

#### Scenario: Prepared identity is forwarded through capture and save
- **WHEN** a retained prepared source icon is used to capture a text, URL, file, or image item and persist that item
- **THEN** the source icon's established content address is forwarded with its bytes without another source-icon identity hash or encoding
- **AND** history uses the existing persistence schema and keeps its existing integrity verification on actual blob reads
