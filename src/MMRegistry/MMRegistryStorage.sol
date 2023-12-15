// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract MMRegistryStorage is OwnableUpgradeable {
    // * EVENTS --------------------------------------------
    // event newSpotMMRegistration(
    //     address mmOwner,
    //     uint32 baseAsset,
    //     uint32 quoteAsset,
    //     uint256 tabAddress,
    //     uint64 maxVlpSupply,
    //     uint32 vlpTokenId
    // );
    event newPerpMMRegistration(
        address indexed mmOwner,
        uint32 syntheticAsset,
        uint256 indexed positionAddress,
        uint64 maxVlpSupply,
        uint32 indexed vlpTokenId
    );

    event ClosePositionEvent(
        uint256 indexed positionAddress,
        address mmOwner,
        uint64 indexed initialValueSum,
        uint64 indexed vlpAmountSum
    );

    event AddLiquidity(
        address indexed depositor,
        uint256 indexed mmPositionAddress,
        uint64 indexed usdcAmount
    );
    event RemoveLiquidity(
        address indexed depositor,
        uint256 mmPositionAddress,
        uint64 indexed initialValue,
        uint64 indexed vlpAmount
    );

    // * STRUCTS --------------------------------------------

    // struct SpotMMRegistration {
    //     address mmOwner;
    //     uint32 baseAsset;
    //     uint32 quoteAsset;
    //     uint256 tabAddress;
    //     uint64 maxVlpSupply;
    //     uint32 vlpTokenId;
    //     bool isRegistered;
    // }

    struct PerpMMRegistration {
        address mmOwner;
        uint32 syntheticAsset;
        uint256 positionAddress;
        uint64 maxVlpSupply;
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

    // * Mm Add/Remove Liquidity
    mapping(address => mapping(uint256 => uint64)) s_pendingAddLiqudityRequests; // depositor => mm_position_address => scaled_amount

    Cancelation[] s_pendingCancellations;

    mapping(address => mapping(uint256 => LiquidityInfo))
        public s_activeLiqudity; // depositor => mm_position_address => LiquidityInfo

    mapping(uint256 => uint64) s_providedUsdcLiquidity; // mm_position_address => usdc_amount
    mapping(uint256 => uint64) s_aggregateVlpIssued; // mm_position_address => vlp issued

    mapping(bytes32 => bool) s_pendingRemoveLiqudityRequests; // H(depositor, value) => isPending

    mapping(address => uint256) public s_pendingWithdrawals; // depositor => amount

    mapping(uint256 => ClosedPositionLiquidityInfo)
        public s_closedPositionLiqudity; // mm_position_address => ClosedPositionLiquidityInfo

    uint32 s_vlpTokenIdCount;

    // -------------------------------------------------------

    // * Mm Registrations
    // mapping(uint32 => mapping(uint32 => bool)) public s_spotMarkets; // baseAsset => quoteAsset => marketExists
    mapping(uint32 => bool) public s_perpMarkets; // syntheticAsset => marketExists

    // mapping(address => mapping(uint256 => bool)) public s_approvedSpotMMs; // user => tabAddress => isApproved
    mapping(address => mapping(uint256 => bool)) public s_approvedPerpMMs; // user => positionAddress => isApproved

    // uint32 public s_pendingSpotMMCount;
    // mapping(uint256 => SpotMMRegistration) public s_spotRegistrations; // tabAddress => SpotMMRegistration
    uint32 public s_pendingPerpMMCount;
    mapping(uint256 => PerpMMRegistration) public s_perpRegistrations; // posAddress => PerpMMRegistration

    mapping(uint256 => bool) s_pendingCloseRequests; // positionAddress => isPending
}
