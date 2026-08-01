package erts

import (
    "encoding/json"
    "fmt"
    "os"
    "testing"
)

// assayxport:law gotp.erts.otp29-gen-statem-export-ledger-coverage
func TestPinnedOTPGenStatemExportLedgerCoverage(t *testing.T) {
    module := pinnedGenStatemModule(t)
    if module.digest != "29a48bbb1ce7da252ddafc5c7de34c083b981cbbfd858a152ebacf2d1ef497e9" { t.Fatalf("gen_statem digest = %s", module.digest) }
    payload, cause := os.ReadFile("../compat/otp-29.0.4.json")
    if cause != nil { t.Fatal(cause) }
    wire := genServerLedgerWire{}
    if cause := json.Unmarshal(payload, &wire); cause != nil { t.Fatal(cause) }
    ledger := map[string]string{}
    for _, item := range wire.Items { ledger[item.Capability] = item.Status }
    metadata := map[ExportKey]string{
        {Function: "module_info", Arity: 0}: "compiler metadata",
        {Function: "module_info", Arity: 1}: "compiler metadata",
        {Function: "behaviour_info", Arity: 1}: "behavior metadata",
    }
    for export := range module.exports {
        if _, classified := metadata[export]; classified { continue }
        capability := fmt.Sprintf("OTP public function gen_statem:%s/%d", export.Function, export.Arity)
        _, present := ledger[capability]
        if !present { t.Fatalf("export %s has no ledger declaration", capability) }
    }
    if len(module.exports) != 42 { t.Fatalf("gen_statem exports = %d, want 42", len(module.exports)) }
}
