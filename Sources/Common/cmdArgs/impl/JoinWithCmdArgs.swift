public struct JoinWithCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .joinWith,
        help: join_with_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
            "--by-rect": trueBoolFlag(\.byRect),
        ],
        posArgs: [newMandatoryPosArgParser(\.direction, parseCardinalDirectionArg, placeholder: CardinalDirection.unionLiteral)],
    )

    public init(direction: CardinalDirection) {
        self.commonState = .init([])
        self.direction = .initialized(direction)
    }

    public var direction: Lateinit<CardinalDirection> = .uninitialized
    public var byRect: Bool = false
}
