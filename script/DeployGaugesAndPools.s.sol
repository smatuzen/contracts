// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "../test/Base.sol";

/// @notice Deploy script to create pools & gauges from constants and write outputs
contract DeployGaugesAndPools is Script {
  using stdJson for string;

  // --- Env / IO ---
  uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
  address public deployerAddress = vm.rememberKey(deployPrivateKey);
  string public constantsFilename = vm.envString("CONSTANTS_FILENAME"); // e.g. "base.json"
  string public outputFilename = vm.envString("OUTPUT_FILENAME");       // e.g. "Base.json"
  string public jsonConstants;
  string public jsonOutput;

  // --- Core protocol refs (decoded from DeployCore output) ---
  PoolFactory public factory;
  Voter public voter;
  address public AERO;

  // --- Input structs from constants file ---
  struct PoolNonAero {
    bool stable;
    address tokenA;
    address tokenB;
  }

  struct PoolAero {
    bool stable;
    address token;
  }

  // --- Outputs ---
  address[] public pools;
  address[] public gauges;

  constructor() {}

  function run() public {
    string memory root = vm.projectRoot();
    string memory basePath = string.concat(root, "/script/constants/");
    string memory path = string.concat(basePath, constantsFilename);

    // Load constants (pools to deploy)
    jsonConstants = vm.readFile(path);
    PoolNonAero[] memory _pools =
      abi.decode(jsonConstants.parseRaw(".pools"), (PoolNonAero[]));
    PoolAero[] memory poolsAero =
      abi.decode(jsonConstants.parseRaw(".poolsAero"), (PoolAero[]));

    // Load core addresses from DeployCore output
    path = string.concat(basePath, "output/DeployCore-");
    path = string.concat(path, outputFilename);
    jsonOutput = vm.readFile(path);
    factory = PoolFactory(abi.decode(jsonOutput.parseRaw(".PoolFactory"), (address)));
    voter = Voter(abi.decode(jsonOutput.parseRaw(".Voter"), (address)));
    AERO = abi.decode(jsonOutput.parseRaw(".AERO"), (address));

    vm.startBroadcast(deployerAddress);

    // Deploy all non-AERO pools & gauges
    for (uint256 i = 0; i < _pools.length; i++) {
      address newPool =
        factory.createPool(_pools[i].tokenA, _pools[i].tokenB, _pools[i].stable);
      address newGauge = voter.createGauge(address(factory), newPool);

      pools.push(newPool);
      gauges.push(newGauge);
    }

    // Deploy all AERO pools & gauges
    for (uint256 i = 0; i < poolsAero.length; i++) {
      address newPool =
        factory.createPool(AERO, poolsAero[i].token, poolsAero[i].stable);
      address newGauge = voter.createGauge(address(factory), newPool);

      pools.push(newPool);
      gauges.push(newGauge);
    }

    vm.stopBroadcast();

    // --- Write arrays to a single JSON object "v2" ---
    // Foundry's serialize* appends when called repeatedly with the same object key.
    string memory obj;

    // Append pools array
    for (uint256 i = 0; i < pools.length; i++) {
      obj = vm.serializeAddress("v2", "pools", pools[i]);
    }

    // Append gauges array
    for (uint256 i = 0; i < gauges.length; i++) {
      obj = vm.serializeAddress("v2", "gauges", gauges[i]);
    }

    // Write file
    path = string.concat(basePath, "output/DeployGaugesAndPools-");
    path = string.concat(path, outputFilename);
    vm.writeJson(obj, path);
  }
}
