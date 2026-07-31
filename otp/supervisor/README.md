# Typed supervisor

The bootstrap supervisor implements static `one_for_one`, `one_for_all`, and
`rest_for_one` trees over the deterministic GoTP kernel. It preserves child
start order, reverses termination order, never restarts temporary children,
applies transient restart rules to the triggering child, and bounds restart
intensity with an explicit clock capability.

Strategies, restart policies, and child lifecycle are closed Go+ enums.
Construction and child starts return typed results; children move through
`Pending`, `Running`, and `Inactive` states without invalid-PID sentinels.

The implementation intentionally does not claim the complete OTP supervisor
API. Dynamic child administration, significant children, automatic shutdown,
shutdown timeouts, `simple_one_for_one`, names, and `sys` integration remain in
the compatibility ledger.
