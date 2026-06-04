// DTOs for the Hofund Mirror wire contract. Wire is snake_case; the Swift API is
// camelCase. Every divergence is pinned with explicit `CodingKeys` (port contract
// §1.3) — no automatic case-conversion strategy is used, which also keeps free-form
// `[String: JSONValue]` payload keys verbatim.

import Foundation

// MARK: - Enums

public enum ConsentLayer: String, Codable, Sendable {
    case care
    case research
    case productAnalytics = "product_analytics"
    case commercialCohort = "commercial_cohort"
}

public enum EventSource: String, Codable, Sendable {
    case user
    case system
}

// MARK: - Responses

public struct HealthCheckResponse: Codable, Sendable, Equatable {
    /// "ok" | "degraded" | "down" — kept as String for forward-compatibility.
    public let status: String
    public let version: String
    public let timestamp: String
}

public struct ConsentRecord: Codable, Sendable, Equatable {
    public let id: String
    public let layer: ConsentLayer
    public let accepted: Bool
    public let version: String
    public let acceptedAt: String?
    public let revokedAt: String?
    public let source: String?

    enum CodingKeys: String, CodingKey {
        case id, layer, accepted, version
        case acceptedAt = "accepted_at"
        case revokedAt = "revoked_at"
        case source
    }
}

public struct EventAck: Codable, Sendable, Equatable {
    public let id: String
    public let occurredAt: String
    public let protocolVersion: String
    public let source: EventSource

    enum CodingKeys: String, CodingKey {
        case id
        case occurredAt = "occurred_at"
        case protocolVersion = "protocol_version"
        case source
    }
}

public struct StoredEvent: Codable, Sendable, Equatable {
    public let id: String
    public let occurredAt: String
    public let protocolVersion: String
    public let source: EventSource
    public let payload: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case id
        case occurredAt = "occurred_at"
        case protocolVersion = "protocol_version"
        case source
        case payload
    }
}

public struct ListEventsResponse: Codable, Sendable, Equatable {
    public let events: [StoredEvent]
    public let count: Int
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case events, count
        case nextCursor = "next_cursor"
    }
}

public struct DeleteSubjectResponse: Codable, Sendable, Equatable {
    public let subjectUserId: String
    public let ledgerId: String
    public let deletedAt: String
    public let deleted: DeletedCounts

    public struct DeletedCounts: Codable, Sendable, Equatable {
        public let chainEvents: Int
        public let emaEvents: Int
        public let consentRecords: Int
        public let insightDeliveryLog: Int

        enum CodingKeys: String, CodingKey {
            case chainEvents = "chain_events"
            case emaEvents = "ema_events"
            case consentRecords = "consent_records"
            case insightDeliveryLog = "insight_delivery_log"
        }
    }

    enum CodingKeys: String, CodingKey {
        case subjectUserId = "subject_user_id"
        case ledgerId = "ledger_id"
        case deletedAt = "deleted_at"
        case deleted
    }
}

// Decodable-only: a response type. (BatchItemResult is a read-only union with no
// Encodable conformance, so BatchResponse must not require Encodable either.)
public struct BatchResponse: Decodable, Sendable, Equatable {
    public let count: Int
    public let results: [BatchItemResult]

    init(count: Int, results: [BatchItemResult]) {
        self.count = count
        self.results = results
    }
}

/// Per-item batch result — a discriminated union on `status` (port contract §3).
public enum BatchItemResult: Decodable, Sendable, Equatable {
    /// status ∈ { "created", "replayed" }
    case success(index: Int, status: String, event: EventAck)
    /// status ∈ { "validation_failed", "consent_missing", "unknown_protocol" }
    case failure(index: Int, status: String, error: String, details: JSONValue?)

    enum CodingKeys: String, CodingKey {
        case index, status, event, error, details
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let index = try c.decode(Int.self, forKey: .index)
        let status = try c.decode(String.self, forKey: .status)
        switch status {
        case "created", "replayed":
            let event = try c.decode(EventAck.self, forKey: .event)
            self = .success(index: index, status: status, event: event)
        default:
            let error = (try? c.decode(String.self, forKey: .error)) ?? ""
            let details = try? c.decode(JSONValue.self, forKey: .details)
            self = .failure(index: index, status: status, error: error, details: details)
        }
    }
}

// MARK: - Event payloads (all fields optional)

public struct ChainPayload: Codable, Sendable, Equatable {
    public var timeOfEvent: String?
    public var location: String?
    public var device: String?
    public var emotionalState: String?
    public var physicalState: String?
    public var socialContext: String?
    public var trigger: String?
    public var urgeIntensity: Double?
    public var thoughtContent: String?
    public var permissionBelief: String?
    public var preparatoryBehavior: String?
    /// "interrupted" | "used" | "unknown"
    public var outcome: String?
    public var immediateConsequence: String?
    public var delayedConsequence: String?
    public var repairAction: String?

    public init(
        timeOfEvent: String? = nil,
        location: String? = nil,
        device: String? = nil,
        emotionalState: String? = nil,
        physicalState: String? = nil,
        socialContext: String? = nil,
        trigger: String? = nil,
        urgeIntensity: Double? = nil,
        thoughtContent: String? = nil,
        permissionBelief: String? = nil,
        preparatoryBehavior: String? = nil,
        outcome: String? = nil,
        immediateConsequence: String? = nil,
        delayedConsequence: String? = nil,
        repairAction: String? = nil
    ) {
        self.timeOfEvent = timeOfEvent
        self.location = location
        self.device = device
        self.emotionalState = emotionalState
        self.physicalState = physicalState
        self.socialContext = socialContext
        self.trigger = trigger
        self.urgeIntensity = urgeIntensity
        self.thoughtContent = thoughtContent
        self.permissionBelief = permissionBelief
        self.preparatoryBehavior = preparatoryBehavior
        self.outcome = outcome
        self.immediateConsequence = immediateConsequence
        self.delayedConsequence = delayedConsequence
        self.repairAction = repairAction
    }

    enum CodingKeys: String, CodingKey {
        case timeOfEvent = "time_of_event"
        case location, device
        case emotionalState = "emotional_state"
        case physicalState = "physical_state"
        case socialContext = "social_context"
        case trigger
        case urgeIntensity = "urge_intensity"
        case thoughtContent = "thought_content"
        case permissionBelief = "permission_belief"
        case preparatoryBehavior = "preparatory_behavior"
        case outcome
        case immediateConsequence = "immediate_consequence"
        case delayedConsequence = "delayed_consequence"
        case repairAction = "repair_action"
    }
}

public struct EmaPayload: Codable, Sendable, Equatable {
    public var urgeIntensity: Double?
    public var trigger: String?
    public var affectiveState: String?
    public var deviceContext: String?
    /// "morning" | "midday" | "afternoon" | "evening" | "night"
    public var timeOfDay: String?
    public var locationType: String?
    public var loneliness: Double?
    public var fatigue: Double?
    public var stress: Double?
    public var conflict: Bool?
    public var substanceExposure: Bool?
    public var interventionSelected: String?
    public var interventionCompleted: Bool?
    public var urgeAfter: Double?
    public var usePrevented: Bool?

    public init(
        urgeIntensity: Double? = nil,
        trigger: String? = nil,
        affectiveState: String? = nil,
        deviceContext: String? = nil,
        timeOfDay: String? = nil,
        locationType: String? = nil,
        loneliness: Double? = nil,
        fatigue: Double? = nil,
        stress: Double? = nil,
        conflict: Bool? = nil,
        substanceExposure: Bool? = nil,
        interventionSelected: String? = nil,
        interventionCompleted: Bool? = nil,
        urgeAfter: Double? = nil,
        usePrevented: Bool? = nil
    ) {
        self.urgeIntensity = urgeIntensity
        self.trigger = trigger
        self.affectiveState = affectiveState
        self.deviceContext = deviceContext
        self.timeOfDay = timeOfDay
        self.locationType = locationType
        self.loneliness = loneliness
        self.fatigue = fatigue
        self.stress = stress
        self.conflict = conflict
        self.substanceExposure = substanceExposure
        self.interventionSelected = interventionSelected
        self.interventionCompleted = interventionCompleted
        self.urgeAfter = urgeAfter
        self.usePrevented = usePrevented
    }

    enum CodingKeys: String, CodingKey {
        case urgeIntensity = "urge_intensity"
        case trigger
        case affectiveState = "affective_state"
        case deviceContext = "device_context"
        case timeOfDay = "time_of_day"
        case locationType = "location_type"
        case loneliness, fatigue, stress, conflict
        case substanceExposure = "substance_exposure"
        case interventionSelected = "intervention_selected"
        case interventionCompleted = "intervention_completed"
        case urgeAfter = "urge_after"
        case usePrevented = "use_prevented"
    }
}

// MARK: - Inputs

public struct BatchEventInput: Sendable {
    public var subjectUserId: String
    public var occurredAt: String
    public var protocolVersion: String
    public var payload: [String: JSONValue]
    public var source: EventSource
    public var idempotencyKey: String?

    public init(
        subjectUserId: String,
        occurredAt: String,
        protocolVersion: String,
        payload: [String: JSONValue],
        source: EventSource = .user,
        idempotencyKey: String? = nil
    ) {
        self.subjectUserId = subjectUserId
        self.occurredAt = occurredAt
        self.protocolVersion = protocolVersion
        self.payload = payload
        self.source = source
        self.idempotencyKey = idempotencyKey
    }
}

public struct ListEventsInput: Sendable {
    public var subjectUserId: String
    public var from: String?
    public var to: String?
    public var protocolVersion: String?
    public var limit: Int?
    public var cursor: String?

    public init(
        subjectUserId: String,
        from: String? = nil,
        to: String? = nil,
        protocolVersion: String? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) {
        self.subjectUserId = subjectUserId
        self.from = from
        self.to = to
        self.protocolVersion = protocolVersion
        self.limit = limit
        self.cursor = cursor
    }
}

// MARK: - Internal request envelopes (encoded to the wire)

struct ConsentRequest: Encodable {
    let subjectUserId: String
    let layer: ConsentLayer
    let accepted: Bool
    let version: String
    let source: String?

    enum CodingKeys: String, CodingKey {
        case subjectUserId = "subject_user_id"
        case layer, accepted, version, source
    }
}

struct ChainEventRequest: Encodable {
    let subjectUserId: String
    let occurredAt: String
    let protocolVersion: String
    let source: EventSource
    let chain: ChainPayload

    enum CodingKeys: String, CodingKey {
        case subjectUserId = "subject_user_id"
        case occurredAt = "occurred_at"
        case protocolVersion = "protocol_version"
        case source, chain
    }
}

struct EmaEventRequest: Encodable {
    let subjectUserId: String
    let occurredAt: String
    let protocolVersion: String
    let source: EventSource
    let ema: EmaPayload

    enum CodingKeys: String, CodingKey {
        case subjectUserId = "subject_user_id"
        case occurredAt = "occurred_at"
        case protocolVersion = "protocol_version"
        case source, ema
    }
}

struct DeleteSubjectRequest: Encodable {
    let reason: String?
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case reason
        case requestId = "request_id"
    }
}

// MARK: - Internal response wrappers

struct ConsentRecordWrapper: Decodable {
    let record: ConsentRecord
}

struct ConsentListWrapper: Decodable {
    let records: [ConsentRecord]
}

struct EventAckWrapper: Decodable {
    let event: EventAck
}
