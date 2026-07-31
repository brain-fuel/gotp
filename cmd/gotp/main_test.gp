package main

import (
	"testing"

	"goforge.dev/goplus/std/result"
)

func TestRunRequiresCommand(t *testing.T) {
	match run([]string{}) {
	case result.Err(failure):
		match failure {
		case UsageFailure(_):
		case _:
			t.Fatalf("failure = %s", failure.Error())
		}
	case result.Ok(_):
		t.Fatal("empty command completed")
	}
}

func TestRunRejectsUnknownCommand(t *testing.T) {
	match run([]string{"not-a-command"}) {
	case result.Err(failure):
		match failure {
		case UsageFailure(_):
		case _:
			t.Fatalf("failure = %s", failure.Error())
		}
	case result.Ok(_):
		t.Fatal("unknown command completed")
	}
}
