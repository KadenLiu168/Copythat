import Foundation

// MARK: - Durable media release

extension ClipboardStore {
    /// Applies one successfully committed snapshot: committed bytes are offered
    /// to the bounded cache first, then still-matching resident roles become
    /// eligible for release. Current identity and visibility are read after
    /// seeding, so deletions, replacements, and panel transitions during the
    /// suspension decide the outcome.
    func handleDurableMediaCommit(_ commit: ClipboardHistoryDurableMediaCommit) async {
        // History is newest first, so reversing offers media oldest-to-newest
        // and leaves the newest committed entries most recent under pressure.
        await mediaLoader.seedCommitted(commit.entries.reversed().flatMap(\.preparedMedia))
        mergePendingDurableMediaRelease(from: commit)
        if !panelVisible {
            consumePendingDurableMediaRelease()
        }
    }

    /// References-only view of the deferred release queue, so ownership tests
    /// can assert it retains no media bytes.
    var pendingDurableReleaseReferences: [UUID: DurableMediaReferences] {
        pendingDurableMediaRelease
    }

    /// Keeps only roles whose current resident bytes still carry the committed
    /// address. Pending state is proof for one specific identity, never blanket
    /// permission to clear an item, so a changed identity keeps its bytes until
    /// its own commit succeeds.
    private func mergePendingDurableMediaRelease(from commit: ClipboardHistoryDurableMediaCommit) {
        let currentItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for entry in commit.entries {
            guard let item = currentItems[entry.itemID] else { continue }
            var commits = DurableMediaReferences()
            if let image = entry.image, item.imageData != nil, item.imageBlobID == image.id {
                commits.imageBlobID = image.id
            }
            if let linkImage = entry.linkImage, item.linkImageData != nil, item.linkImageBlobID == linkImage.id {
                commits.linkImageBlobID = linkImage.id
            }
            guard commits != DurableMediaReferences() else { continue }
            var pending = pendingDurableMediaRelease[entry.itemID] ?? DurableMediaReferences()
            if let imageBlobID = commits.imageBlobID {
                pending.imageBlobID = imageBlobID
            }
            if let linkImageBlobID = commits.linkImageBlobID {
                pending.linkImageBlobID = linkImageBlobID
            }
            pendingDurableMediaRelease[entry.itemID] = pending
        }
    }

    /// Releases every pending identity that still matches resident bytes and
    /// clears the queue. Each array is assigned at most once, and no filter,
    /// selection, preview, or persistence work is triggered. Internal because
    /// panel close and the class body call it from another file.
    func consumePendingDurableMediaRelease() {
        guard !pendingDurableMediaRelease.isEmpty else { return }
        let pending = pendingDurableMediaRelease
        pendingDurableMediaRelease.removeAll()
        publishReleasedResidentMedia(
            items: releasingResidentMedia(in: items, pending: pending),
            filteredItems: releasingResidentMedia(in: filteredItems, pending: pending)
        )
    }

    private func releasingResidentMedia(
        in history: [ClipboardItem],
        pending: [UUID: DurableMediaReferences]
    ) -> [ClipboardItem]? {
        var updated = history
        var didRelease = false
        for index in updated.indices {
            guard let references = pending[updated[index].id],
                  let released = updated[index].releasingResidentMedia(
                      durableImageBlobID: references.imageBlobID,
                      durableLinkImageBlobID: references.linkImageBlobID
                  ) else { continue }
            updated[index] = released
            didRelease = true
        }
        return didRelease ? updated : nil
    }

    /// Drops deferred proofs for items that no longer exist, so an indefinitely
    /// open panel cannot accumulate obsolete identities.
    func discardPendingDurableMediaRelease(forRemovedItemIDs removedIDs: [UUID]) {
        for itemID in removedIDs {
            pendingDurableMediaRelease[itemID] = nil
        }
    }

    func discardPendingDurableMediaRelease(itemID: UUID, droppingLinkImage: Bool) {
        guard var pending = pendingDurableMediaRelease[itemID] else { return }
        if droppingLinkImage {
            pending.linkImageBlobID = nil
        } else {
            pending.imageBlobID = nil
        }
        pendingDurableMediaRelease[itemID] = pending == DurableMediaReferences() ? nil : pending
    }
}
