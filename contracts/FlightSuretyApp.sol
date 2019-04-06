pragma solidity 0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyApp {
  using SafeMath for uint256;

  FlightSuretyData flightSuretyData;
  
  address private contractOwner;
  bool public operational;

  mapping(address => address[]) public airlineVotes;

  uint256 public constant minAirplaneFund = 10 ether;
  uint256 private constant maxInsurancePayment = 1 ether;
  uint256 private constant multipartyConsensus = 4;

  // Flight status codees
  uint8 private constant STATUS_CODE_UNKNOWN = 0;
  uint8 private constant STATUS_CODE_ON_TIME = 10;
  uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
  uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
  uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
  uint8 private constant STATUS_CODE_LATE_OTHER = 50;

  event FlightRegistered(bytes32 flightKey);

  constructor(address dataContract) public {
    contractOwner = msg.sender;
    flightSuretyData = FlightSuretyData(dataContract);
  }

  modifier requireIsOperational() {
    require(flightSuretyData.isOperational(), "Contract is currently not operational");
    _;
  }

  modifier requireHaveEnoughFund() {
    require(msg.value >= minAirplaneFund, "Minimun funding amount is 10 ETH");
    _;
  }

  modifier requireIsPaidEnough(uint _price) {
    require(msg.value >= _price, "Sent value must cover the price");
    _;
  }

  modifier requireValueCheck(uint _price) {
    _;
    uint amountToReturn = msg.value - _price;
    msg.sender.transfer(amountToReturn);
  }

  modifier requireIsAirlineRegistered() {
    require(flightSuretyData.isAirlineRegistered(msg.sender),"Airline must be registered");
    _;
  }

  modifier requireIsAirlineFunded() {
    require(flightSuretyData.isAirlineFunded(msg.sender),"Airline must provide funding");
    _;
  }

  /* Utilities Functions  */

  function isOperational() public view returns(bool) {
    return flightSuretyData.isOperational();
  }

  function getFlightKey(string _flightCode, string _destination, uint _timestamp) internal pure returns(bytes32) {
    return keccak256(abi.encodePacked(_flightCode, _destination, _timestamp));
  }

  /* Smart Contract Functions */

  function registerAirline(address _airline) external
    requireIsOperational
    requireIsAirlineFunded {

      if (flightSuretyData.getRegisteredAirlinesCount() < multipartyConsensus) {
        flightSuretyData.registerAirline(_airline, msg.sender);
      } else {
        bool isDuplicate = false;
        for (uint i = 0; i < airlineVotes[_airline].length; i += 1) {
          if (airlineVotes[_airline][i] == msg.sender) {
              isDuplicate = true;
              break;
          }
        }

        require(!isDuplicate, "Voting already submitted for this airline");
        airlineVotes[_airline].push(msg.sender);

        uint registeredVotes = airlineVotes[_airline].length;
        uint multipartyConsensysDivider = flightSuretyData.getRegisteredAirlinesCount().div(2);

        if (multipartyConsensysDivider.sub(registeredVotes) == 0) {
          airlineVotes[_airline] = new address[](0);
          flightSuretyData.registerAirline(_airline, msg.sender);
        }
      }
  }

  function fundAirline() external payable
    requireIsAirlineRegistered
    requireHaveEnoughFund
    requireIsOperational {

      flightSuretyData.fundAirline.value(msg.value)(msg.sender);
  }

  function registerFlight(
    string _flightCode,
    uint _timestamp,
    uint _price,
    string _departure,
    string _destination
  ) external
    requireIsOperational
    requireIsAirlineFunded {

      flightSuretyData.registerFlight(
        _flightCode,        
        _timestamp,
        _price,
        _departure,
        _destination,
        msg.sender
      );
      bytes32 flightKey = keccak256(abi.encodePacked(_flightCode, _destination, _timestamp));
      emit FlightRegistered(flightKey);
  }

  function buyInsurance(
    string _flightCode,
    string _destination,
    uint _timestamp
  ) public payable
    requireIsOperational
    requireIsPaidEnough(maxInsurancePayment)
    requireValueCheck(maxInsurancePayment) {

      bytes32 flightKey = getFlightKey(_flightCode, _destination, _timestamp);

      flightSuretyData.buyInsurance(flightKey, msg.value, msg.sender);
  }

  function withdraw() external requireIsOperational {
    flightSuretyData.pay(msg.sender);
  }

  // Generate a request for oracles to fetch flight information
  function fetchFlightStatus(string _flightCode, string _destination, uint _timestamp) external {
    uint8 index = getRandomIndex(msg.sender);

    // Generate a unique key for storing the request
    bytes32 key = getFlightKey(_flightCode, _destination, _timestamp);
    oracleResponses[key] = ResponseInfo({
      requester: msg.sender,
      isOpen: true
    });

    emit OracleRequest(index, _flightCode, _destination, _timestamp);
  }

  ////////////////////// START ORACLE MANAGEMENT REGION
  // Incremented to add pseudo-randomness at various points
  uint8 private nonce = 0;

  // Fee to be paid when registering oracle
  uint256 public constant REGISTRATION_FEE = 1 ether;

  // Number of oracles that must respond for valid status
  uint8 private constant MIN_RESPONSES = 3;

  struct Oracle {
    bool isRegistered;
    uint8[3] indexes;
  }

  // Track all registered oracles
  mapping(address => Oracle) private oracles;

  // Model for responses from oracles
  struct ResponseInfo {
    address requester;                              
    bool isOpen;                                    
    mapping(uint8 => address[]) responses;
  }

  // Track all oracle responses
  // Key = hash(flight, destination, timestamp)
  mapping(bytes32 => ResponseInfo) public oracleResponses;

  event OracleRegistered(uint8[3] indexes);
  // Event fired each time an oracle submits a response
  event OracleReport(string flightCode, string destination, uint timestamp, uint8 status);
  // Event fired when number of identical responses reaches the threshold: response is accepted and is processed
  event FlightStatusInfo(string flightCode, string destination, uint timestamp, uint8 status);

  // Event fired when flight status request is submitted
  // Oracles track this and if they have a matching index
  // they fetch data and submit a response
  event OracleRequest(uint8 index, string flightCode, string destination, uint timestamp);


  // Register an oracle with the contract
  function registerOracle() external payable {
    // Require registration fee
    require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

    uint8[3] memory indexes = generateIndexes(msg.sender);

    oracles[msg.sender] = Oracle({
      isRegistered: true,
      indexes: indexes
    });
    emit OracleRegistered(indexes);
  }

  function getMyIndexes() external view returns(uint8[3]) {
    require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

    return oracles[msg.sender].indexes;
  }

  // Called by oracle when a response is available to an outstanding request
  // For the response to be accepted, there must be a pending request that is open
  // and matches one of the three Indexes randomly assigned to the oracle at the
  // time of registration (i.e. uninvited oracles are not welcome)
  function submitOracleResponse(uint8 _index, string _flightCode, string _destination, uint _timestamp, uint8 _status) external {
    
    require((oracles[msg.sender].indexes[0] == _index) || 
            (oracles[msg.sender].indexes[1] == _index) || 
            (oracles[msg.sender].indexes[2] == _index),
            "Index does not match oracle request"
    );

    bytes32 key = getFlightKey(_flightCode, _destination, _timestamp);
    require(oracleResponses[key].isOpen,"Flight or timestamp do not match oracle request.");

    oracleResponses[key].responses[_status].push(msg.sender);
    emit OracleReport(_flightCode, _destination, _timestamp, _status);

    /* Information isn't considered verified until at least
    MIN_RESPONSES oracles respond with the *** same *** information
    */
    if (oracleResponses[key].responses[_status].length == MIN_RESPONSES) {
      // close responseInfo
      oracleResponses[key].isOpen = false;
      emit FlightStatusInfo(_flightCode, _destination, _timestamp, _status);
      // Handle flight status as appropriate
      flightSuretyData.processFlightStatus(key, _status);
    }
  }

  // Returns array of three non-duplicating integers from 0-9
  function generateIndexes(address _account) internal returns(uint8[3]) {
    
    uint8[3] memory indexes;
    indexes[0] = getRandomIndex(_account);

    indexes[1] = indexes[0];
    while (indexes[1] == indexes[0]) {
      indexes[1] = getRandomIndex(_account);
    }

    indexes[2] = indexes[1];
    while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
      indexes[2] = getRandomIndex(_account);
    }

    return indexes;
  }

  // Returns array of three non-duplicating integers from 0-9
  function getRandomIndex(address _account) internal returns (uint8) {
    uint8 maxValue = 10;

    // Pseudo random number...the incrementing nonce adds variation
    uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), _account))) % maxValue);

    if (nonce > 250) {
      nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
    }

    return random;
  }
} 

// FlightSuretyData Interface contract
contract FlightSuretyData {
  function isOperational() public view returns(bool);
  function isAirlineFunded(address airline) external view returns (bool);
  function isAirlineRegistered(address airline) external view returns (bool);
  function getRegisteredAirlinesCount() external view returns (uint);
  function processFlightStatus(bytes32 flightKey, uint8 status) external;
  function buyInsurance(bytes32 flightKey, uint amount, address originAddress) external payable;
  function creditInsurees(bytes32 flightKey) external;
  function pay(address originAddress) external;
  function registerAirline(address airlineAddress, address originAddress) external;
  function fundAirline(address originAddress) external payable;
  function registerFlight(
    string _flightCode,
    uint timestamp,
    uint _price,
    string _departure,
    string _destination,
    address _airline
  ) external;
}
