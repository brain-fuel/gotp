package main

import "goforge.dev/gotp/otp/genstatem"

var event genstatem.EventHandlerResult[int,int] = genstatem.EventKeep[int,int](1,nil)
var invalid genstatem.StateEnterResult[int,int] = event

func main() {}
