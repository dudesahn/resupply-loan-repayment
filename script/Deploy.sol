// SPDX-License-Identifier: AGLP-3.0
pragma solidity 0.8.28;

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {LoanAccounting} from "src/LoanAccounting.sol";
import {Converter} from "src/Converter.sol";

contract DeployScript is Script {
    address public loanAccounting;
    address public converter;
    
    // Configuration
    uint256 public constant LOAN_PRINCIPAL = 1_130_000e18; // $1.13M crvUSD loan principal
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("RESUPPLY_PK");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer:", deployer);
        console.log("Loan principal:", LOAN_PRINCIPAL);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy LoanAccounting first
        LoanAccounting loanAccountingContract = new LoanAccounting(LOAN_PRINCIPAL);
        loanAccounting = address(loanAccountingContract);
        console.log("LoanAccounting deployed at:", loanAccounting);
        
        // Deploy Converter with LoanAccounting as repayer
        Converter converterContract = new Converter(loanAccounting);
        converter = address(converterContract);
        console.log("Converter deployed at:", converter);
        
        vm.stopBroadcast();
    }
}
