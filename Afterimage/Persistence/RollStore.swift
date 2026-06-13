import Foundation
import UIKit

struct RollLoadResult {
    let rolls: [Roll]
    let unavailableRollCount: Int
    let repairedRollCount: Int
}

enum ResumeRollCache {
    private static let key = "afterimage.resumeRollState"

    static func load() -> ResumeRollState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder.nine.decode(ResumeRollState.self, from: data)
    }

    static func save(_ state: ResumeRollState?) {
        if let state,
           let data = try? JSONEncoder.nine.encode(state) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func clear() {
        save(nil)
    }
}

actor RollStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directoryURL = documents.appendingPathComponent("Rolls", isDirectory: true)
        print("[Nine] RollStore initialized · \(directoryURL.path)")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadRolls() throws -> RollLoadResult {
        try createDirectoryIfNeeded()

        let entries = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        print("[Nine] RollStore scanning · entries: \(entries.count)")
        var rolls: [Roll] = []
        var restoredIDs = Set<UUID>()
        var unavailableCount = 0
        var repairedCount = 0

        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  fileManager.fileExists(atPath: manifestURL(in: entry).path) else { continue }
            do {
                let restoration = try restoreRoll(from: entry)
                rolls.append(restoration.roll)
                restoredIDs.insert(restoration.roll.id)
                if restoration.wasRepaired {
                    repairedCount += 1
                    try save(restoration.roll)
                }
            } catch {
                unavailableCount += 1
            }
        }

        // Earlier versions stored each roll as one top-level JSON file.
        for entry in entries where entry.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: entry)
                var roll = try decoder.decode(Roll.self, from: data)
                guard !restoredIDs.contains(roll.id) else { continue }
                if roll.phase == .complete, roll.gridImage == nil {
                    roll.gridImage = GridRenderer.render(images: roll.blendedImages)
                    repairedCount += 1
                }
                try save(roll)
                rolls.append(roll)
                restoredIDs.insert(roll.id)
            } catch {
                unavailableCount += 1
            }
        }

        let sortedRolls = rolls.sorted { $0.updatedAt > $1.updatedAt }
        print("[Nine] RollStore scan completed · rolls: \(sortedRolls.count) · active: \(sortedRolls.contains { $0.requiresCaptureInput }) · completed: \(sortedRolls.filter { $0.phase == .complete }.count)")

        return RollLoadResult(
            rolls: sortedRolls,
            unavailableRollCount: unavailableCount,
            repairedRollCount: repairedCount
        )
    }

    func save(_ roll: Roll) throws {
        try createDirectoryIfNeeded()
        let rollDirectory = directoryURL.appendingPathComponent(roll.id.uuidString, isDirectory: true)
        try createRollDirectories(in: rollDirectory)

        let first = try persistCapturedFrames(roll.firstPassImages, folder: "first", in: rollDirectory)
        let second = try persistCapturedFrames(roll.secondPassImages, folder: "second", in: rollDirectory)
        let blendedPaths = try persistDevelopedFrames(roll.blendedImages, in: rollDirectory)
        let gridPath = try persistGridImage(roll.gridImage, in: rollDirectory)
        let manifest = RollManifest(
            id: roll.id,
            createdAt: roll.createdAt,
            updatedAt: roll.updatedAt,
            mode: roll.mode,
            title: roll.title,
            phase: roll.phase,
            currentFrameIndex: roll.capturedFrameCount,
            firstPassFrames: first,
            secondPassFrames: second,
            blendedFramePaths: blendedPaths,
            gridPath: gridPath
        )
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL(in: rollDirectory), options: .atomic)
        ResumeRollCache.save(ResumeRollState(roll: roll))
    }

    func loadRoll(id: UUID) throws -> Roll? {
        try createDirectoryIfNeeded()
        let rollDirectory = directoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: manifestURL(in: rollDirectory).path) {
            return try restoreRoll(from: rollDirectory).roll
        }

        let legacyURL = directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        guard fileManager.fileExists(atPath: legacyURL.path) else { return nil }
        let data = try Data(contentsOf: legacyURL)
        return try decoder.decode(Roll.self, from: data)
    }

    func discard(_ roll: Roll) throws {
        try discardRoll(id: roll.id)
    }

    func discardRoll(id: UUID) throws {
        let rollDirectory = directoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: rollDirectory.path) {
            try fileManager.removeItem(at: rollDirectory)
        }

        let legacyURL = directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        if fileManager.fileExists(atPath: legacyURL.path) {
            try fileManager.removeItem(at: legacyURL)
        }
        if ResumeRollCache.load()?.rollID == id {
            ResumeRollCache.clear()
        }
    }

    private func restoreRoll(from rollDirectory: URL) throws -> (roll: Roll, wasRepaired: Bool) {
        let data = try Data(contentsOf: manifestURL(in: rollDirectory))
        let manifest = try decoder.decode(RollManifest.self, from: data)
        let first = restoreCapturedFrames(
            from: "first",
            references: manifest.firstPassFrames,
            in: rollDirectory
        )
        let second = first.count == Roll.frameCount
            ? restoreCapturedFrames(from: "second", references: manifest.secondPassFrames, in: rollDirectory)
            : []
        let blended = restoreDevelopedFrames(in: rollDirectory)
        let movedOrphanedFirst = try quarantineFiles(after: first.count, in: "first", under: rollDirectory)
        let movedOrphanedSecond = try quarantineFiles(after: second.count, in: "second", under: rollDirectory)
        let movedOrphanedBlended = try quarantineFiles(after: blended.count, in: "blended", under: rollDirectory)

        let safePhase: RollPhase
        if blended.count == Roll.frameCount {
            safePhase = .complete
        } else if first.count < Roll.frameCount {
            safePhase = .firstPass
        } else if second.count < Roll.frameCount {
            safePhase = .secondPass
        } else {
            safePhase = .developing
        }

        let savedGridImage = safePhase == .complete ? restoreGridImage(in: rollDirectory) : nil
        let gridImage = safePhase == .complete
            ? savedGridImage ?? GridRenderer.render(images: blended)
            : nil
        let roll = Roll(
            id: manifest.id,
            createdAt: manifest.createdAt,
            updatedAt: manifest.updatedAt,
            mode: manifest.mode,
            title: manifest.title,
            phase: safePhase,
            firstPassImages: first,
            secondPassImages: second,
            blendedImages: safePhase == .complete ? blended : [],
            gridImage: gridImage
        )
        let expectedFrameIndex = roll.capturedFrameCount
        let wasRepaired = manifest.phase != safePhase
            || manifest.currentFrameIndex != expectedFrameIndex
            || manifest.firstPassFrames.count != first.count
            || manifest.secondPassFrames.count != second.count
            || manifest.blendedFramePaths.count != roll.blendedImages.count
            || movedOrphanedFirst
            || movedOrphanedSecond
            || movedOrphanedBlended
            || (safePhase == .complete && savedGridImage == nil && gridImage != nil)
        return (roll, wasRepaired)
    }

    private func persistCapturedFrames(
        _ frames: [CapturedFrame],
        folder: String,
        in rollDirectory: URL
    ) throws -> [RollManifest.FrameReference] {
        try frames.prefix(Roll.frameCount).enumerated().map { index, frame in
            let relativePath = "\(folder)/\(filename(for: index))"
            try frame.imageData.write(
                to: rollDirectory.appendingPathComponent(relativePath),
                options: .atomic
            )
            return RollManifest.FrameReference(
                id: frame.id,
                relativePath: relativePath,
                timestamp: frame.timestamp,
                metadata: frame.metadata
            )
        }
    }

    private func persistDevelopedFrames(_ images: [UIImage], in rollDirectory: URL) throws -> [String] {
        try images.prefix(Roll.frameCount).enumerated().map { index, image in
            let relativePath = "blended/\(filename(for: index))"
            guard let data = GridRenderer.squareImage(image).jpegData(compressionQuality: 0.96) else {
                throw RollError.imageEncodingFailed
            }
            try data.write(to: rollDirectory.appendingPathComponent(relativePath), options: .atomic)
            return relativePath
        }
    }

    private func persistGridImage(_ image: UIImage?, in rollDirectory: URL) throws -> String? {
        guard let image,
              let data = GridRenderer.squareImage(image).jpegData(compressionQuality: 0.96) else {
            return nil
        }
        let relativePath = "grid.jpg"
        try data.write(to: rollDirectory.appendingPathComponent(relativePath), options: .atomic)
        return relativePath
    }

    private func restoreCapturedFrames(
        from folder: String,
        references: [RollManifest.FrameReference],
        in rollDirectory: URL
    ) -> [CapturedFrame] {
        let referencesByPath = Dictionary(uniqueKeysWithValues: references.map { ($0.relativePath, $0) })
        var frames: [CapturedFrame] = []
        for index in 0..<Roll.frameCount {
            let relativePath = "\(folder)/\(filename(for: index))"
            let url = rollDirectory.appendingPathComponent(relativePath)
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else { break }
            let reference = referencesByPath[relativePath]
            frames.append(CapturedFrame(
                id: reference?.id ?? UUID(),
                imageData: data,
                timestamp: reference?.timestamp ?? modificationDate(for: url),
                metadata: reference?.metadata
            ))
        }
        return frames
    }

    private func restoreDevelopedFrames(in rollDirectory: URL) -> [UIImage] {
        var images: [UIImage] = []
        for index in 0..<Roll.frameCount {
            guard let image = UIImage(
                contentsOfFile: rollDirectory.appendingPathComponent("blended/\(filename(for: index))").path
            ) else { break }
            images.append(image)
        }
        return images
    }

    private func restoreGridImage(in rollDirectory: URL) -> UIImage? {
        UIImage(contentsOfFile: rollDirectory.appendingPathComponent("grid.jpg").path)
    }

    private func quarantineFiles(after validCount: Int, in folder: String, under rollDirectory: URL) throws -> Bool {
        var movedFile = false
        let orphanedDirectory = rollDirectory.appendingPathComponent("orphaned", isDirectory: true)
        for index in validCount..<Roll.frameCount {
            let source = rollDirectory.appendingPathComponent("\(folder)/\(filename(for: index))")
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.createDirectory(at: orphanedDirectory, withIntermediateDirectories: true)
            let destination = orphanedDirectory.appendingPathComponent(
                "\(folder)-\(filename(for: index).replacingOccurrences(of: ".jpg", with: ""))-\(UUID().uuidString).jpg"
            )
            try fileManager.moveItem(at: source, to: destination)
            movedFile = true
        }
        return movedFile
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }

    private func createDirectoryIfNeeded() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func createRollDirectories(in rollDirectory: URL) throws {
        try fileManager.createDirectory(at: rollDirectory, withIntermediateDirectories: true)
        for folder in ["first", "second", "blended"] {
            try fileManager.createDirectory(
                at: rollDirectory.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func manifestURL(in rollDirectory: URL) -> URL {
        rollDirectory.appendingPathComponent("roll.json")
    }

    private func filename(for index: Int) -> String {
        String(format: "%03d.jpg", index + 1)
    }
}

private extension JSONEncoder {
    static var nine: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var nine: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
