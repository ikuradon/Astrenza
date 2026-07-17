public struct NostrRelayInformationDocument: Codable, Equatable, Sendable {
    public let name: String?
    public let description: String?
    public let pubkey: String?
    public let contact: String?
    public let supportedNips: [Int]
    public let software: String?
    public let version: String?
    public let limitation: NostrRelayLimitation?

    public init(
        name: String?,
        description: String?,
        pubkey: String?,
        contact: String?,
        supportedNips: [Int],
        software: String?,
        version: String?,
        limitation: NostrRelayLimitation?
    ) {
        self.name = name
        self.description = description
        self.pubkey = pubkey
        self.contact = contact
        self.supportedNips = supportedNips
        self.software = software
        self.version = version
        self.limitation = limitation
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case pubkey
        case contact
        case supportedNips = "supported_nips"
        case software
        case version
        case limitation
    }
}

public struct NostrRelayLimitation: Codable, Equatable, Sendable {
    public let maxMessageLength: Int?
    public let maxSubscriptions: Int?
    public let maxLimit: Int?
    public let maxSubIDLength: Int?
    public let authRequired: Bool?
    public let paymentRequired: Bool?
    public let restrictedWrites: Bool?

    public init(
        maxMessageLength: Int? = nil,
        maxSubscriptions: Int? = nil,
        maxLimit: Int? = nil,
        maxSubIDLength: Int? = nil,
        authRequired: Bool? = nil,
        paymentRequired: Bool? = nil,
        restrictedWrites: Bool? = nil
    ) {
        self.maxMessageLength = maxMessageLength
        self.maxSubscriptions = maxSubscriptions
        self.maxLimit = maxLimit
        self.maxSubIDLength = maxSubIDLength
        self.authRequired = authRequired
        self.paymentRequired = paymentRequired
        self.restrictedWrites = restrictedWrites
    }

    enum CodingKeys: String, CodingKey {
        case maxMessageLength = "max_message_length"
        case maxSubscriptions = "max_subscriptions"
        case maxLimit = "max_limit"
        case maxSubIDLength = "max_subid_length"
        case authRequired = "auth_required"
        case paymentRequired = "payment_required"
        case restrictedWrites = "restricted_writes"
    }
}
