package main

import (
	"os"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/compat"
)

func inspectParity(arguments []string) result.Result[CommandResult, Failure] {
	if len(arguments) > 1 {
		return result.Err[CommandResult, Failure](UsageFailure("parity accepts at most one compatibility ledger"))
	}
	path := "compat/otp-29.0.4.json"
	if len(arguments) == 1 {
		path = arguments[0]
	}
	payload, err := os.ReadFile(path)
	if err != nil {
		return result.Err[CommandResult, Failure](IOFailure("read compatibility ledger", err))
	}
	match compat.Parse(payload) {
	case result.Ok(ledger):
		return writeJSON(compat.Summarize(ledger))
	case result.Err(failure):
		return result.Err[CommandResult, Failure](VerificationFailure(compat.FailureMessage(failure)))
	}
}
