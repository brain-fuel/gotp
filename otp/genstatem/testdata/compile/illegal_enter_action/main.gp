package main

import "goforge.dev/gotp/otp/genstatem"

var invalid []genstatem.EnterAction = []genstatem.EnterAction{genstatem.Postpone(true)}

func main() {}
