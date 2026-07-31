package compat

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"sort"
	"strings"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

const (
	jvmPublic = 0x0001
	jvmPrivate = 0x0002
	jvmProtected = 0x0004
	jvmStatic = 0x0008
	jvmFinal = 0x0010
	jvmBridge = 0x0040
	jvmInterface = 0x0200
	jvmSynthetic = 0x1000
	jvmAnnotation = 0x2000
	jvmEnum = 0x4000
)

type JavaSymbolKind enum {
	JavaClass()
	JavaInterface()
	JavaAnnotation()
	JavaEnum()
	JavaField()
	JavaConstructor()
	JavaMethod()
}

type JavaSymbol struct {
	Kind string `json:"kind"`
	Class string `json:"class"`
	Name string `json:"name"`
	Descriptor string `json:"descriptor"`
	GenericSignature string `json:"generic_signature,omitempty"`
	Exceptions []string `json:"exceptions,omitempty"`
	MetadataDigest string `json:"metadata_digest,omitempty"`
	Visibility string `json:"visibility"`
	Static bool `json:"static,omitempty"`
	Final bool `json:"final,omitempty"`
	Synthetic bool `json:"synthetic,omitempty"`
	Bridge bool `json:"bridge,omitempty"`
}

type JavaClassAPI struct {
	Class string
	Symbols []JavaSymbol
}

type JavaFailure enum {
	JavaClassRejected(Path string, Detail string)
	JavaInventoryRejected(Detail string)
	JavaJSONRejected(Cause string)
}

func (failure JavaFailure) Error() string {
	match failure {
	case JavaClassRejected(path, detail): return "gotp/compat: JVM class rejected " + path + ": " + detail
	case JavaInventoryRejected(detail): return "gotp/compat: Java inventory rejected: " + detail
	case JavaJSONRejected(cause): return "gotp/compat: Java inventory JSON rejected: " + cause
	}
}

type classCursor struct {
	data []byte
	offset int
	failure option.Option[string]
}

func (cursor *classCursor) take(size int) []byte {
	match cursor.failure {
	case option.Some(_): return nil
	case option.None:
	}
	if size < 0 || cursor.offset > len(cursor.data)-size {
		cursor.failure = option.Some[string](fmt.Sprintf("truncated at byte %d requesting %d", cursor.offset, size))
		return nil
	}
	value := cursor.data[cursor.offset:cursor.offset+size]
	cursor.offset += size
	return value
}

func (cursor *classCursor) u1() uint8 {
	value := cursor.take(1)
	if len(value) != 1 { return 0 }
	return value[0]
}

func (cursor *classCursor) u2() uint16 {
	value := cursor.take(2)
	if len(value) != 2 { return 0 }
	return binary.BigEndian.Uint16(value)
}

func (cursor *classCursor) u4() uint32 {
	value := cursor.take(4)
	if len(value) != 4 { return 0 }
	return binary.BigEndian.Uint32(value)
}

type constantEntry struct {
	tag uint8
	a uint32
	b uint32
	text string
}

type classAttribute struct {
	name string
	data []byte
}

func ParseJVMClass(path string, data []byte) result.Result[JavaClassAPI, JavaFailure] {
	cursor := classCursor{data: data, failure: option.None[string]}
	if cursor.u4() != 0xCAFEBABE { return result.Err[JavaClassAPI, JavaFailure](JavaClassRejected(path, "bad magic")) }
	cursor.u2()
	cursor.u2()
	poolCount := int(cursor.u2())
	if poolCount < 1 || poolCount > 65535 { return result.Err[JavaClassAPI, JavaFailure](JavaClassRejected(path, "invalid constant-pool count")) }
	pool := make([]constantEntry, poolCount)
	for index := 1; index < poolCount; index++ {
		tag := cursor.u1()
		entry := constantEntry{tag: tag}
		switch tag {
		case 1:
			length := int(cursor.u2())
			entry.text = string(cursor.take(length))
		case 3, 4: entry.a = cursor.u4()
		case 5, 6:
			entry.a = cursor.u4(); entry.b = cursor.u4(); pool[index] = entry; index++; continue
		case 7, 8, 16, 19, 20: entry.a = uint32(cursor.u2())
		case 9, 10, 11, 12, 17, 18: entry.a = uint32(cursor.u2()); entry.b = uint32(cursor.u2())
		case 15: entry.a = uint32(cursor.u1()); entry.b = uint32(cursor.u2())
		default: return result.Err[JavaClassAPI, JavaFailure](JavaClassRejected(path, fmt.Sprintf("unknown constant-pool tag %d", tag)))
		}
		pool[index] = entry
	}
	match cursor.failure {
	case option.Some(detail): return result.Err[JavaClassAPI, JavaFailure](JavaClassRejected(path, detail))
	case option.None:
	}
	access := cursor.u2()
	thisClass := cursor.u2()
	superClass := cursor.u2()
	interfaces := make([]string, int(cursor.u2()))
	for index := range interfaces {
		match className(pool, cursor.u2()) {
		case option.None: return result.Err[JavaClassAPI, JavaFailure](JavaClassRejected(path, "invalid interface class reference"))
		case option.Some(name): interfaces[index] = name
		}
	}
	var class string
	match className(pool, thisClass) {
	case option.None: return result.Err[JavaClassAPI, JavaFailure](JavaClassRejected(path, "invalid this_class reference"))
	case option.Some(name): class = name
	}
	symbols := []JavaSymbol{}
	fieldCount := int(cursor.u2())
	for index := 0; index < fieldCount; index++ {
		match parseJavaMember(&cursor, pool, class, true) {
		case result.Err(failure): return result.Err[JavaClassAPI, JavaFailure](JavaClassRejected(path, failure))
		case result.Ok(symbol):
			match symbol {
			case option.None:
			case option.Some(symbol): symbols = append(symbols, symbol)
			}
		}
	}
	methodCount := int(cursor.u2())
	for index := 0; index < methodCount; index++ {
		match parseJavaMember(&cursor, pool, class, false) {
		case result.Err(failure): return result.Err[JavaClassAPI, JavaFailure](JavaClassRejected(path, failure))
		case result.Ok(symbol):
			match symbol {
			case option.None:
			case option.Some(symbol): symbols = append(symbols, symbol)
			}
		}
	}
	match readClassAttributes(&cursor, pool) {
	case result.Err(detail): return result.Err[JavaClassAPI, JavaFailure](JavaClassRejected(path, detail))
	case result.Ok(attributes):
		if access&jvmPrivate == 0 && access&(jvmPublic|jvmProtected) != 0 {
			super := ""
			if superClass != 0 {
				match className(pool, superClass) {
				case option.None: return result.Err[JavaClassAPI, JavaFailure](JavaClassRejected(path, "invalid super_class reference"))
				case option.Some(name): super = name
				}
			}
			descriptor := "extends=" + super + ";implements=" + strings.Join(interfaces, ",")
			kind := javaClassKind(access)
			symbols = append(symbols, JavaSymbol{Kind: kind, Class: class, Name: class, Descriptor: descriptor, GenericSignature: signatureAttribute(attributes, pool), MetadataDigest: metadataDigest(attributes, pool), Visibility: javaVisibility(access), Final: access&jvmFinal != 0, Synthetic: access&jvmSynthetic != 0})
		}
	}
	match cursor.failure {
	case option.Some(detail): return result.Err[JavaClassAPI, JavaFailure](JavaClassRejected(path, detail))
	case option.None:
	}
	if cursor.offset != len(data) { return result.Err[JavaClassAPI, JavaFailure](JavaClassRejected(path, "trailing class-file bytes")) }
	return result.Ok[JavaClassAPI, JavaFailure](JavaClassAPI{Class: class, Symbols: symbols})
}

func parseJavaMember(cursor *classCursor, pool []constantEntry, class string, field bool) result.Result[option.Option[JavaSymbol], string] {
	access := cursor.u2()
	nameIndex := cursor.u2()
	descriptorIndex := cursor.u2()
	match utf8Constant(pool, nameIndex) {
	case option.None: return result.Err[option.Option[JavaSymbol], string]("invalid member name reference")
	case option.Some(name):
		match utf8Constant(pool, descriptorIndex) {
		case option.None: return result.Err[option.Option[JavaSymbol], string]("invalid member descriptor reference")
		case option.Some(descriptor):
			match readClassAttributes(cursor, pool) {
			case result.Err(detail): return result.Err[option.Option[JavaSymbol], string](detail)
			case result.Ok(attributes):
				if access&(jvmPublic|jvmProtected) == 0 || name == "<clinit>" { return result.Ok[option.Option[JavaSymbol], string](option.None[JavaSymbol]) }
				kind := "method"
				if field { kind = "field" } else if name == "<init>" { kind = "constructor" }
				return result.Ok[option.Option[JavaSymbol], string](option.Some[JavaSymbol](JavaSymbol{Kind: kind, Class: class, Name: name, Descriptor: descriptor, GenericSignature: signatureAttribute(attributes, pool), Exceptions: exceptionAttribute(attributes, pool), MetadataDigest: metadataDigest(attributes, pool), Visibility: javaVisibility(access), Static: access&jvmStatic != 0, Final: access&jvmFinal != 0, Synthetic: access&jvmSynthetic != 0, Bridge: !field && access&jvmBridge != 0}))
			}
		}
	}
}

func readClassAttributes(cursor *classCursor, pool []constantEntry) result.Result[[]classAttribute, string] {
	count := int(cursor.u2())
	attributes := make([]classAttribute, 0, count)
	for index := 0; index < count; index++ {
		nameIndex := cursor.u2()
		length := cursor.u4()
		if uint64(length) > uint64(len(cursor.data)) { return result.Err[[]classAttribute, string]("attribute length exceeds class file") }
		match utf8Constant(pool, nameIndex) {
		case option.None: return result.Err[[]classAttribute, string]("invalid attribute name reference")
		case option.Some(name): attributes = append(attributes, classAttribute{name: name, data: append([]byte{}, cursor.take(int(length))...)})
		}
	}
	match cursor.failure {
	case option.Some(detail): return result.Err[[]classAttribute, string](detail)
	case option.None: return result.Ok[[]classAttribute, string](attributes)
	}
}

func utf8Constant(pool []constantEntry, index uint16) option.Option[string] {
	if index == 0 || int(index) >= len(pool) || pool[index].tag != 1 { return option.None[string] }
	return option.Some[string](pool[index].text)
}

func className(pool []constantEntry, index uint16) option.Option[string] {
	if index == 0 || int(index) >= len(pool) || pool[index].tag != 7 { return option.None[string] }
	return utf8Constant(pool, uint16(pool[index].a))
}

func signatureAttribute(attributes []classAttribute, pool []constantEntry) string {
	for _, attribute := range attributes {
		if attribute.name == "Signature" && len(attribute.data) == 2 {
			match utf8Constant(pool, binary.BigEndian.Uint16(attribute.data)) {
			case option.None: return ""
			case option.Some(signature): return signature
			}
		}
	}
	return ""
}

func exceptionAttribute(attributes []classAttribute, pool []constantEntry) []string {
	for _, attribute := range attributes {
		if attribute.name != "Exceptions" || len(attribute.data) < 2 { continue }
		count := int(binary.BigEndian.Uint16(attribute.data[:2]))
		if len(attribute.data) != 2+count*2 { return nil }
		exceptions := make([]string, 0, count)
		for index := 0; index < count; index++ {
			match className(pool, binary.BigEndian.Uint16(attribute.data[2+index*2:4+index*2])) {
			case option.None: return nil
			case option.Some(name): exceptions = append(exceptions, name)
			}
		}
		return exceptions
	}
	return nil
}

func metadataDigest(attributes []classAttribute, pool []constantEntry) string {
	semantic := []classAttribute{}
	for _, attribute := range attributes {
		switch attribute.name {
		case "RuntimeVisibleAnnotations", "RuntimeVisibleParameterAnnotations", "AnnotationDefault", "ConstantValue", "MethodParameters", "PermittedSubclasses", "Record": semantic = append(semantic, attribute)
		default:
		}
	}
	if len(semantic) == 0 { return "" }
	sort.Slice(semantic, func(left, right int) bool { return semantic[left].name < semantic[right].name })
	var canonical strings.Builder
	for _, attribute := range semantic {
		canonical.WriteString(attribute.name); canonical.WriteByte(0); canonical.Write(attribute.data); canonical.WriteByte(0)
	}
	digest := sha256.Sum256([]byte(canonical.String()))
	return hex.EncodeToString(digest[:])
}

func javaClassKind(access uint16) string {
	if access&jvmAnnotation != 0 { return "annotation" }
	if access&jvmEnum != 0 { return "enum" }
	if access&jvmInterface != 0 { return "interface" }
	return "class"
}

func javaVisibility(access uint16) string {
	if access&jvmPublic != 0 { return "public" }
	if access&jvmProtected != 0 { return "protected" }
	return "package"
}

func javaSymbolKind(kind string) option.Option[JavaSymbolKind] {
	switch kind {
	case "class": return option.Some[JavaSymbolKind](JavaClass())
	case "interface": return option.Some[JavaSymbolKind](JavaInterface())
	case "annotation": return option.Some[JavaSymbolKind](JavaAnnotation())
	case "enum": return option.Some[JavaSymbolKind](JavaEnum())
	case "field": return option.Some[JavaSymbolKind](JavaField())
	case "constructor": return option.Some[JavaSymbolKind](JavaConstructor())
	case "method": return option.Some[JavaSymbolKind](JavaMethod())
	default: return option.None[JavaSymbolKind]
	}
}
