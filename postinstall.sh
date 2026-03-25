#!/bin/bash
# Patch @uniswap/v4-core exact pragma to caret for solc 0.8.28 compatibility
# Use portable sed -i: GNU sed needs -i'', BSD/macOS sed needs -i ''
if sed --version 2>/dev/null | grep -q GNU; then
  SED_INPLACE=(sed -i)
else
  SED_INPLACE=(sed -i '')
fi
find node_modules/@uniswap/v4-core -name "*.sol" -type f -exec "${SED_INPLACE[@]}" 's/pragma solidity 0.8.26;/pragma solidity ^0.8.26;/' {} + 2>/dev/null
find node_modules/@uniswap/v4-periphery -name "*.sol" -type f -exec "${SED_INPLACE[@]}" 's/pragma solidity 0.8.26;/pragma solidity ^0.8.26;/' {} + 2>/dev/null
exit 0
