RPC_URL ?= http://127.0.0.1:8545
# First unlocked account on a default Anvil node.
DEPLOYER ?= 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
USDC_ADDRESS ?=

.PHONY: deploy
deploy:
	USDC_ADDRESS="$(USDC_ADDRESS)" forge script script/ComputeOptionRegistry.s.sol:ComputeOptionRegistryScript \
		--rpc-url "$(RPC_URL)" \
		--sender "$(DEPLOYER)" \
		--unlocked \
		--broadcast
