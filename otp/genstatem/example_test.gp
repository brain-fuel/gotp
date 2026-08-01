package genstatem

import (
    "fmt"

    "goforge.dev/goplus/std/result"
    "goforge.dev/gotp/term"
)

func ExampleEncodeEventHandlerResult() {
    resultValue := EventNext[string, term.Term](
        "active",
        term.Integer(4),
        []Action{NextEvent(InternalEvent(), term.MustAtom("continue"))},
    )
    match EncodeEventHandlerResult(resultValue, AtomCodec{}, TermCodec{}) {
    case result.Err(failure): fmt.Println(failure)
    case result.Ok(encoded): match encoded.Kind() { case term.TupleKind: fmt.Println("tuple"); case _: fmt.Println("other") }
    }
    // Output: tuple
}

func ExampleDecodeAction() {
    encoded := term.Tuple(term.MustAtom("next_event"), term.MustAtom("internal"), term.MustAtom("work"))
    match DecodeAction(encoded) {
    case result.Err(failure): fmt.Println(failure)
    case result.Ok(action): match action { case NextEvent(_, _): fmt.Println("next event"); case _: fmt.Println("other") }
    }
    // Output: next event
}
