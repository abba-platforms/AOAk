# Changelog

This document records all notable changes, additions, and updates to the AOAk repository, following **semantic versioning (SemVer) principles**.  
It provides a clear and chronological history of releases, ensuring transparency, traceability, and accountability for developers, auditors, institutional stakeholders, and public users.

---

## [v0.1.0] – 2025-09-16

**Initial Release**

### Added
- **Smart Contract**
  - `contracts/AOAk.sol` – Primary AOAk ERC20 (upgradeable) smart contract
- **Documentation**
  - `docs/AOAk_Whitepaper.md` – Complete AOAk Whitepaper with tokenomics, technical specifications, and OpenZeppelin-style audit
  - `docs/ANGOLA_ANALYSIS.md` – In-depth analysis of Angola’s economy, currency, market potential, and necessity of AOAk
- **Repository Metadata**
  - `README.md` – Project overview, features, documentation links, disclaimers, and contact information
  - `LICENSE.md` – MIT License with disclaimer on AOAk not being licensed or endorsed by the Bank of Angola
  - `SECURITY.md` – Security considerations, best practices, and reporting guidelines
  - `CHANGELOG.md` – Record of repository history and updates
  - `CONTRIBUTION.md` – Contribution guidelines (not required for this stablecoin project)
  
### Features
- Enterprise-grade, upgradeable ERC20 smart contract
- Pegged 1:1 to Angola Kwanza (AOA) and 100% backed by USD reserves
- On-chain Proof-of-Reserves via Merkle roots
- Oracle integration with emergency override and governance roles
- Voucher-based minting (EIP-712)
- Batch redemption system with daily limits and status tracking
- OpenZeppelin-style audit applied with recommended and optional improvements
- Comprehensive legal disclaimer emphasizing AOAk is independent of Bank of Angola

### Notes
- This version establishes the complete repository structure for AOAk, including smart contracts, technical documentation, country analysis, licensing, and governance materials.
- All files are finalized for institutional review and public transparency.
