import FlightSuretyApp from "../../build/contracts/FlightSuretyApp.json";
import Config from "./config.json";
import Web3 from "web3";

export default class Contract {
  constructor(network, callback) {
    let config = Config[network];

    this.web3 = new Web3(new Web3.providers.HttpProvider(config.url));

    this.flightSuretyApp = new this.web3.eth.Contract(
      FlightSuretyApp.abi,
      config.appAddress
    );

    this.initialize(callback);

    this.owner = null;
    this.firstAirline = null;
    this.airlines = [];
    this.flights = [];
    this.passengers = [];
  }

  initialize(callback) {
    this.web3.eth.getAccounts((error, accts) => {
      this.owner = accts[0];
      this.firstAirline = accts[1];

      let counter = 1;

      while (this.airlines.length < 5) {
        this.airlines.push(accts[counter++]);
      }

      while (this.passengers.length < 5) {
        this.passengers.push(accts[counter++]);
      }

      callback();
    });
  }

  isOperational(callback) {
    let self = this;
    self.flightSuretyApp.methods
      .isOperational()
      .call({ from: self.owner }, callback);
  }

  fetchFlightStatus(flightCode, destination, callback) {
    let self = this;
    const timestamp = Math.floor(Date.now() / 1000);

    self.flightSuretyApp.methods
      .fetchFlightStatus(flightCode, destination, timestamp)
      .send({ from: self.firstAirline }, (error, result) => {
        callback(error, result);
      });
  }

  registerAirline(airline, callback) {
    let self = this;
    self.flightSuretyApp.methods
      .registerAirline(airline)
      .send({ from: self.firstAirline }, callback);
  }

  fundAirline(amount, callback) {
    let self = this;
    const price = this.web3.utils.toWei(amount.toString(), "ether");

    self.flightSuretyApp.methods
      .fundAirline()
      .send({ from: self.firstAirline, value: price }, callback);
  }

  registerFlight(flightCode, price, departure, destination, callback) {
    let self = this;
    const timestamp = Math.floor(Date.now() / 1000);
    const value = this.web3.utils.toWei(price.toString(), "ether");

    self.flightSuretyApp.methods.registerFlight(
      flightCode,
      timestamp,
      value,
      departure,
      destination,
      { from: self.firstAirline },
      callback
    );
  }

  buyInsurance(flightCode, destination, price, callback) {
    let self = this;
    const timestamp = Math.floor(Date.now() / 1000);
    const value = this.web3.utils.toWei(price.toString(), "ether");

    self.flightSuretyApp.methods.buyInsurance(
      flightCode,
      destination,
      timestamp,
      {
        from: self.firstAirline,
        value: value
      },
      callback
    );
  }

  withdraw(callback) {
    self.flightSuretyApp.methods
      .withdraw()
      .send({ from: self.firstAirline }, callback);
  }
}
