// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IRiverMenGift.sol";
import "./polygon/ContextMixin.sol";
import "./polygon/NativeMetaTransaction.sol";

contract OwnableDelegateProxy {}

//libarary

    library MathSqrt {
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
        // else z = 0 (default value)
    }
}

contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}

contract RiverMenGift is
    IRiverMenGift,
    ERC721,
    ContextMixin,
    NativeMetaTransaction,
    ERC721Enumerable,
    AccessControl,
    ReentrancyGuard,
    Ownable
{
    using Strings for uint256;
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.UintSet;

    Counters.Counter private _tokenIds;

    string public baseURI;

    bytes32 public MINTER_ROLE;

    mapping(uint256 => uint24) public tokenResource;

    mapping(bytes32 => bool) public signatureUsed;

    address proxyRegistryAddress;

    address public hostSigner;

    // constructor{IDE, IDE, chainide.com, ur address, ur address, ur address, ur address, [3,2,1]}
    // --> name: "IDE", baseURI: chainide.com
    //seturl

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _initBaseURI,
        address admin,
        address minter,
        address signer,
        address _proxyRegistryAddress,
        uint256[] memory _testArr
        ) payable ERC721(_name, _symbol) {
        baseURI = _initBaseURI;
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        MINTER_ROLE = keccak256("MINTER_ROLE");
        _setupRole(MINTER_ROLE, minter);
        hostSigner = signer;
        proxyRegistryAddress = _proxyRegistryAddress;
        _initializeEIP712(_name);
        testarr = _testArr;
    }

    /* ================ UTIL FUNCTIONS ================ */
    modifier _onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "require admin permission");
        _;
    }

    modifier _onlyMinter() {
        require(hasRole(MINTER_ROLE, _msgSender()), "require minter permission");
        _;
    }

    modifier _notContract() {
        uint256 size;
        address addr = msg.sender;
        assembly {
            size := extcodesize(addr)
        }
        require(size == 0, "contract not allowed");
        require(msg.sender == tx.origin, "proxy contract not allowed");
        _;
    }

    function _msgSender() internal view override returns (address sender) {
        return ContextMixin.msgSender();
    }

    /* ================ VIEWS ================ */
    function tokenURI(uint256 tokenId) public view override(IRiverMenGift, ERC721) returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        return string(abi.encodePacked(_baseURI(), uint256(tokenResource[tokenId]).toString()));
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function isApprovedForAll(address owner, address operator) public view override returns (bool) {
        if (proxyRegistryAddress != address(0)) {
            // On Polygon
            if (block.chainid == 137 || block.chainid == 80001) {
                // if OpenSea's ERC721 Proxy Address is detected, auto-return true
                if (operator == address(proxyRegistryAddress)) {
                    return true;
                }
                // On Ethereum
            } else if (block.chainid == 1 || block.chainid == 4 || block.chainid == 5) {
                // Whitelist OpenSea proxy contract for easy trading.
                ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
                if (address(proxyRegistry.proxies(owner)) == operator) {
                    return true;
                }
            }
        }
        return super.isApprovedForAll(owner, operator);
    }

    /* ================ INTERNAL FUNCTIONS ================ */
    function _awardItem(address receiver) private returns (uint256) {
        _tokenIds.increment();
        uint256 newId = _tokenIds.current();
        _safeMint(receiver, newId);
        return newId;
    }

    function _mintByResource(address receiver, uint16 resourceId) private {
        uint256 newId = _awardItem(receiver);
        tokenResource[newId] = resourceId;
        emit Mint(receiver, newId);
    }

    function _baseURI() internal view override(ERC721) returns (string memory) {
        return baseURI;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function splitSignature(bytes memory sig)
        internal
        pure
        returns (
            uint8,
            bytes32,
            bytes32
        )
    {
        require(sig.length == 65, "invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        return (v, r, s);
    }

    function recoverSigner(bytes32 message, bytes memory sig) internal pure returns (address) {
        uint8 v;
        bytes32 r;
        bytes32 s;

        (v, r, s) = splitSignature(sig);

        return ecrecover(message, v, r, s);
    }

    function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    /* ================ ADMIN ACTIONS ================ */
    function setBaseURI(string memory newBaseURI) public override _onlyAdmin {
        baseURI = newBaseURI;
    }

    /* ================ MINTER ACTIONS ================ */
    function airdrop(address[] memory receivers, uint16[] memory resourceIds) public override nonReentrant _onlyMinter {
        require(receivers.length == resourceIds.length, "receivers length must equal resourceIds length");
        for (uint16 idx = 0; idx < resourceIds.length; ++idx) {
            _mintByResource(receivers[idx], resourceIds[idx]);
        }
    }

    /* ================ TRANSACTIONS ================ */
    function claim(
        address account,
        uint16[] memory resourceIds,
        uint256 nonce,
        bytes memory signature
    ) external override nonReentrant _notContract {
        bytes32 signatureHash = keccak256(abi.encodePacked(signature));
        require(!signatureUsed[signatureHash], "signature has been used");
        signatureUsed[signatureHash] = true;
        bytes32 messageHash = getEthSignedMessageHash(
            keccak256(abi.encodePacked(account, resourceIds, nonce, block.chainid))
        );
        require(recoverSigner(messageHash, signature) == hostSigner, "unable to verify signature");
        for (uint256 i = 0; i < resourceIds.length; i++) {
            _mintByResource(account, resourceIds[i]);
        }
    }

    // SPDX-License-Identifier: MIT
    // 这是一个单行注释。

    /*
    这是一个
    多行注释。
    */

    // constructor([3,2,1], value: 100) --> getBalance: 100, getTestArr: 3,2,1
    uint[] public testarr;

    function getBalance() external view returns(uint) {
        return address(this).balance;
    }

    function getTestArr() public view returns (uint256[] memory) {
        return testarr;
    }

    // bool 
    // setBool(true) --> getBool(true, false) : true, false, true

    bool public testbool;

    function setBool(bool _setbool) public {
        testbool = _setbool;
    }

    function getBool(bool _true,bool _false) public view returns (bool , bool, bool) {
        return (_true, _false, testbool || _true);
    }

    // int,uint 
    // setIntUint(-57896044618658097711785492504343953926634992332820282019728792003956564819968, 115792089237316195423570985008687907853269984665640564039457584007913129639935) 
    // --> getIntUint(); -123321. 321123,-57896044618658097711785492504343953926634992332820282019728792003956564819968, 115792089237316195423570985008687907853269984665640564039457584007913129639935 : 
    int public testint;
    uint public testuint;

    function setIntUint(int _int, uint _uint) public {
        testint = _int;
        testuint = _uint;
    }

    function getIntUint(int _int, uint _uint) public view returns (int, uint, int, uint) {
        return (_int, _uint, testint, testuint);
    }

    //address
    // setAddr(0xbA2b06f246aB4682f3A15B2A5Dc0fe709a8d097f) value: 100 --> getAddr(): 0xbA2b06f246aB4682f3A15B2A5Dc0fe709a8d097f ,getBalance(): 200
    address public Addr;

    function setAddr(address _testAddr) public payable {
        Addr = _testAddr;
    }

    function getAddr() public view returns (address) {
        return Addr;
    }

    //bytes1234..32
    //setBytes3(0xffffff) --> getBytes3(0x01, 0x0002): 0x01, 0x0002, 0xffffff
    bytes3 public tBytes3; //"0x000000";

    function setBytes3(bytes3 _bytes3) public {
        tBytes3 = _bytes3;
    }

    function getBytes3(bytes1 _bytes1, bytes2 _bytes2) public view returns (bytes1, bytes2, bytes3) {
        return (_bytes1, _bytes2, tBytes3);
    }

    uint public a = 2.5e30;

    //string, bytes
    // setEmoji(😍😘🥰) --> getEmoji(😁😂🤣, "0xabcd", "chainIDE 永远嘀神")：😍😘🥰，😁😂🤣，"0xabcd", "chainIDE 永远嘀神"
    //setString("我太难了~giao！") --> getString: "我太难了~giao！"
    string public emoji = unicode"Hello 😃";

    string public testString;

    bytes public foo = "foo\tf"; //ide:"0x666f6f5c66", remix: "0x666f6f0966"  asic: http://c.biancheng.net/c/ascii/  doc: https://learnblockchain.cn/docs/solidity/types.html#types

    string public foos = "foo\tf";

    bytes public fooss = hex"00112233" hex"44556677";

    string public foosss = hex"0011223344556677";

    function setEmoji(string memory _emoji) public {
        emoji = _emoji;
    }

    function getEmoji(string memory _emoji, bytes memory _foo, string memory _foos) public view returns (string memory, string memory, bytes memory, string memory) {
        return (emoji, _emoji, _foo, _foos);
    }

    function setString(string memory _string) public {
        testString = _string;
    }

    function getString() public view returns (string memory) {
        return testString;
    }

    //function-selector, address
    //f(): 0x26121ff0,  an address                  
    function f() public view returns (bytes4, address) {
    return (this.f.selector, this.f.address);
    }

    //array
    //setArr([1,2,3,4,5,6,7,8]) --> getArr(): [1,2,3,4,5,6,7,8]
    //setArr5([1,2,3,4,5] --> ) --> getArr5(): [1,2,3,4,5]
    //setArr55([[1,2,3,4,5],[1,2,3,4,5],[1,2,3,4,5],[1,2,3,4,5],[1,2,3,4,5]]) --> getArr55: [[1,2,3,4,5],[1,2,3,4,5],[1,2,3,4,5],[1,2,3,4,5],[1,2,3,4,5]]
    //setArr22([[[[1,2],[1,2]],[[1,2],[1,2]]], [[[1,2],[1,2]],[[1,2],[1,2]]]]) --> getArr22：
    //arrUnLimit() 
    uint[] public arr;

    function setArr(uint[] memory _arr) public {
        arr = _arr;
    }

    uint[5] public arr5;

    function setArr5(uint[5] memory _arr) public {
        arr5 = _arr;
    }

    uint[][5] public arr55;

    uint[2][2][2] public arr22;

    uint[][][] public arrUnLimit;

    function setUnArrL(uint[][][] memory _arr) public {
        arrUnLimit = _arr;
    }

    function getUnArrL() public view returns (uint256[][][] memory) {
        return arrUnLimit;
    }

    function setArr22(uint[2][2][2] memory _arr) public {
        arr22 = _arr;
    }

    function getArr22() public view returns (uint256[2][2][2] memory) {
        return arr22;
    }

    function setArr55(uint[][5] memory _arr) public {
        arr55 = _arr;
    }

    function getArr() public view returns (uint256[] memory) {
        return arr;
    }
    
    function getArr5() public view returns (uint256[5] memory) {
        return arr5;
    }

    function getArr55() public view returns (uint256[][5] memory) {
        return arr55;
    }

    //mapping
    // update(20220209) --> balances[your address]: 202202209
    mapping(address => uint) public balances;

    function update(uint newBalance) public {
        balances[msg.sender] = newBalance;
    }

    //struct
    //setTodo(["111", true, 0xbA2b06f246aB4682f3A15B2A5Dc0fe709a8d097f, "0x01", 1, -1, [1,2,3], [[1],[2]]]) --> getTodo: ["111", true, 0xbA2b06f246aB4682f3A15B2A5Dc0fe709a8d097f, "0x01", 1, -1, [1,2,3], [[1],[2]]]
    struct Todo {
        string text;
        bool completed;
        address player;
        bytes1 bt1;
        uint unsigned;
        int signed;
        uint[] arr;
        int[][2] uarr55;
    }

    Todo[] todo;

    function setTodo(Todo memory item) public {
        todo.push(item);
    }

    function getTodo() public view returns (Todo[] memory) {
        return todo;
    }

    //yul
    //asb(666) --> 666
    uint b = 1;
    function asb(uint x) public view returns (uint r) {
        assembly {
            // We ignore the storage slot offset, we know it is zero
            // in this special case.
            r := mul(x, sload(b.slot))
        }
    }

    // Event declaration
    // Up to 3 parameters can be indexed.
    // Indexed parameters helps you filter the logs by the indexed parameter
    event Log(address indexed sender, string message);

    function testEvent() external {
        emit Log(msg.sender, "Hello EVM!");
    }

    //Wei, ETher    
    uint public oneWei = 1 wei;
    // 1 wei is equal to 1
    bool public isOneWei = 1 wei == 1;

    uint public oneEther = 1 ether;
    // 1 ether is equal to 10^18 wei
    bool public isOneEther = 1 ether == 1e18;

    //if,else    
    function ifelse(uint x) public pure returns (uint) {
        if (x < 10) {
            return 0;
        } else if (x < 20) {
            return 1;
        } else {
            return 2;
        }
    }

    function ternary(uint _x) public pure returns (uint) {
        // if (_x < 10) {
        //     return 1;
        // }
        // return 2;

        // shorthand way to write if / else statement
        return _x < 10 ? 1 : 2;
    }

    // Enum representing shipping status
    enum Status {
        Pending,
        Shipped,
        Accepted,
        Rejected,
        Canceled
    }

    // Default value is the first element listed in
    // definition of the type, in this case "Pending"
    Status public status;

    // Returns uint
    // Pending  - 0
    // Shipped  - 1
    // Accepted - 2
    // Rejected - 3
    // Canceled - 4
    function getEnum() public view returns (Status) {
        return status;
    }

    // Update status by passing uint into input
    function setEnum(Status _status) public {
        status = _status;
    }

    //revert
    function testRevert(uint _i) public pure {
        // Revert is useful when the condition to check is complex.
        // This code does the exact same thing as the example above
        if (_i <= 10) {
            revert("Input must be greater than 10");
        }
    }

    uint public MAX_UINT = 2**256 - 1;

    function testSquareRoot(uint x) public pure returns (uint) {
        return MathSqrt.sqrt(x);
    }

    //payable and fallback
     /*
    Which function is called, fallback() or receive()?

           send Ether
               |
         msg.data is empty?
              / \
            yes  no
            /     \
    receive() exists?  fallback()
         /   \
        yes   no
        /      \
    receive()   fallback()
    */

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}

}
