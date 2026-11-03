extends RefCounted

func run(ctx: TestContext) -> void:
	ctx.eq("13 -> bin", BitMath.to_base(13, 2), "1101")
	ctx.eq("45 -> bin", BitMath.to_base(45, 2), "101101")
	ctx.eq("255 pad 8", BitMath.to_base(255, 2, 8), "11111111")
	ctx.eq("0 pad 8", BitMath.to_base(0, 2, 8), "00000000")
	ctx.eq("1234 -> hex", BitMath.to_base(1234, 16), "4d2")
	ctx.eq("35 -> base36", BitMath.to_base(35, 36), "z")
	ctx.eq("negative rejected", BitMath.to_base(-3, 2), "")
	ctx.eq("bad base rejected", BitMath.to_base(3, 1), "")

	var r := BitMath.from_base("1101", 2)
	ctx.check("parse 1101", bool(r["ok"]))
	ctx.eq("parse 1101 value", int(r["value"]), 13)
	ctx.eq("parse hex 4d2", int(BitMath.from_base("4d2", 16)["value"]), 1234)
	ctx.eq("parse base36 zz", int(BitMath.from_base("zz", 36)["value"]), 1295)
	ctx.check("parse empty fails", not bool(BitMath.from_base("   ", 2)["ok"]))
	var bad := BitMath.from_base("102", 2)
	ctx.check("binary rejects 2", not bool(bad["ok"]))
	ctx.check("error mentions char", str(bad["error"]).contains("2"))

	ctx.eq("binary pad", BitMath.binary(13, 8), "00001101")
	ctx.eq("binary overflow empty", BitMath.binary(300, 8), "")
	ctx.eq("binary max", BitMath.max_value(8), 255)
	ctx.eq("from_binary 255", int(BitMath.from_binary("11111111", 8)["value"]), 255)
	ctx.check("from_binary overflow", not bool(BitMath.from_binary("100000000", 8)["ok"]))

	var bits := BitMath.bits_of(13, 8)
	ctx.eq("bits_of len", bits.size(), 8)
	ctx.eq("bits_of value", BitMath.value_of_bits(bits), 13)
	ctx.eq("bits_of msb", int(bits[0]), 0)
	ctx.eq("bits_of lsb", int(bits[7]), 1)

	ctx.eq("grouped", BitMath.grouped("11110000"), "1111 0000")
	ctx.eq("grouped odd", BitMath.grouped("10101", 4), "1 0101")

	var all_ok := true
	for v in range(0, 1024):
		var enc := BitMath.binary(v, 10)
		var dec := BitMath.from_binary(enc, 10)
		if not bool(dec["ok"]) or int(dec["value"]) != v:
			all_ok = false
			break
	ctx.check("roundtrip 0..1023", all_ok)
