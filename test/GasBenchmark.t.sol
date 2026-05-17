// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {RWAAMM} from "../src/RWAAMM.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title GasBenchmarkTest
 * @notice Measures gas: Yul sqrt vs pure-Solidity sqrt.
 *         Output is captured in the CI log and cited in GasReport.md.
 *
 * Run with: forge test --match-contract GasBenchmarkTest -vvv
 */
contract GasBenchmarkTest is Test {
    RWAAMM public amm;
    MockERC20 public t0;
    MockERC20 public t1;

    address admin = makeAddr("admin");

    function setUp() public {
        t0 = new MockERC20("T0", "T0", 18);
        t1 = new MockERC20("T1", "T1", 18);
        amm = new RWAAMM(address(t0), address(t1), admin);
    }

    function test_GasBenchmark_Sqrt_Yul_vs_Solidity() public view {
        uint256[5] memory inputs = [
            uint256(0),
            uint256(4),
            uint256(1e18),
            uint256(1e36),
            uint256(type(uint128).max)
        ];

        for (uint256 i = 0; i < inputs.length; i++) {
            uint256 x = inputs[i];

            uint256 gasBeforeYul = gasleft();
            uint256 resultYul = amm.sqrtYul(x);
            uint256 gasYul = gasBeforeYul - gasleft();

            uint256 gasBeforeSol = gasleft();
            uint256 resultSol = amm.sqrtSolidity(x);
            uint256 gasSol = gasBeforeSol - gasleft();

            console.log("=== sqrt(%s) ===", x);
            console.log("  Yul result:      ", resultYul, " gas:", gasYul);
            console.log("  Solidity result: ", resultSol, " gas:", gasSol);

            if (gasYul < gasSol) {
                console.log("  -> Yul saves", gasSol - gasYul, "gas");
            } else {
                console.log("  -> Solidity saves", gasYul - gasSol, "gas");
            }

            // Results must match
            assertEq(resultYul, resultSol);
        }
    }
}
