pragma solidity 0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
  using SafeMath for uint;
  
  struct Airline {
    bool isRegistered;
    bool isFunded;
  }

  struct Flight {
    bool isRegistered;
    uint timestamp;
    uint8 status;
    address airline;
    string code;
    uint price;
    string departure;
    string destination;
    mapping(address => uint) insurances;
  }

  bool public operational = true;

  address private contractOwner;
  address[] internal passengers;
  bytes32[] public flightKeys;

  uint256 public registeredAirlinesCount;
  uint256 public registeredFlightsCount;

  mapping(address => bool) private authorizedContracts;
  mapping(address => Airline) public registeredAirlines;
  mapping(bytes32 => Flight) public flights;
  mapping(address => uint) public withdrawals;


  event AirlineRegistered(address origin, address airline);
  event AirlineFunded(address airline);
  event FlightRegistered(bytes32 flightKey);
  event FlightStatusUpdated(bytes32 flightKey, uint8 status);
  event PassengerCredited(address passenger, uint amount);
  event AccountWithdrawal(address recipient, uint amount);
  

  constructor(address _firstAirline) public {
    contractOwner = msg.sender;

    registeredAirlines[_firstAirline] = Airline({
      isRegistered: true,
      isFunded: false
    });

    registeredAirlinesCount = 1;
  }

  modifier requireIsOperational() {
    require(operational, "Contract is currently not operational");
    _;
  }

  modifier requireContractOwner() {
    require(msg.sender == contractOwner, "Caller is not contract owner");
    _;
  }

  modifier requireIsCallerAuthorized() {
    require(authorizedContracts[msg.sender] == true, "Caller is not authorized");
    _;
  }

  modifier requireIsAirlineNotRegistered(address _airline) {
    require(!registeredAirlines[_airline].isRegistered, "Airline is registered");
    _;
  }

  modifier requireIsFlightRegistered(bytes32 _flightKey) {
    require(flights[_flightKey].isRegistered, "This flight is not exist");
    _;
  }

  modifier requireIsFlightProcessed(bytes32 _flightKey) {
    require(flights[_flightKey].status == 0, "Flight already processed");
    _;
  }

  /* Utilities Functions  */

  function setOperatingStatus(bool mode) external requireContractOwner {
    require(mode != operational, "Contract already in the requested state");
    operational = mode;
  }

  function isOperational() external view returns(bool) {
    return operational;
  }

  function isAirlineRegistered(address _airline) external view returns(bool) {
    return registeredAirlines[_airline].isRegistered;
  }

  function authorizeCaller(address _contractAddress) external requireContractOwner{
    authorizedContracts[_contractAddress] = true;
  }

  function deauthorizeCaller(address _contractAddress) external requireContractOwner{
    delete authorizedContracts[_contractAddress];
}

  function isAirlineFunded(address _airline) external view returns(bool) {
    return registeredAirlines[_airline].isFunded;
  }

  function getFlightPrice(bytes32 _flightKey) external view returns(uint) {
    return flights[_flightKey].price;
  }

  function getInsuranceKey(address _passenger, address _airline, bytes32 _flightCode, uint _timestamp) 
    pure internal returns (bytes32) {

      return keccak256(abi.encodePacked(_passenger, _airline, _flightCode, _timestamp));
  }

  function getFlightKey(string _flightCode, string _destination, uint _timestamp) public pure returns(bytes32) {
    return keccak256(abi.encodePacked(_flightCode, _destination, _timestamp));
  }

  function isFlightRegistered(bytes32 _flightKey) external view returns(bool) {
    return flights[_flightKey].isRegistered;
  }

  function getRegisteredAirlinesCount() external view returns(uint) {
    return registeredAirlinesCount;
  }

    function getRegisteredFlightsCount() external view returns(uint) {
    return flightKeys.length;
  }

  function getPassengerPaidAmount(bytes32 _flightKey, address _passenger) external view returns(uint) {
    return flights[_flightKey].insurances[_passenger];
  }

  /* Smart Contract Functions */
  
  function registerAirline(address _airline, address _sender) external
    requireIsOperational
    requireIsCallerAuthorized 
    requireIsAirlineNotRegistered(_airline) {

      registeredAirlines[_airline] = Airline({
        isRegistered: true,
        isFunded: false
      });

      registeredAirlinesCount += 1;

      emit AirlineRegistered(_sender, _airline);
  }

  function registerFlight(
    string _flightCode,
    uint _timestamp,
    uint _price,
    string _departure,
    string _destination,
    address _airline
  ) external
    requireIsOperational
    requireIsCallerAuthorized {

      bytes32 flightKey = keccak256(abi.encodePacked(_flightCode, _destination, _timestamp));
      
      flights[flightKey] = Flight({
        isRegistered: true,
        timestamp: _timestamp,
        status: 0,
        airline: _airline,
        code: _flightCode,
        price: _price,
        departure: _departure,
        destination: _destination
      });
      
      flightKeys.push(flightKey);
      
      emit FlightRegistered(flightKey);
  }

  function buyInsurance(bytes32 _flightCode, uint _amount, address _passenger) external payable
    requireIsOperational
    requireIsCallerAuthorized
    requireIsFlightRegistered(_flightCode) {

      flights[_flightCode].insurances[_passenger] = _amount;
      withdrawals[flights[_flightCode].airline] = flights[_flightCode].price;

      passengers.push(_passenger);
  }

  function creditInsurees(bytes32 _flightCode) internal
    requireIsOperational
    requireIsFlightRegistered(_flightCode) {

      Flight storage flight = flights[_flightCode];
      
      for (uint i = 0; i < passengers.length; i++) {
        withdrawals[passengers[i]] = flight.insurances[passengers[i]];
        emit PassengerCredited(passengers[i], flight.insurances[passengers[i]]);
      }
  }

  function pay(address _originAddress) external
    requireIsOperational
    requireIsCallerAuthorized {
      
      require(withdrawals[_originAddress] > 0, "No amount available for withdrawal");

      uint amount = withdrawals[_originAddress];
      withdrawals[_originAddress] = 0;
      _originAddress.transfer(amount);
      emit AccountWithdrawal(_originAddress, amount);
  }

  function fundAirline(address _airline) external payable
    requireIsOperational
    requireIsCallerAuthorized {
      
      registeredAirlines[_airline].isFunded = true;
      emit AirlineFunded(_airline);
  }

  function processFlightStatus(bytes32 _flightKey, uint8 _status) external
    requireIsOperational
    requireIsCallerAuthorized
    requireIsFlightRegistered(_flightKey)
    requireIsFlightProcessed(_flightKey) {

      flights[_flightKey].status = _status;

      if (_status == 20) {
        creditInsurees(_flightKey);
      }

      emit FlightStatusUpdated(_flightKey, _status);
  }

  function fund() public payable{}

  function() external payable requireIsCallerAuthorized {
    require(msg.data.length == 0);
    fund();
  }
}
