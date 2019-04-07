const Test = require("../config/testConfig.js");

contract("Flight Surety Tests", async accounts => {
  var config;

  before("setup contract", async () => {
    config = await Test.Config(accounts);
    await config.flightSuretyData.authorizeCaller(
      config.flightSuretyApp.address
    );
  });

  describe("Contracts Operational Status", () => {
    it("Contract has correct initial isOperational() value", async () => {
      // Get operating status
      let status = await config.flightSuretyData.operational.call();

      assert.equal(status, true, "Incorrect initial operating status value");
    });

    it("Contract can block access to setOperatingStatus() for non-Contract Owner account", async function() {
      // Ensure that access is denied for non-Contract Owner account
      let accessDenied = false;

      try {
        await config.flightSuretyData.setOperatingStatus(false, {
          from: config.testAddresses[2]
        });
      } catch (e) {
        accessDenied = true;
      }

      assert.equal(
        accessDenied,
        true,
        "Access not restricted to Contract Owner"
      );
    });

    it("Contract can block access to functions using requireIsOperational when operating status is false", async () => {
      await config.flightSuretyData.setOperatingStatus(false);

      let reverted = false;

      try {
        await config.flightSurety.setTestingMode(true);
      } catch (e) {
        reverted = true;
      }

      assert.equal(
        reverted,
        true,
        "Access not blocked by requireIsOperational"
      );

      // Set it back for other tests to work
      await config.flightSuretyData.setOperatingStatus(true);
    });
  });

  describe("airlines registration", () => {
    const minimumFund = web3.utils.toWei("10", "ether");

    const airline2 = accounts[2];
    const airline3 = accounts[3];
    const airline4 = accounts[4];
    const airline5 = accounts[5];

    it("Register first airline at deployment", async () => {
      const isAirlineRegistered = await config.flightSuretyData.isAirlineRegistered.call(
        config.firstAirline
      );

      assert.equal(
        isAirlineRegistered,
        true,
        "First airline not registered on deployment"
      );

      assert.equal(
        await config.flightSuretyData.getRegisteredAirlinesCount.call(),
        1
      );
    });

    it("Airline cannot register another one before providing funding", async () => {
      try {
        await config.flightSuretyApp.registerAirline(airline2, {
          from: config.firstAirline
        });
      } catch (error) {}

      const isAirlineRegistered = await config.flightSuretyData.isAirlineRegistered(
        airline2
      );

      assert.equal(
        isAirlineRegistered,
        false,
        "Airline should not be able to register another airline without providing fund"
      );
    });

    it("Airline can provide funding", async () => {
      try {
        await config.flightSuretyApp.fundAirline({
          from: config.firstAirline,
          value: minimumFund
        });
      } catch (error) {
        console.log(error.toString());
      }

      const isAirlineFunded = await config.flightSuretyData.isAirlineFunded.call(
        config.firstAirline
      );

      assert.equal(isAirlineFunded, true, "Airline hasn't provided funding");
    });

    it("Only first airline can register an airline when less than 4 airlines are registered", async () => {
      try {
        await config.flightSuretyApp.registerAirline(airline2, {
          from: config.firstAirline
        });

        await config.flightSuretyApp.registerAirline(airline3, {
          from: config.firstAirline
        });

        await config.flightSuretyApp.registerAirline(airline4, {
          from: config.firstAirline
        });
      } catch (error) {
        console.log(error.toString());
      }

      const isAirline2Registered = await config.flightSuretyData.isAirlineRegistered.call(
        airline2
      );

      const isAirline3Registered = await config.flightSuretyData.isAirlineRegistered.call(
        airline3
      );

      const isAirline4Registered = await config.flightSuretyData.isAirlineRegistered.call(
        airline4
      );

      assert.equal(
        isAirline2Registered,
        true,
        "Second airline should able to be registered"
      );
      assert.equal(
        isAirline3Registered,
        true,
        "Third airline should able to be registered"
      );
      assert.equal(
        isAirline4Registered,
        true,
        "Forth airline should able to be registered"
      );
      assert.equal(
        await config.flightSuretyData.getRegisteredAirlinesCount.call(),
        4
      );
    });

    it("5th airline cannot be registered without multiparty consensus", async () => {
      await config.flightSuretyApp.registerAirline(airline5, {
        from: config.firstAirline
      });

      let isAirline5Registered = await config.flightSuretyData.isAirlineRegistered.call(
        airline5
      );

      assert.equal(
        isAirline5Registered,
        false,
        "5th airline should not registered without minimum votes"
      );

      // // Same airline can not be registered twice
      let reverted = true;
      try {
        await config.flightSuretyApp.registerAirline(airline5, {
          from: config.firstAirline
        });
      } catch (error) {
        reverted = false;
      }

      assert.equal(reverted, false, "Airline should not be registered twice");

      try {
        await config.flightSuretyApp.fundAirline({
          from: airline2,
          value: minimumFund
        });
      } catch (error) {
        console.log(error.toString());
      }

      try {
        await config.flightSuretyApp.registerAirline(airline5, {
          from: airline2
        });
      } catch (error) {
        console.log(error.toString());
      }

      isAirline5Registered = await config.flightSuretyData.isAirlineRegistered.call(
        airline5
      );

      assert.equal(isAirline5Registered, true, "5th airline not registered");
    });
  });

  describe("flight registration", () => {
    const departure = "RUH";
    const destination = "HBE";
    const flightCode = "MS653";
    const timestamp = (Date.now() / 1000) | 0;

    const price = web3.utils.toWei("0.3", "ether");

    it("airline Can register a flight", async () => {
      try {
        await config.flightSuretyApp.registerFlight(
          flightCode,
          timestamp,
          price,
          departure,
          destination,
          { from: config.firstAirline }
        );
      } catch (error) {
        console.log(error.toString());
      }

      const flightKey = await config.flightSuretyData.getFlightKey(
        flightCode,
        destination,
        timestamp
      );

      const isFlightRegistered = await config.flightSuretyData.isFlightRegistered.call(
        flightKey
      );

      assert.equal(isFlightRegistered, true, "Flight not registered");
    });
  });

  describe("buy flight insurance", () => {
    const destination = "HBE";
    const flightCode = "MS653";
    const timestamp = (Date.now() / 1000) | 0;
    const insurancePrice = web3.utils.toWei("1", "ether");
    const passenger = accounts[8];

    it("passenger can buy a flight insurance", async () => {
      try {
        await config.flightSuretyApp.buyInsurance(
          flightCode,
          destination,
          timestamp,
          {
            from: passenger,
            value: insurancePrice
          }
        );
      } catch (error) {
        console.log(error.toString());
      }

      const flightKey = await config.flightSuretyData.getFlightKey(
        flightCode,
        destination,
        timestamp
      );

      const amount = await config.flightSuretyData.getPassengerPaidAmount.call(
        flightKey,
        passenger
      );
      assert.equal(
        amount,
        insurancePrice,
        "Passenger should be able to buy insurance correctly"
      );
    });

    it("Airline can withdraw credited amount", async () => {
      const balanceBefore = await web3.eth.getBalance(config.firstAirline);
      
      try {
        await config.flightSuretyApp.withdraw({ from: config.firstAirline });
      } catch (error) {
        console.log(error.toString());
      }

      const balanceAfter = await web3.eth.getBalance(config.firstAirline);

      assert(+balanceBefore < +balanceAfter, "Airline withdrawal failed");
    });
  });
});
