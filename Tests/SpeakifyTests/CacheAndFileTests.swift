import Foundation
import XCTest
@testable import Speakify

final class AudioCachePrunerTests: XCTestCase {
    private let retention: TimeInterval = 10 * 24 * 60 * 60
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testKeepsFreshEntriesUnderSizeLimit() {
        let entries = [
            makeEntry(key: "a", ageInDays: 1, size: 10),
            makeEntry(key: "b", ageInDays: 2, size: 10)
        ]

        let evicted = AudioCachePruner.entriesToEvict(
            from: entries,
            now: now,
            retention: retention,
            sizeLimit: 100
        )

        XCTAssertTrue(evicted.isEmpty)
    }

    func testEvictsEntriesPastRetentionRegardlessOfSize() {
        let entries = [
            makeEntry(key: "fresh", ageInDays: 1, size: 10),
            makeEntry(key: "stale", ageInDays: 11, size: 10)
        ]

        let evicted = AudioCachePruner.entriesToEvict(
            from: entries,
            now: now,
            retention: retention,
            sizeLimit: 1_000
        )

        XCTAssertEqual(evicted.map(\.key), ["stale"])
    }

    func testEvictsOldestFirstUntilUnderSizeLimit() {
        let entries = [
            makeEntry(key: "newest", ageInDays: 1, size: 60),
            makeEntry(key: "middle", ageInDays: 2, size: 60),
            makeEntry(key: "oldest", ageInDays: 3, size: 60)
        ]

        let evicted = AudioCachePruner.entriesToEvict(
            from: entries,
            now: now,
            retention: retention,
            sizeLimit: 100
        )

        // 180 bytes total: dropping the two oldest brings it to 60, under the limit.
        XCTAssertEqual(evicted.map(\.key), ["oldest", "middle"])
    }

    func testEvictionStopsAsSoonAsCacheFitsAgain() {
        let entries = [
            makeEntry(key: "newest", ageInDays: 1, size: 50),
            makeEntry(key: "oldest", ageInDays: 5, size: 60)
        ]

        let evicted = AudioCachePruner.entriesToEvict(
            from: entries,
            now: now,
            retention: retention,
            sizeLimit: 100
        )

        XCTAssertEqual(evicted.map(\.key), ["oldest"])
    }

    func testGroupsAudioAndAlignmentSidecarIntoOneEntry() throws {
        let directory = try makeTemporaryDirectory()
        let audioURL = directory.appending(path: "abc123.mp3")
        let alignmentURL = directory.appending(path: "abc123.alignment.json")
        try Data(repeating: 0, count: 30).write(to: audioURL)
        try Data(repeating: 0, count: 12).write(to: alignmentURL)

        let entries = AudioCachePruner.entries(from: [audioURL, alignmentURL])

        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.key, "abc123")
        XCTAssertEqual(entry.size, 42)
        XCTAssertEqual(Set(entry.urls), Set([audioURL, alignmentURL]))
    }

    private func makeEntry(key: String, ageInDays: Double, size: Int) -> AudioCacheEntry {
        AudioCacheEntry(
            key: key,
            urls: [URL(filePath: "/tmp/\(key).mp3")],
            modifiedAt: now.addingTimeInterval(-ageInDays * 24 * 60 * 60),
            size: size
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "speakify-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

final class FileNameFormatterAvailableURLTests: XCTestCase {
    func testReturnsRequestedNameWhenNothingExists() throws {
        let directory = try makeTemporaryDirectory()

        let url = FileNameFormatter.availableURL(in: directory, fileName: "speech.mp3", companionExtension: "srt")

        XCTAssertEqual(url.lastPathComponent, "speech.mp3")
    }

    func testSuffixesWhenAudioFileAlreadyExists() throws {
        let directory = try makeTemporaryDirectory()
        try Data().write(to: directory.appending(path: "speech.mp3"))

        let url = FileNameFormatter.availableURL(in: directory, fileName: "speech.mp3", companionExtension: "srt")

        XCTAssertEqual(url.lastPathComponent, "speech (2).mp3")
    }

    /// The audio slot is free but the subtitle slot is not; taking it would clobber
    /// the existing .srt, so the pair has to move on together.
    func testSuffixesWhenOnlyCompanionSubtitleExists() throws {
        let directory = try makeTemporaryDirectory()
        try Data().write(to: directory.appending(path: "speech.srt"))

        let url = FileNameFormatter.availableURL(in: directory, fileName: "speech.mp3", companionExtension: "srt")

        XCTAssertEqual(url.lastPathComponent, "speech (2).mp3")
    }

    func testSkipsPastConsecutiveCollisions() throws {
        let directory = try makeTemporaryDirectory()
        try Data().write(to: directory.appending(path: "speech.mp3"))
        try Data().write(to: directory.appending(path: "speech (2).mp3"))
        try Data().write(to: directory.appending(path: "speech (3).srt"))

        let url = FileNameFormatter.availableURL(in: directory, fileName: "speech.mp3", companionExtension: "srt")

        XCTAssertEqual(url.lastPathComponent, "speech (4).mp3")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "speakify-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
