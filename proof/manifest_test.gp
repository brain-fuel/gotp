package proof

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/result"
)

func TestAssumptionsCapAggregateAssurance(t *testing.T) {
	manifest := Manifest{
		Schema:         Schema,
		Module:         "demo",
		SourceDigest:   sixtyFourZeroes(),
		ArtifactDigest: sixtyFourZeroes(),
		Compiler:       "goplus/test",
		OTPBaseline:    "OTP-29.0.4",
		Target:         "beam",
		Dimensions: Dimensions{
			Types: ClosedVerified, Totality: ClosedVerified,
			Resources: ClosedVerified, Effects: ClosedVerified,
			Translation: ClosedVerified, Runtime: ClosedVerified,
		},
		Assumptions: []Assumption{{Kind: "nif", Subject: "demo", Reason: "foreign"}},
	}
	match manifest.Validate() {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(_):
	}
	match manifest.Aggregate() {
	case result.Err(failure):
		t.Fatal(failure.Error())
	case result.Ok(level):
		if level != BoundaryChecked {
			t.Fatalf("aggregate = %s", level)
		}
	}
}

func TestAssuranceOrderingLaw(t *testing.T) {
	levels := []Level{Foreign, BoundaryChecked, ResourceSafe, Total, ClosedVerified}
	law := func(left uint8, right uint8) bool {
		actual := levels[int(left)%len(levels)]
		minimum := levels[int(right)%len(levels)]
		match AtLeast(actual, minimum) {
		case result.Ok(accepted):
			return accepted == (int(left)%len(levels) >= int(right)%len(levels))
		case result.Err(_):
			return false
		}
	}
	match result.Of(true, quick.Check(law, nil)) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}

func sixtyFourZeroes() string {
	return "0000000000000000000000000000000000000000000000000000000000000000"
}
