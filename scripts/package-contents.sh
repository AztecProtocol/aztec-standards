# shellcheck shell=bash disable=SC2034
# What the npm package ships, read by build-package.sh (to assemble it) and smoke-test-package.sh (to check it).

# Wrappers (src/artifacts/<Name>.ts) that ship: the standards and the ARC-403 interface stubs the README documents.
PUBLISHED=(Arc403Authorizer Arc403MultiTokenAuthorizer Dripper Escrow MultiToken NFT Token Vault VaultDeployer)
# Fixtures of the Noir test suites; their wrappers never ship. A wrapper in neither list fails the build, so a new
# contract is classified on purpose rather than by default.
TEST_FIXTURES=(AuthorizationContract GenericProxy MultiTokenAuthorizationContract TestLogic)
# Fixture artifacts that ship anyway, in artifacts/target/ only: Token's Noir tests deploy them, and downstream forks
# of Token stage them from the package to run those tests under TXE.
FIXTURE_ARTIFACTS=(generic_proxy-GenericProxy test_authorization_contract-AuthorizationContract)
