## ADDED Requirements

### Requirement: Responsive clipboard capture
Copythat SHALL react promptly to supported user-initiated clipboard writes without remaining in permanent high-frequency pasteboard polling, and SHALL commit pasteboard content only after the final observed change count has remained unchanged for a minimum stability interval.

#### Scenario: Shortcut-triggered copy wakes capture monitoring
- **WHEN** monitoring is active and Copythat observes a supported copy, cut, or clipboard-screenshot keyboard action
- **THEN** Copythat enters or extends a bounded fast-observation period
- **AND** Copythat does not rely solely on the next idle polling interval to observe the resulting pasteboard change

#### Scenario: Clipboard content is committed only after time-based stability
- **WHEN** one logical copy operation causes multiple pasteboard change counts
- **THEN** Copythat restarts the stability interval whenever it observes a newer count
- **AND** Copythat reads and commits content only after the final observed count remains unchanged for the minimum stability interval
- **AND** transient intermediate content is not inserted into history

#### Scenario: A newer pending count replaces its observation context atomically
- **WHEN** another change count arrives before a pending count reaches the minimum stability interval
- **THEN** Copythat replaces the pending count, its first-observed source candidate, and its stability start time together
- **AND** the captured content and source attribution belong to the count that actually becomes stable

#### Scenario: Successive stable shortcut-driven copies are retained
- **WHEN** a shortcut-driven copy reaches the minimum stability interval and is captured
- **AND** another shortcut-driven copy occurs while the bounded fast-observation period remains active
- **THEN** Copythat records both stable values in newest-first history order

#### Scenario: Non-keyboard pasteboard activity enters fast observation after discovery
- **WHEN** idle monitoring first observes a pasteboard change without a supported shortcut wake signal
- **THEN** Copythat enters or extends a bounded fast-observation period for stability confirmation
- **AND** a short fast-observation tail remains after the stable change is processed so immediately following activity can be observed promptly

#### Scenario: Fast observation ends after inactivity
- **WHEN** no new copy intent or pasteboard activity extends the bounded fast-observation period
- **THEN** Copythat exits fast observation after its deadline
- **AND** subsequent idle monitoring remains at its low-frequency cadence

#### Scenario: Copythat-generated pasteboard writes terminate pending external capture
- **WHEN** Copythat writes or clears the pasteboard while an external change is pending
- **THEN** Copythat discards the pending observation and ends its current fast-observation period
- **AND** Copythat does not insert either the stale pending value or its own pasteboard write into history

#### Scenario: Shortcut observation is unavailable
- **WHEN** the existing keyboard event tap is unavailable
- **THEN** Copythat continues discovering clipboard activity through low-frequency idle polling
- **AND** discovered changes receive the same time-based stability confirmation without requesting new permissions

#### Scenario: Monitoring stops and restarts
- **WHEN** clipboard monitoring stops
- **THEN** pending observation and scheduled fast polling are invalidated, and copy-intent wakes received while stopped do not restart polling
- **AND** an explicit later restart can discover an external change written while monitoring was stopped

#### Scenario: Opening the panel does not bypass stability
- **WHEN** opening the panel triggers an explicit pasteboard poll before the pending count reaches the minimum stability interval
- **THEN** Copythat does not capture that pending content prematurely
