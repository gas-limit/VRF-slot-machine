// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "https://github.com/transmissions11/solmate/blob/main/src/auth/Owned.sol";

/*
A truly random and fair slot machine 🎰
Made by Josh 
*/


// setup
// Owner will fund contract with ETH
// Owner will set up Chainlink VRF subscription and fund with LINK
// In constructor, owner will specify how much in dollars the game will cost to play


// how to play
// 1. player will use startGame() to play
// 2. 3 verifiably random numbers are produced and determine each slot's position
// 3. if the player wins, then winnings will be sent directly to their wallet




contract SlotMachineRouter is VRFConsumerBaseV2, Owned  {


  //entry fee to play
  uint entryFee;
  //denominated in USD
  mapping(address => uint) public userBalance;
  address constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
  address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
  address constant USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;

  //deposit ERC20
  // 1 = DAI, 2 = USDC, 3 = USDT
  string priceFeedAddress;

  AggregatorV3Interface internal priceFeed;

  //coordinator object
  VRFCoordinatorV2Interface public COORDINATOR;
  // Your subscription ID.
  uint64 public s_subscriptionId;

  // ID of public key against which randomness is generated
  bytes32 public keyHash;

  uint32 callbackGasLimit = 10e5;

  uint16 requestConfirmations = 3;

  //mapping to reference the address in fulfillrandomwords()
  mapping(uint256 => address) public s_requestIdToAddress;

  mapping (address => uint256[]) public  userToRequestArray; 

  mapping (address => uint256) addressToBalance;

  mapping (address => uint256) addressToWinnings;

  mapping(uint256 => gameData) requestIdToGameData;

  struct gameData {
      uint256 slot1;
      uint256 slot2;
      uint256 slot3;
  }

  //events 🎪
  event GameStarted(address indexed _from, uint _value);
  event Jackpot1(address indexed _from);
  event Two1s(address indexed _from);
  event Jackpot2(address indexed _from);
  event Two2s(address indexed _from);
  event Jackpot3(address indexed _from);
  event Two3s(address indexed _from);
  event Jackpot4(address indexed _from);
  event Two4s(address indexed _from);
  event Jackpot5(address indexed _from);
  event Two5s(address indexed _from);
  event Lose(address indexed _from);


  constructor(uint _entryFee, string memory _priceFeedAddress, uint64 subscriptionId, address _vrfCoordinator, bytes32 _keyHash) Owned(msg.sender) VRFConsumerBaseV2(_vrfCoordinator) {
    entryFee = _entryFee;
    priceFeedAddress = _priceFeedAddress;
    COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
    s_subscriptionId = subscriptionId;
    keyHash = _keyHash;
    owner = payable(msg.sender);
  }

    //deposit MATIC
   function depositETH() public payable {
       (,int price,,,) = priceFeed.latestRoundData();
        uint chainlinkPrice = uint(price);
        uint chainlinkPriceTo4Digits = chainlinkPrice / 10 ** 4;
        uint amountWei = msg.value * chainlinkPriceTo4Digits;
        amountWei = amountWei / 10 ** 4;
        uint amountETH = amountWei / 1 ether;
        userBalance[msg.sender] += amountETH;
  }

  function depositERC20(uint amount, address token) public {
    require(token == DAI || token == USDC || token == USDT);
    IERC20(token).transferFrom(msg.sender, address(this), amount);
    userBalance[msg.sender] += amount;
   }

  function ownerWithdraw() public {
    address payable ownerPayable = payable(owner);
    ownerPayable.transfer(address(this).balance);
    IERC20(DAI).transfer(owner,  IERC20(DAI).balanceOf(address(this)));
    IERC20(USDC).transfer(owner, IERC20(USDC).balanceOf(address(this)));
    IERC20(USDT).transfer(owner, IERC20(USDT).balanceOf(address(this)));      
  }

  function userWithdraw() public {

  }

/* ☆♬○♩●♪✧♩☆♬○♩●♪✧♩☆♬○♩●♪✧♩☆♬○♩●♪✧♩　Play Game (*triple H Theme*)　♩✧♪●♩○♬☆♩✧♪●♩○♬☆♩✧♪●♩○♬☆♩✧♪●♩○♬☆*/
    // play game function
    function playGame() public {

      //require entry fee is paid
      require(userBalance[msg.sender] >= entryFee);
      userBalance[msg.sender] - entryFee;

      //request random numbers
      requestRandomWords();
      //fullFillRandomWords() is called by Chainlink which completes our game
        
    }
/* ☆♬○♩●♪✧♩☆♬○♩●♪✧♩☆♬○♩●♪✧♩☆♬○♩●♪✧♩　End of game　♩✧♪●♩○♬☆♩✧♪●♩○♬☆♩✧♪●♩○♬☆♩✧♪●♩○♬☆*/



// =!=!=!=!=!=!=!=!=!=! CHAINLINK PricefeedV3 St00f =!=!=!=!=!=!=!=!=!=!=!=!=!=!=!

  //this function calculates the cost in ether to play the game
  //the entry fee is denominated in dollars
  function getEntryFeeMATIC() public view returns (uint) {
        //get ETH latest price
        (,int price,,,) = priceFeed.latestRoundData();
        //multiply price to prepare for division
        uint ETHprice = uint(price*10**18);
        //multiply dollar cost to prepare for division
        uint minDollars = entryFee * 10 ** 18;
        //calculate cost in ether
        uint fee = ((minDollars*10**18)/ETHprice) * 10 ** 8;

        return fee;
  }


//=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!=!

  
/* ｡･:*:･ﾟ★,｡･:*:･ﾟ☆　CHAINLINK VRF STUFF  ｡･:*:･ﾟ★,｡･:*:･ﾟ☆｡･:*:･ﾟ★,｡･:*:･ﾟ☆　　 ｡･:*:･ﾟ★,｡･:*:･ﾟ☆*/

    // Assumes the subscription is funded sufficiently.
  function requestRandomWords() internal {
    // Will revert if subscription is not set and funded.
    uint256 requestId = COORDINATOR.requestRandomWords(
      keyHash,
      s_subscriptionId,
      requestConfirmations,
      callbackGasLimit,
      3
    );
    //mapping to pass address over to fulfillRandomWords
    s_requestIdToAddress[requestId] = msg.sender;
  }
/*♥*♡∞:｡.｡♥*♡∞:｡.｡♥*♡∞:｡.｡　FULFILL RANDOM WORDS　｡.｡:∞♡*♥｡.｡:∞♡*♥｡.｡:∞♡*♥       < ---------- */

  function fulfillRandomWords(
    uint256 requestId, 
    uint256[] memory randomWords
  ) internal override {

      require(msg.sender == address(COORDINATOR), "not vrf");

    //Get random words between 1 and 5
    uint256 slot1 = (randomWords[0] % 5) + 1;
    uint256 slot2 = (randomWords[1] % 5) + 1;
    uint256 slot3 = (randomWords[2] % 5) + 1;

    //sets the frontend mappings
    requestIdToGameData[requestId] = gameData(slot1, slot2, slot3);

    address player = s_requestIdToAddress[requestId];
    

   //The Game
   if (slot1 == 1 && slot2 == 1 && slot3 == 1) {
    //Jackpot #1
    addressToWinnings[player] += 1 ether;

  }
  else if((slot1 == 1 && slot2 == 1) || (slot2 == 1 && slot3 == 2))
  {
    //if two 1's are next to eachother
    addressToWinnings[player] += 0.1 ether;
  }
  else if(slot1 == 2 && slot2 == 2 && slot3 == 2) {
    //Jackpot #2
    addressToWinnings[player] += 2 ether;
  }
  else if((slot1 == 2 && slot2 == 2) || (slot2 == 2 && slot3 == 2) ){
    //if two 2's are next to eachother
    addressToWinnings[player] += 0.2 ether;
  }
  else if(slot1 == 3 && slot2 == 3 && slot3 == 3) {
    //Jackpot #3
    addressToWinnings[player] += 3 ether;
  }
  else if((slot1 == 3 && slot2 == 3) || (slot2 == 3 && slot3 == 3) ){
    //if two 3's are next to eachother
    addressToWinnings[player] += 0.3 ether;
  }
  else if(slot1 == 4 && slot2 == 4 && slot3 == 4) {
    //Jackpot #4
    addressToWinnings[player] += 4 ether;
  }
  else if((slot1 == 4 && slot2 == 4) || (slot2 == 4 && slot3 == 4) ){
    //if two 4's are next to eachother
    addressToWinnings[player] += 0.4 ether;
  }
  else if(slot1 == 5 && slot2 == 5 && slot3 == 5) {
    //Jackpot #5
    addressToWinnings[player] += 5 ether;
  }
  else if((slot1 == 5 && slot2 == 5) || (slot2 == 5 && slot3 == 5) ){
    //if two 5's are next to eachother
    addressToWinnings[player] += 0.5 ether;
  }
  else{
       
  }

  }

/*♥*♡∞:｡.｡♥*♡∞:｡.｡♥*♡∞:｡.｡　END OF FULFILL RANDOM WORDS　｡.｡:∞♡*♥｡.｡:∞♡*♥｡.｡:∞♡*♥ */

/* ｡･:*:･ﾟ★,｡･:*:･ﾟ☆　END OF CHAINLINK VRF STUFF  ｡･:*:･ﾟ★,｡･:*:･ﾟ☆｡･:*:･ﾟ★,｡･:*:･ﾟ☆　　 ｡･:*:･ﾟ★,｡･:*:･ﾟ☆*/

    /* ============Some data to help the frontend =====================*/

    function getLastGameData(address _address) public view returns (gameData memory) {
      uint256 length = userToRequestArray[_address].length;
      uint256 requestId_ = userToRequestArray[_address][length - 1];
      gameData memory gameData_ = requestIdToGameData[requestId_];
      return gameData_;
    }

    function getBalance(address _address) public view returns (uint256) {
      return addressToWinnings[_address];
    }

    //==================================================================

    
    // Function to receive Ether. msg.data must be empty
   receive() external payable {}
    // Fallback function is called when msg.data is not empty
   fallback() external payable {}

}


interface IERC20 {
    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint amount);
    event Approval(address indexed owner, address indexed spender, uint amount);
}
