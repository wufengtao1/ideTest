// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;
pragma abicoder v2;

interface IRiverMenGift {
    /* ================ EVENTS ================ */
    event Mint(address indexed payer, uint256 indexed tokenId);

    /* ================ VIEWS ================ */
    function tokenURI(uint256 tokenId) external view returns (string memory);

    /* ================ ADMIN ACTIONS ================ */
    function setBaseURI(string memory newBaseURI) external;

    function airdrop(address[] memory receivers, uint16[] memory resourceIds) external;

    /* ================ TRANSACTIONS ================ */
    function claim(
        address account,
        uint16[] memory resourceIds,
        uint256 nonce,
        bytes memory signature
    ) external;
}
