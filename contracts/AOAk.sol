// SPDX-License-Identifier: BUSL-1.1 pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol"; import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol"; import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol"; import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol"; import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol"; import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol"; import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title Angola Digital Kwanza (AOAk) Stablecoin Contract (Enterprise-Grade, Upgradeable, Enhanced) /// @notice ERC20 stablecoin pegged 1:1 to Angolan Kwanza /// @dev Upgradeable via UUPS proxy; ERC-3643 migration-ready contract AOAk is ERC20Upgradeable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable { using ECDSA for bytes32; using EnumerableSet for EnumerableSet.AddressSet;

// -------------------
// Roles
// -------------------
bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");
bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE"); // New governance role

// -------------------
// Oracle Integration
// -------------------
uint256 public aoaPerUsdScaled;
uint256 public lastOracleUpdate;
uint256 public oracleMinInterval = 60; // seconds
uint256 public oracleMaxDelta = 5e18;  // 5%
EnumerableSet.AddressSet private oracleSources;
address public emergencyAdmin;
uint256 public emergencyOverrideTimelock; // seconds
uint256 public emergencyOverrideRequestedAt;
uint256 public pendingEmergencyRate;
uint256 public constant MIN_EMERGENCY_TIMELOCK = 3600; // 1 hour minimum

event AoAPerUsdUpdated(uint256 oldRate, uint256 newRate, uint256 timestamp);
event OracleSourceAdded(address source);
event OracleSourceRemoved(address source);
event EmergencyOverrideScheduled(uint256 newRate, uint256 timestamp);
event EmergencyOverrideExecuted(uint256 oldRate, uint256 newRate, uint256 timestamp, address admin);
event OracleMaxDeltaUpdated(uint256 oldDelta, uint256 newDelta);

function setOracleMaxDelta(uint256 newDelta) external onlyRole(GOVERNOR_ROLE) {
    uint256 old = oracleMaxDelta;
    oracleMaxDelta = newDelta;
    emit OracleMaxDeltaUpdated(old, newDelta);
}

function addOracleSource(address source) external onlyRole(ORACLE_ROLE) {
    require(oracleSources.add(source), "Already source");
    emit OracleSourceAdded(source);
}

function removeOracleSource(address source) external onlyRole(ORACLE_ROLE) {
    require(oracleSources.remove(source), "Not source");
    emit OracleSourceRemoved(source);
}

/// @notice Submit multiple oracle rates and set median as current rate
function submitOracleRates(uint256[] calldata rates) external {
    require(oracleSources.contains(msg.sender), "Not approved oracle");
    require(block.timestamp >= lastOracleUpdate + oracleMinInterval, "Too soon");
    require(rates.length > 0, "No rates submitted");
    require(rates.length <= 50, "Too many rates"); // gas safety

    uint256[] memory sorted = rates;
    for (uint i = 0; i < sorted.length - 1; i++) {
        for (uint j = i + 1; j < sorted.length; j++) {
            if (sorted[j] < sorted[i]) {
                (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
            }
        }
    }
    uint256 median = sorted[sorted.length / 2];

    if (aoaPerUsdScaled != 0) {
        uint256 delta = median > aoaPerUsdScaled ? median - aoaPerUsdScaled : aoaPerUsdScaled - median;
        require(delta * 1e18 / aoaPerUsdScaled <= oracleMaxDelta, "Delta too high");
    }

    uint256 oldRate = aoaPerUsdScaled;
    aoaPerUsdScaled = median;
    lastOracleUpdate = block.timestamp;
    emit AoAPerUsdUpdated(oldRate, median, block.timestamp);
}

function scheduleEmergencyOverride(uint256 scaledRate, uint256 timelockSeconds) external {
    require(msg.sender == emergencyAdmin, "Not emergency admin");
    require(timelockSeconds >= MIN_EMERGENCY_TIMELOCK, "Timelock too short");
    pendingEmergencyRate = scaledRate;
    emergencyOverrideRequestedAt = block.timestamp;
    emergencyOverrideTimelock = timelockSeconds;
    emit EmergencyOverrideScheduled(scaledRate, block.timestamp);
}

function executeEmergencyOverride() external {
    require(msg.sender == emergencyAdmin, "Not emergency admin");
    require(emergencyOverrideRequestedAt > 0, "No pending override");
    require(block.timestamp >= emergencyOverrideRequestedAt + emergencyOverrideTimelock, "Timelock not expired");

    uint256 oldRate = aoaPerUsdScaled;
    aoaPerUsdScaled = pendingEmergencyRate;
    lastOracleUpdate = block.timestamp;
    pendingEmergencyRate = 0;
    emergencyOverrideRequestedAt = 0;
    emergencyOverrideTimelock = 0;

    emit EmergencyOverrideExecuted(oldRate, aoaPerUsdScaled, block.timestamp, msg.sender);
}

// -------------------
// Proof-of-Reserves (Configurable buffer)
// -------------------
struct ReserveAnchor { bytes32 merkleRoot; string ipfsCid; uint256 timestamp; uint256 totalSupply; uint256 blockNumber; }
ReserveAnchor[] private reserveAnchors;
uint256 private reserveIndex;
uint256 public maxReserveAnchors = 100;

event ReserveAnchored(bytes32 merkleRoot, string ipfsCid, uint256 timestamp, uint256 totalSupply, uint256 blockNumber);

function setMaxReserveAnchors(uint256 newMax) external onlyRole(GOVERNOR_ROLE) {
    require(newMax >= reserveAnchors.length, "Too small");
    maxReserveAnchors = newMax;
}

function anchorReserveBatch(ReserveAnchor[] calldata anchors) external onlyRole(AUDITOR_ROLE) {
    require(anchors.length <= 10, "Too many reserve anchors");
    for (uint i = 0; i < anchors.length; i++) {
        if(reserveAnchors.length < maxReserveAnchors){
            reserveAnchors.push(anchors[i]);
        } else {
            reserveAnchors[reserveIndex] = anchors[i];
            reserveIndex = (reserveIndex + 1) % maxReserveAnchors;
        }
        emit ReserveAnchored(anchors[i].merkleRoot, anchors[i].ipfsCid, anchors[i].timestamp, anchors[i].totalSupply, anchors[i].blockNumber);
    }
}

// -------------------
// Helper view functions (recommended)
// -------------------
function getLatestReserveAnchor() external view returns (ReserveAnchor memory) {
    if(reserveAnchors.length == 0) return ReserveAnchor(0, "", 0, 0, 0);
    uint256 idx = reserveIndex == 0 ? reserveAnchors.length - 1 : reserveIndex - 1;
    return reserveAnchors[idx];
}

function getLatestOracleRate() external view returns (uint256) {
    return aoaPerUsdScaled;
}

// -------------------
// Voucher Minting (EIP-712)
// -------------------
bytes32 public constant VOUCHER_TYPEHASH = keccak256("MintVoucher(address to,uint256 amountAOA,uint256 nonce,uint256 expiry)");
mapping(bytes32 => bool) public usedVouchers;

struct MintVoucher { address to; uint256 amountAOA; uint256 nonce; uint256 expiry; }
event Minted(address indexed to, uint256 amountAOA, uint256 usdAmount, bytes32 voucherHash);

function mint(address to, uint256 amountAOA) external onlyRole(MINTER_ROLE) whenNotPaused {
    _mint(to, amountAOA);
    emit Minted(to, amountAOA, 0, 0);
}

function mintWithVoucher(MintVoucher calldata voucher, bytes calldata signature) external whenNotPaused nonReentrant {
    require(block.timestamp <= voucher.expiry, "Voucher expired");
    bytes32 hashStruct = keccak256(abi.encode(VOUCHER_TYPEHASH, voucher.to, voucher.amountAOA, voucher.nonce, voucher.expiry));
    bytes32 digest = ECDSA.toEthSignedMessageHash(hashStruct);
    address signer = digest.recover(signature);
    require(hasRole(MINTER_ROLE, signer), "Invalid signer");
    require(!usedVouchers[digest], "Voucher used");

    usedVouchers[digest] = true;
    _mint(voucher.to, voucher.amountAOA);
    emit Minted(voucher.to, voucher.amountAOA, 0, digest);
}

// -------------------
// Redemption (Batch + Monitoring + KYC-ready hook)
// -------------------
enum RedemptionStatus { Pending, Processed, Failed }
struct Redemption { address user; uint256 amountAOA; bytes32 bankHash; RedemptionStatus status; uint256 timestamp; }
uint256 public redemptionCount;
mapping(uint256 => Redemption) public redemptions;
mapping(address => mapping(uint256 => uint256)) public dailyRedemption;
uint256 public dailyRedemptionLimit = 1e24;

event DailyRedemptionAggregate(address indexed user, uint256 totalRedeemed, uint256 day);
event RedemptionRequested(uint256 indexed redemptionId, address indexed user, uint256 amountAOA, bytes32 bankHash, uint256 timestamp);
event RedemptionProcessed(uint256 indexed redemptionId, address indexed user, uint256 usdAmount, bool success);
event RedemptionFailed(uint256 indexed redemptionId, address indexed user, uint256 amountAOA, string reason);

// Optional KYC hook placeholder
function _checkKYC(address user) internal view returns (bool) {
    // Integrate with off-chain KYC system if needed
    return true;
}

function requestRedemptions(uint256[] calldata amounts, bytes32[] calldata bankHashes) external whenNotPaused nonReentrant {
    require(amounts.length == bankHashes.length, "Mismatched arrays");
    require(amounts.length <= 20, "Too many redemptions at once");
    uint256 today = block.timestamp / 1 days;
    uint256 totalToday = dailyRedemption[msg.sender][today];

    Redemption storage r;
    for (uint i = 0; i < amounts.length; i++) {
        require(_checkKYC(msg.sender), "KYC check failed");
        uint256 amountAOA = amounts[i];
        bytes32 bankHash = bankHashes[i];
        if(totalToday + amountAOA > dailyRedemptionLimit){
            emit RedemptionFailed(redemptionCount, msg.sender, amountAOA, "Daily limit exceeded");
            continue;
        }
        totalToday += amountAOA;
        dailyRedemption[msg.sender][today] = totalToday;

        uint256 redemptionId = redemptionCount;
        r = redemptions[redemptionId];
        r.user = msg.sender;
        r.amountAOA = amountAOA;
        r.bankHash = bankHash;
        r.status = RedemptionStatus.Pending;
        r.timestamp = block.timestamp;

        _burn(msg.sender, amountAOA);
        emit RedemptionRequested(redemptionCount, msg.sender, amountAOA, bankHash, block.timestamp);
        redemptionCount++;
    }

    emit DailyRedemptionAggregate(msg.sender, totalToday, today);
}

function finalizeRedemption(uint256 redemptionId, uint256 usdAmount, bool success) external onlyRole(MINTER_ROLE) {
    Redemption storage r = redemptions[redemptionId];

