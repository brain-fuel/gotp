package mnesia

import (
	"bytes"
	"fmt"
	"sort"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/term"
)

const snapshotVersion = 1

type SnapshotFailure enum {
	SnapshotCodecFailure(Cause etf.Failure)
	InvalidSnapshot(Detail string)
	DuplicateSnapshotTable(Name string)
	DuplicateSnapshotKey(Table string, Key term.Term)
}

func (failure SnapshotFailure) Error() string {
	match failure {
	case SnapshotCodecFailure(cause):
		return "gotp/mnesia: snapshot codec: " + cause.Error()
	case InvalidSnapshot(detail):
		return "gotp/mnesia: invalid snapshot: " + detail
	case DuplicateSnapshotTable(name):
		return fmt.Sprintf("gotp/mnesia: duplicate snapshot table %q", name)
	case DuplicateSnapshotKey(table, key):
		return fmt.Sprintf("gotp/mnesia: duplicate key %v in snapshot table %q", key, table)
	}
}

type encodedRow struct {
	row row
	key []byte
}

// assayxport:unit gotp.otp.mnesia-snapshots
func Snapshot(
	database *Database,
	codec etf.CanonicalCodec,
) result.Result[[]byte, SnapshotFailure] {
	database.mu.Lock()
	defer database.mu.Unlock()
	names := make([]string, 0, len(database.state.tables))
	for name := range database.state.tables {
		names = append(names, name)
	}
	sort.Strings(names)
	tables := make([]term.Term, 0, len(names))
	for _, name := range names {
		var rows []term.Term
		match snapshotRows(database.state.tables[name], codec) {
		case result.Err(failure):
			return result.Err[[]byte, SnapshotFailure](failure)
		case result.Ok(encoded):
			rows = encoded
		}
		tables = append(tables, term.Tuple(term.Binary([]byte(name)), term.List(rows...)))
	}
	image := term.Tuple(
		term.MustAtom("gotp_mnesia_snapshot"),
		term.Integer(snapshotVersion),
		term.List(tables...),
	)
	match codec.Encode(image) {
	case result.Err(failure):
		return result.Err[[]byte, SnapshotFailure](SnapshotCodecFailure(failure))
	case result.Ok(encoded):
		return result.Ok[[]byte, SnapshotFailure](append([]byte(nil), encoded...))
	}
}

func snapshotRows(
	rows []row,
	codec etf.CanonicalCodec,
) result.Result[[]term.Term, SnapshotFailure] {
	encoded := make([]encodedRow, 0, len(rows))
	for _, candidate := range rows {
		match codec.Encode(candidate.key) {
		case result.Err(failure):
			return result.Err[[]term.Term, SnapshotFailure](SnapshotCodecFailure(failure))
		case result.Ok(key):
			encoded = append(encoded, encodedRow{
				row: row{key: candidate.key.Clone(), value: candidate.value.Clone()},
				key: key,
			})
		}
	}
	sort.SliceStable(encoded, func(left, right int) bool {
		return bytes.Compare(encoded[left].key, encoded[right].key) < 0
	})
	terms := make([]term.Term, len(encoded))
	for index, candidate := range encoded {
		terms[index] = term.Tuple(candidate.row.key, candidate.row.value)
	}
	return result.Ok[[]term.Term, SnapshotFailure](terms)
}

func Restore(
	database *Database,
	codec etf.CanonicalCodec,
	payload []byte,
) result.Result[Mutation, SnapshotFailure] {
	var image term.Term
	match codec.Decode(payload) {
	case result.Err(failure):
		return result.Err[Mutation, SnapshotFailure](SnapshotCodecFailure(failure))
	case result.Ok(decoded):
		image = decoded
	}
	var restored state
	match decodeSnapshot(image) {
	case result.Err(failure):
		return result.Err[Mutation, SnapshotFailure](failure)
	case result.Ok(decoded):
		restored = decoded
	}
	database.mu.Lock()
	defer database.mu.Unlock()
	database.state = restored
	return result.Ok[Mutation, SnapshotFailure](Changed())
}

func decodeSnapshot(image term.Term) result.Result[state, SnapshotFailure] {
	var fields []term.Term
	match image {
	case term.TupleTerm(elements):
		fields = elements
	case _:
		return result.Err[state, SnapshotFailure](InvalidSnapshot("root is not a tuple"))
	}
	if len(fields) != 3 || !term.Equal(fields[0], term.MustAtom("gotp_mnesia_snapshot")) {
		return result.Err[state, SnapshotFailure](InvalidSnapshot("root marker or arity differs"))
	}
	match term.Int64(fields[1]) {
	case option.None:
		return result.Err[state, SnapshotFailure](InvalidSnapshot("version is not an integer"))
	case option.Some(version):
		if version != snapshotVersion {
			return result.Err[state, SnapshotFailure](InvalidSnapshot(fmt.Sprintf("unsupported version %d", version)))
		}
	}
	var tables []term.Term
	match fields[2] {
	case term.ProperListTerm(elements):
		tables = elements
	case _:
		return result.Err[state, SnapshotFailure](InvalidSnapshot("tables are not a proper list"))
	}
	restored := state{tables: make(map[string][]row, len(tables))}
	for _, tableTerm := range tables {
		match decodeSnapshotTable(tableTerm) {
		case result.Err(failure):
			return result.Err[state, SnapshotFailure](failure)
		case result.Ok(decoded):
			if _, duplicate := restored.tables[decoded.name]; duplicate {
				return result.Err[state, SnapshotFailure](DuplicateSnapshotTable(decoded.name))
			}
			restored.tables[decoded.name] = decoded.rows
		}
	}
	return result.Ok[state, SnapshotFailure](restored)
}

type decodedTable struct {
	name string
	rows []row
}

func decodeSnapshotTable(value term.Term) result.Result[decodedTable, SnapshotFailure] {
	var fields []term.Term
	match value {
	case term.TupleTerm(elements):
		fields = elements
	case _:
		return result.Err[decodedTable, SnapshotFailure](InvalidSnapshot("table entry is not a tuple"))
	}
	if len(fields) != 2 {
		return result.Err[decodedTable, SnapshotFailure](InvalidSnapshot("table entry arity differs"))
	}
	var name string
	match term.BinaryValue(fields[0]) {
	case option.None:
		return result.Err[decodedTable, SnapshotFailure](InvalidSnapshot("table name is not binary"))
	case option.Some(encoded):
		name = string(encoded)
	}
	if name == "" {
		return result.Err[decodedTable, SnapshotFailure](InvalidSnapshot("table name is empty"))
	}
	var encodedRows []term.Term
	match fields[1] {
	case term.ProperListTerm(elements):
		encodedRows = elements
	case _:
		return result.Err[decodedTable, SnapshotFailure](InvalidSnapshot("table rows are not a proper list"))
	}
	rows := make([]row, 0, len(encodedRows))
	for _, encoded := range encodedRows {
		var pair []term.Term
		match encoded {
		case term.TupleTerm(elements):
			pair = elements
		case _:
			return result.Err[decodedTable, SnapshotFailure](InvalidSnapshot("row is not a tuple"))
		}
		if len(pair) != 2 {
			return result.Err[decodedTable, SnapshotFailure](InvalidSnapshot("row arity differs"))
		}
		for _, existing := range rows {
			if term.Equal(existing.key, pair[0]) {
				return result.Err[decodedTable, SnapshotFailure](DuplicateSnapshotKey(name, pair[0].Clone()))
			}
		}
		rows = append(rows, row{key: pair[0].Clone(), value: pair[1].Clone()})
	}
	return result.Ok[decodedTable, SnapshotFailure](decodedTable{name: name, rows: rows})
}
