import Foundation
import UIKit

enum RollMode: String, Codable, CaseIterable, Identifiable {
    case freeform
    case desaturated
    case blackAndWhite
    case highContrast

    var id: Self { self }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.freeform.rawValue:
            self = .freeform
        case Self.desaturated.rawValue:
            self = .desaturated
        case Self.blackAndWhite.rawValue:
            self = .blackAndWhite
        case Self.highContrast.rawValue:
            self = .highContrast
        case "softFocus", "motion":
            self = .freeform
        default:
            self = .freeform
        }
    }

    var title: String {
        switch self {
        case .freeform: return "Natural"
        case .desaturated: return "Desaturated"
        case .blackAndWhite: return "Black & White"
        case .highContrast: return "High Contrast"
        }
    }

    var description: String {
        switch self {
        case .freeform: return "Unscripted overlaps"
        case .desaturated: return "Muted color, soft memory"
        case .blackAndWhite: return "Silver-toned exposures"
        case .highContrast: return "Harder shadows"
        }
    }
}

enum RollPhase: String, Codable {
    case firstPass
    case secondPass
    case developing
    case complete
}

func shouldResumeToCamera(_ roll: Roll?) -> Bool {
    guard let roll, roll.blendedImages.isEmpty, roll.gridImage == nil else {
        return false
    }

    switch roll.phase {
    case .firstPass:
        return roll.firstPassImages.count < Roll.frameCount
    case .secondPass:
        return roll.firstPassImages.count == Roll.frameCount
            && roll.secondPassImages.count < Roll.frameCount
    case .developing, .complete:
        return false
    }
}

func isPartialRollInProgress(_ roll: Roll?) -> Bool {
    shouldResumeToCamera(roll)
}

func isValidResumeRoll(_ roll: Roll?, resume: ResumeRollState?) -> Bool {
    guard let roll, let resume else { return false }
    guard roll.id == resume.rollID else { return false }
    guard roll.blendedImages.isEmpty, roll.gridImage == nil else { return false }

    switch roll.phase {
    case .firstPass:
        return roll.firstPassImages.count < Roll.frameCount
    case .secondPass:
        return roll.secondPassImages.count < Roll.frameCount
    case .developing, .complete:
        return false
    }
}

struct CapturedFrame: Identifiable, Codable {
    let id: UUID
    let imageData: Data
    let timestamp: Date
    let metadata: [String: String]?

    init(
        id: UUID = UUID(),
        imageData: Data,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.timestamp = timestamp
        self.metadata = metadata
    }

    var image: UIImage? {
        UIImage(data: imageData)
    }
}

struct Roll: Identifiable, Codable {
    static let frameCount = 9

    let id: UUID
    let createdAt: Date
    let mode: RollMode
    var title: String
    var updatedAt: Date
    var phase: RollPhase
    var firstPassImages: [CapturedFrame]
    var secondPassImages: [CapturedFrame]
    var blendedImages: [UIImage]
    var gridImage: UIImage?

    init(id: UUID = UUID(), createdAt: Date = Date(), mode: RollMode, title: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.mode = mode
        self.title = title ?? RollTitleGenerator.fallbackTitle(for: createdAt)
        updatedAt = createdAt
        phase = .firstPass
        firstPassImages = []
        secondPassImages = []
        blendedImages = []
        gridImage = nil
    }

    init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        mode: RollMode,
        title: String,
        phase: RollPhase,
        firstPassImages: [CapturedFrame],
        secondPassImages: [CapturedFrame],
        blendedImages: [UIImage],
        gridImage: UIImage?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mode = mode
        self.title = title
        self.phase = phase
        self.firstPassImages = firstPassImages
        self.secondPassImages = secondPassImages
        self.blendedImages = blendedImages
        self.gridImage = gridImage
    }

    var capturedFrameCount: Int {
        phase == .firstPass ? firstPassImages.count : secondPassImages.count
    }

    var requiresCaptureInput: Bool {
        shouldResumeToCamera(self)
    }

    var correspondingFirstExposure: UIImage? {
        guard phase == .secondPass, secondPassImages.count < firstPassImages.count else {
            return nil
        }
        return firstPassImages[secondPassImages.count].image
    }

    mutating func append(_ frame: CapturedFrame) throws -> CaptureMilestone {
        updatedAt = Date()
        switch phase {
        case .firstPass:
            guard firstPassImages.count < Self.frameCount else { throw RollError.passAlreadyFull }
            firstPassImages.append(frame)
            if firstPassImages.count == Self.frameCount {
                phase = .secondPass
                return .firstPassComplete
            }
            return .frameCaptured
        case .secondPass:
            guard firstPassImages.count == Self.frameCount else { throw RollError.firstPassIncomplete }
            guard secondPassImages.count < Self.frameCount else { throw RollError.passAlreadyFull }
            secondPassImages.append(frame)
            if secondPassImages.count == Self.frameCount {
                phase = .developing
                return .secondPassComplete
            }
            return .frameCaptured
        case .developing, .complete:
            throw RollError.captureUnavailable
        }
    }

    mutating func finishDevelopment(images: [UIImage], gridImage: UIImage?) throws {
        guard phase == .developing, images.count == Self.frameCount else {
            throw RollError.developmentIncomplete
        }
        blendedImages = images
        self.gridImage = gridImage
        phase = .complete
        updatedAt = Date()
    }

    mutating func touch() {
        updatedAt = Date()
    }

    mutating func rename(to title: String) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedAt = Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, mode, title, phase, firstPassImages, secondPassImages, blendedImageData, gridImageData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        mode = try container.decode(RollMode.self, forKey: .mode)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? RollTitleGenerator.fallbackTitle(for: createdAt)
        phase = try container.decode(RollPhase.self, forKey: .phase)
        firstPassImages = try container.decode([CapturedFrame].self, forKey: .firstPassImages)
        secondPassImages = try container.decode([CapturedFrame].self, forKey: .secondPassImages)
        let encodedImages = try container.decodeIfPresent([Data].self, forKey: .blendedImageData) ?? []
        blendedImages = encodedImages.compactMap(UIImage.init(data:))
        gridImage = try container.decodeIfPresent(Data.self, forKey: .gridImageData).flatMap(UIImage.init(data:))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(mode, forKey: .mode)
        try container.encode(title, forKey: .title)
        try container.encode(phase, forKey: .phase)
        try container.encode(firstPassImages, forKey: .firstPassImages)
        try container.encode(secondPassImages, forKey: .secondPassImages)
        try container.encode(blendedImages.compactMap { $0.jpegData(compressionQuality: 0.96) }, forKey: .blendedImageData)
        try container.encodeIfPresent(gridImage?.jpegData(compressionQuality: 0.96), forKey: .gridImageData)
    }
}

struct RollManifest: Codable {
    struct FrameReference: Codable {
        let id: UUID
        let relativePath: String
        let timestamp: Date
        let metadata: [String: String]?
    }

    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let mode: RollMode
    let title: String
    let phase: RollPhase
    let currentFrameIndex: Int
    let firstPassFrames: [FrameReference]
    let secondPassFrames: [FrameReference]
    let blendedFramePaths: [String]
    let gridPath: String?

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, mode, title, phase, currentFrameIndex, firstPassFrames, secondPassFrames, blendedFramePaths, gridPath
    }

    init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        mode: RollMode,
        title: String,
        phase: RollPhase,
        currentFrameIndex: Int,
        firstPassFrames: [FrameReference],
        secondPassFrames: [FrameReference],
        blendedFramePaths: [String],
        gridPath: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mode = mode
        self.title = title
        self.phase = phase
        self.currentFrameIndex = currentFrameIndex
        self.firstPassFrames = firstPassFrames
        self.secondPassFrames = secondPassFrames
        self.blendedFramePaths = blendedFramePaths
        self.gridPath = gridPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        mode = try container.decode(RollMode.self, forKey: .mode)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? RollTitleGenerator.fallbackTitle(for: createdAt)
        phase = try container.decode(RollPhase.self, forKey: .phase)
        currentFrameIndex = try container.decode(Int.self, forKey: .currentFrameIndex)
        firstPassFrames = try container.decode([FrameReference].self, forKey: .firstPassFrames)
        secondPassFrames = try container.decode([FrameReference].self, forKey: .secondPassFrames)
        blendedFramePaths = try container.decode([String].self, forKey: .blendedFramePaths)
        gridPath = try container.decodeIfPresent(String.self, forKey: .gridPath)
    }
}

struct RollResumeState: Codable, Identifiable, Equatable {
    let id: UUID
    let updatedAt: Date
    let mode: RollMode
    let title: String
    let phase: RollPhase
    let frameCount: Int

    init(id: UUID, updatedAt: Date, mode: RollMode, title: String, phase: RollPhase, frameCount: Int) {
        self.id = id
        self.updatedAt = updatedAt
        self.mode = mode
        self.title = title
        self.phase = phase
        self.frameCount = frameCount
    }

    init(roll: Roll) {
        self.init(
            id: roll.id,
            updatedAt: roll.updatedAt,
            mode: roll.mode,
            title: roll.title,
            phase: roll.phase,
            frameCount: roll.capturedFrameCount
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, updatedAt, mode, title, phase, frameCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        mode = try container.decode(RollMode.self, forKey: .mode)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? RollTitleGenerator.fallbackTitle(for: updatedAt)
        phase = try container.decode(RollPhase.self, forKey: .phase)
        frameCount = try container.decode(Int.self, forKey: .frameCount)
    }
}

struct ResumeRollState: Codable, Equatable {
    let rollID: UUID
    let phase: RollPhase
    let firstPassCount: Int
    let secondPassCount: Int
    let updatedAt: Date

    init(
        rollID: UUID,
        phase: RollPhase,
        firstPassCount: Int,
        secondPassCount: Int,
        updatedAt: Date
    ) {
        self.rollID = rollID
        self.phase = phase
        self.firstPassCount = firstPassCount
        self.secondPassCount = secondPassCount
        self.updatedAt = updatedAt
    }

    init?(roll: Roll) {
        guard shouldResumeToCamera(roll) else { return nil }
        self.init(
            rollID: roll.id,
            phase: roll.phase,
            firstPassCount: roll.firstPassImages.count,
            secondPassCount: roll.secondPassImages.count,
            updatedAt: roll.updatedAt
        )
    }
}

enum CaptureMilestone {
    case frameCaptured
    case firstPassComplete
    case secondPassComplete
}

enum RollError: LocalizedError {
    case passAlreadyFull
    case firstPassIncomplete
    case captureUnavailable
    case developmentIncomplete
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .passAlreadyFull: return "This exposure pass already contains nine frames."
        case .firstPassIncomplete: return "The first exposure must be completed first."
        case .captureUnavailable: return "This roll is no longer accepting exposures."
        case .developmentIncomplete: return "Nine developed frames are required."
        case .imageEncodingFailed: return "The captured image could not be stored."
        }
    }
}
