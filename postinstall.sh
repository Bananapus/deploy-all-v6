#!/bin/bash
# Patch @uniswap/v4-core exact pragma to caret for solc 0.8.28 compatibility
find node_modules/@uniswap/v4-core -name "*.sol" -type f -exec sed -i '' 's/pragma solidity 0.8.26;/pragma solidity ^0.8.26;/' {} + 2>/dev/null
find node_modules/@uniswap/v4-periphery -name "*.sol" -type f -exec sed -i '' 's/pragma solidity 0.8.26;/pragma solidity ^0.8.26;/' {} + 2>/dev/null
