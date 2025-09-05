# LoopedSonicVault

LoopedSonicVault is an ERC20 vault token that implements a looped LST strategy combining stS with Aave v3 on the Sonic network. The vault uses a flash-accounting execution flow similar to Uni V4 and Balncer V3. This allows for custom router implementations for managing the deposit and withdrawal of assets, supporting flexibility in sourcing the best rate when looping and unwinding. The vault maintains strict safety invariants during an operation.
