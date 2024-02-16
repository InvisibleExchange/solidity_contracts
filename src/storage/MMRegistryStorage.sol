// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract MMRegistryStorage {
    // * EVENTS --------------------------------------------

    event newPerpMMRegistration(
        address mmOwner,
        uint32 syntheticAsset,
        uint256 positionAddress,
        uint32 vlpTokenId,
        uint32 indexed mmActionId
    );
    event ClosePositionEvent(
        uint256 positionAddress,
        address mmOwner,
        uint64 initialValueSum,
        uint64 vlpAmountSum,
        uint32 indexed mmActionId
    );
    event AddLiquidity(
        address depositor,
        uint256 mmPositionAddress,
        uint64 usdcAmount,
        uint32 indexed mmActionId
    );
    event RemoveLiquidity(
        address depositor,
        uint256 mmPositionAddress,
        uint64 initialValue,
        uint64 vlpAmount,
        uint32 indexed mmActionId
    );

    // * STRUCTS --------------------------------------------

    struct PerpMMRegistration {
        address mmOwner;
        uint32 syntheticAsset;
        uint256 positionAddress;
        uint32 vlpTokenId;
        uint64 vlpAmount;
    }

    struct Cancelation {
        address depositor;
        uint256 mmAddress;
    }
    struct LiquidityInfo {
        uint64 initialValue;
        uint64 vlpAmount;
    }
    struct ClosedPositionLiquidityInfo {
        uint64 vlpAmountSum;
        uint64 returnCollateral;
    }

    // * STORAGE --------------------------------------------

    uint32 constant USDC_TOKEN_ID = 2413654107;

    // * Mm Add/Remove Liquidity
    mapping(address => mapping(uint256 => uint64))
        public s_pendingAddLiqudityRequests; // depositor => mm_position_address => scaled_amount

    Cancelation[] s_pendingCancellations;

    mapping(address => mapping(uint256 => LiquidityInfo))
        public s_activeLiqudity; // depositor => mm_position_address => LiquidityInfo

    mapping(uint256 => uint64) public s_providedUsdcLiquidity; // mm_position_address => usdc_amount
    mapping(uint256 => uint64) public s_aggregateVlpIssued; // mm_position_address => vlp issued

    mapping(bytes32 => uint256) public s_pendingRemoveLiqudityRequests; // keccak256(depositor, mm_position_address) => timestamp

    mapping(address => uint256) public s_pendingWithdrawals; // depositor => amount

    mapping(uint256 => ClosedPositionLiquidityInfo)
        public s_closedPositionLiqudity; // mm_position_address => ClosedPositionLiquidityInfo

    uint32 s_vlpTokenIdCount;
    uint32 s_mmActionId; // used by the offchain indexer to distinguish between requests

    // -------------------------------------------------------

    // * Mm Registrations
    // mapping(uint32 => mapping(uint32 => bool)) public s_spotMarkets; // baseAsset => quoteAsset => marketExists
    mapping(uint32 => bool) s_perpMarkets; // syntheticAsset => marketExists

    // mapping(address => mapping(uint256 => bool)) public s_approvedSpotMMs; // user => tabAddress => isApproved
    mapping(address => mapping(uint256 => bool)) s_approvedPerpMMs; // user => positionAddress => isApproved

    // uint32 public s_pendingSpotMMCount;
    // mapping(uint256 => SpotMMRegistration) public s_spotRegistrations; // tabAddress => SpotMMRegistration
    uint32 s_pendingPerpMMCount;
    mapping(uint256 => PerpMMRegistration) public s_perpRegistrations; // posAddress => PerpMMRegistration

    mapping(uint256 => uint64) s_pendingCloseRequests; // positionAddress => txBatchId
}
