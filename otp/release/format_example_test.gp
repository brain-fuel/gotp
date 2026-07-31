package release

import (
	"testing"

	"goforge.dev/gotp/term"
)

// assayxport:law gotp.otp.systools-relup-diagnostic-laws
func TestRelupDiagnosticsMatchPinnedOTPForms(t *testing.T) {
	application := ApplicationSpec{Name: "kernel", Version: "9.0"}
	release := ReleaseSpec{Name: "demo", Version: "2.0"}
	cases := []struct { found string; want string }{
		{FormatRelupError(FileProblem("demo.rel", OpenFile())), "Could not open file demo.rel\n"},
		{FormatRelupError(NoRelup("demo.appup", application, "8.0")), "No release upgrade script entry for kernel-9.0 to kernel-8.0 in file demo.appup\n"},
		{FormatRelupError(MissingSASL(release)), "No sasl application in release demo, 2.0. Can not be upgraded."},
		{FormatRelupWarning(ERTSVersionChanged(term.MustAtom("old"), term.MustAtom("new"))), "*WARNING* The ERTS version changed between old and new\n"},
		{FormatRelupWarning(PreR15EmulatorUpgrade()), "*WARNING* Upgrade from an OTP version earlier than R15. New code should be compiled with the old emulator.\n"},
		{FormatRelupWarning(RawRelupWarning(term.Tuple(term.MustAtom("unknown"), term.Integer(3)))), "*WARNING* {unknown,3}\n"},
	}
	for _, test := range cases { if test.found != test.want { t.Fatalf("diagnostic = %q, want %q", test.found, test.want) } }
}

func TestWarningsAsErrorsUseUnprefixedPinnedFormatting(t *testing.T) {
	found := FormatRelupError(WarningsTreatedAsErrors([]RelupWarning{
		ERTSVersionChanged(term.MustAtom("old"), term.MustAtom("new")),
		RawRelupWarning(term.MustAtom("other")),
	}))
	want := "Warnings being treated as errors:\nThe ERTS version changed between old and new\nother\n"
	if found != want { t.Fatalf("diagnostic = %q, want %q", found, want) }
}
