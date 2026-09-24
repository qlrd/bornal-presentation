#import "@preview/slydst:0.1.4": *

#show: slides.with(
  title: "Bornal",
  subtitle: "DIY krux integration tests",
  date: none,
  authors: ("qlrd - Krux contributor",),
  layout: "medium",
  ratio: 4/3,
  title-color: none,
)

#show link: it => {
  set text(blue)
  if type(it.dest) != str {
    it
  }
  else {
    underline(it)
  }
}

// ===========================================================================
== Idea summary

#align(horizon)[
  *Bitcoin Test Framework(s)* reflections and practices.
]

= Definitions @qlrd2025

== Definitions by `obj`, POV and beneficiary

#align(horizon)[
  @avachown2018 names *what* is tested:

  #definition[
    The functional [tests] test the RPCs.
  ]
]

#align(horizon)[
  @jahr2019 names *who is looking*:

  #definition[
    (...) it takes pretty long. In general they take longer than unit tests.
    (...) pay some attention to how you write the tests and how many you write.
  ]
]

#align(horizon)[
  *Neither* used definitions names a beneficiary.
]

// ===========================================================================
= Candidates

== Reference itself @bitcoincore_test_framework (oop approach)

#align(horizon)[
  ```python
  class MyTest(BitcoinTestFramework):

      def set_test_params(self):
          self.num_nodes = 2

      def run_test(self):
          self.connect_nodes(0, 1)
          self.generate(self.nodes[0], 1)
          self.sync_all()
  ```
// - every node in `self.nodes` is a `bitcoind`;
// - one build: the tree you are standing in;
// - one dialect: `authproxy`;
// - every failure is Core's.
// - *BitcoinTestFramework* uses a metaclass, *BitcoinTestMetaClass*
]

== C-lightning @pyln_testing (fixture and yield with core)

#align(horizon)[
  ```python
  @pytest.fixture
  def bitcoind(request, directory, teardown_checks):...
  
  @pytest.fixture
  def node_factory(request, directory, bitcoind, ...):
      nf = NodeFactory(request, test_name, bitcoind, ...)
      yield nf
      nf.killall([not n.may_fail for n in nf.nodes])

  def test_pay(node_factory, bitcoind):...
  ```
  // - a `pip` package: Core Lightning tests itself with it, community plugins
  //   reuse it;
  // - `bitcoind` and `lightningd` come from `PATH`: you build them;
  // - `TEST_NETWORK=liquid-regtest` swaps `BitcoinD` for `ElementsD`;
  // - any RPC is a method: `__getattr__` $arrow$ a throwaway `BitcoinProxy` per
  //   call. Liana inherits this;
  // - "synced" means `getinfo()["blockheight"]` equals `bitcoind`'s;
  // - at teardown, a `BROKEN` line, a `crash.log` or a valgrind report in a
  //  node's log fails the test, naming the node (`lightningd-1`).
]

== Liana @liana_tests fixture and yield with core + electrs + liana

#align(horizon)[
  ```python
  @pytest.fixture
  def bitcoind(directory):
      bitcoind = Bitcoind(bitcoin_dir=directory / "bitcoind")
      bitcoind.startup()
      bitcoind.rpc.generatetoaddress(101, ...)
      yield bitcoind
      bitcoind.cleanup()

  @pytest.fixture
  def lianad(bitcoin_backend, directory): ...
  ```
  //- lineage: `pyln-testing` $arrow$ revaultd @revaultd $arrow$ liana;
  // - binaries from `BITCOIND_PATH`, `ELECTRS_PATH`, `LIANAD_PATH`: you build
  //  them;
  // - `bitcoin_backend` is `Bitcoind` or `Electrs`, chosen by an env var;
  // - any RPC is a method: `__getattr__` $arrow$ `AuthServiceProxy`;
  // - a fresh directory and a fresh chain per test.
]

== Floresta @floresta_tests Based fixture and yield with core + utreexod + floresta

#align(horizon)[
  ```python
  @pytest.fixture
  def node_manager(setup_logging, request):
      manager = FlorestaTestFramework(...)
      yield manager
      manager.stop()

  @pytest.fixture
  def bitcoind_node(node_manager) -> Node:
      node = node_manager.add_node_default_args(
          variant=NodeType.BITCOIND)
      node_manager.run_node(node)
      return node
  ```
  // Lineage: Core. `p2p.py`, `messages.py`, `key.py` are vendored from
  // `test_framework`.

  // `prepare.sh` builds `bitcoind`, `utreexod` and `florestad` into a
  // `BINARIES_DIR`.
]

== See it from outside...

#align(horizon)[
  #table(
    columns: (auto, 1fr, 1fr, 1fr, 1fr),
    inset: 5pt,
    [], [*Core*], [*C-lightning*], [*Liana*], [*Floresta*],
    [lineage], [itself], [itself], [C-lightning], [Core#footnote[It started with similar Core version]],
    [who runs it], [`main()`], [pytest fixtures], [pytest fixtures],
      [pytest fixtures],
    [binaries], [the tree], [`PATH`], [`*_PATH` env], [`prepare.sh`],
    [RPC], [`authproxy`], [`__getattr__` proxy], [`__getattr__` proxy],
      [`node.rpc`],
    [daemons], [`bitcoind`], [`bitcoind`, `lightningd`],
      [`bitcoind`, `electrs`, `lianad`],
      [`bitcoind`, `utreexod`, `florestad`],
    [scope], [one script], [function], [function], [function, class],
  )
]

= Challenges

==

#align(horizon)[
  + Build
  + Dialect
  + Lifecycle
  + Synchronization
  + Oracle
  + Attribution
  + Version matrix
  // There is no release binary for every cell of tag $times$ wallet $times$
  // platform $times$ implementation.

  // One client class no longer fits.

  // With one implementation, every node is a peer. `electrs` needs a *started*
  // `bitcoind`. There is an order to start, and the reverse order to stop.

  // "Synced" means:
  //  block count, for `bitcoind`;
  // index tip, for `electrs`;
  // `lastprocessedblock`, for a wallet.
  //  specific RPCs for `utreexo`, `floresta` and `liana`

  // When someone disagrees, which one is wrong?
  // Core, by default. But the test has to say so, not assume it.

  // With one implementation, the bug is yours. With three, whose is it?

  // ```
  // AssertionError:
  //     'bitcoind' at 127.0.0.1:41733 expected 1 blocks, got 0
  // ```
  // The message has to name the node, or the failure is nobody's.

  // One implementation has one version at a time.
  // Three have a matrix, and the interesting bugs sit in the cells:

  // ```bash
  // $> pytest --build-bitcoin 30.2 --build-electrs latest ...
  // ```

  // Inside a single-implementation test there is no trust boundary.
  // With a signer in the picture, the test *is* the boundary.
  //- Core holds the `tpub`, never the `tprv`: the coordinator is not trusted
  //  with the key;
  // - blocks are mined to an unspendable address: no wallet has to be trusted
  //  for the chain to advance;
  // - a second node only sees the transaction: the network is a witness.
  // - A test framework is a verification model made executable.
]

// ===========================================================================
= bornal @bornal

== Test the test

#align(horizon)[
  ```bash
  # install
  $> uv add --dev git+https://github.com/qlrd/bornal.git@v0.0.1

  # check the help
  $> uv run bornal -h

  # scaffold a template test
  $> uv run bornal create the_test --template wallet-roundtrip

  # first time: minutes of cmake
  $> uv run pytest --build-bitcoin latest \
                   --wallet \
                   tests/integration/test_the_test.py

  # next time it will be faster
  $> uv run pytest tests/integration/test_the_test.py
  ```
]

==

#align(horizon)[
  ```toml
  # entry point for the plugin system
  [project.entry-points."bornal.daemons"]
  bitcoin-core = "bornal.plugins.bitcoind:CoreCompiler"
  electrs      = "bornal.plugins.electrs:ElectrsCompiler"

  # Access clients and daemons through `integration_test` fixture.
  [project.entry-points.pytest11]
  bornal = "bornal.fixtures"
  ```
]

== 
#align(horizon)[
  + `Compiler` $arrow$ *build*;
  + `Daemon` $arrow$ *lifecycle*;
  + `Client` $arrow$ *dialect*;
  + entry points $arrow$ *ownership*;
  + helpers that name the node $arrow$ *attribution*;
  + the watch-only rule $arrow$ *verification*.
]

== Approach

#align(horizon)[
```python
@pytest.fixture(scope="module")
def test_factory(request):
    pytest.fail() # SCOPE IT YOURSELF 

@pytest.fixture(scope="module")
def integration_test(request, test_factory):
    test = test_factory(data_dir=(...),...) # prev `BaseTest` instance
    test._on_set_test_params() # runs YOURS `set_test_params` hook
    try:
      test._on_run_test()  # runs YOURS `run_test` hook
      yield test
    finally:
      test._on_stop_test() # runs YOURS `stop_test` hook
```
]

== Example of `conftest.py`

#align(horizon)[
  ```python
  N = 2

  class BaseTest(IntegrationTest):
      def set_test_params(self):
          # "bitcoin-core", "electrs", "utreexo", "floresta", "liana", etc.
          for _ in range(N):
              self.add_backend(<impl>, <daemon-args>=...)
          ...
          
      def run_test(self):
          self.log.info("Example test running") # do anything
          ...
  ```
]

==

#align(horizon)[
  ```python        
  @pytest.fixture(scope="module")
  def test_factory(request):
      return BaseTest # bornal will call an instance of this class

  # define abstract and consensual names, it's easier
  @pytest.fixture
  def alice(integration_test):
      return integration_test.backends[0]

  @pytest.fixture
  def bob(integration_test):
      return integration_test.backends[1]
  ```
]

== Example of a `test_the_test.py`

#align(horizon)[
  ```python
  from bornal.plugins.bitcoind import UNSPENDABLE_ADDRESS
  from bornal.fixtures import (
      assert_block_count,
      connect_p2p,
      generate_to_address,
      sync_blocks # bornal has more in its bag
  )
  ```
]

==

#align(horizon)[
  ```python
  # Both nodes have already booted
  def test_000_connect_p2p(alice, bob):
      connect_p2p(alice, bob)

  # Nodes are still up and connected, so the order matters
  def test_001_generate(alice):
      generate_to_address(alice, UNSPENDABLE_ADDRESS, 1)

  # After yielding to ALL tests, the nodes will stop.
  def test_002_sync_blocks(alice, bob):
      sync_blocks(alice, bob)
      assert_block_count(bob, 1)
  ```
]

= WIP with bornal: Krux integration tests

== `krux-integration-tests` @krux_integration_tests

#align(horizon)[
  - two `bitcoin-core` nodes: one *coordinates*, the other *witnesses*;
  - Core imports the `tpub`, funds it, builds the unsigned PSBT @bip174;
  - the Python modules of krux/embit inspect and sign;
  - Core finalizes and broadcasts; the witness should see the tx;
  - Krux must refuse: wrong purpose, wrong network, wrong policy;
  - and malformed PSBTs, fabricated previous txs, non-standard sighashes,
    outputs above inputs.
  + *logging* // the RPC client logs every call with its parameters; pytest captures that, CI keeps it;
  + *persistence* // Core writes imported keys to a datadir that is reused;
  + *fidelity* // a test could pass without Krux signing anything.
]

// ===========================================================================
= Plans

== To solve

#align(horizon)[
  - *lifecycle* // `electrs` cannot be declared from `set_test_params()`;
  - *oracle* // Core is still the default answer, by convention;
  - *drift* // the tool moves, the examples lag;
  - *plugins* // `btcd`, `utreexod`, `florestad`, `lianad` are TODO.
  - *signer warnet* // with nodes AND signers: krux, kern, seedsigner, specter diy, jade diy...
  // - FFI bindings to signer firmware: Krux already runs as a Python module
  //   under pytest; C cores through `ctypes` or `cffi`;
  // - many signers, one regtest/signet: Core coordinates, `electrs` indexes, a second
  //  node witnesses;
  // - multisig across vendors, PSBT round-trips, and above all the refusals.
]

= Bibliography
== Bibliography
#bibliography("main.bib")

== Appendix I: "Cangaceiro" with bornals @cangacologia2025

#align(horizon)[
  #figure(
    image("cangaceiro_with_bornals.png", height: 60%),
    caption: ["Cangaceiro" with bornals carrying a variety of tools and meals,
    to survive the aridness and a hard way of life @wikipedia2026.]
  )
]
