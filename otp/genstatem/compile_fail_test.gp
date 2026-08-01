package genstatem

import (
    "os/exec"
    "strings"
    "testing"
)

// assayxport:law gotp.otp.genstatem-illegal-results-do-not-compile
func TestIllegalGenStatemProgramsDoNotCompile(t *testing.T){cases:=[]string{"illegal_enter_action","illegal_callback_result"};for _,name:=range cases{command:=exec.Command("go","tool","goplus","gen","./otp/genstatem/testdata/compile/"+name);command.Dir="../..";output,cause:=command.CombinedOutput();if cause==nil{t.Fatalf("%s compiled successfully",name)};if !strings.Contains(string(output),"cannot")&&!strings.Contains(string(output),"mismatch"){t.Fatalf("%s failed without type diagnostic: %s",name,output)}}}
