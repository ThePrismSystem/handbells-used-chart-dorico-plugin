local json = require("hbuc.json")

return {
  encodes_arrays_objects_and_escapes = function(t)
    t:eq(json.encode({ 1, 2, 3 }), "[1,2,3]")
    t:eq(json.encode({ a = "x" }), '{"a":"x"}')
    t:eq(json.encode('q"\n'), '"q\\"\\n"')
    t:eq(json.encode({}), "{}")
    t:eq(json.encode({ b = 1, a = 2 }), '{"a":2,"b":1}', "keys sorted")
    t:eq(json.encode(1.5), "1.5")
  end,
  decodes_values = function(t)
    local d = json.decode('{"a":[1,true,null,"\\u00e9"]}')
    t:eq(d.a[1], 1)
    t:eq(d.a[2], true)
    t:eq(d.a[3], json.null)
    t:eq(d.a[4], "\195\169")
  end,
  round_trips = function(t)
    local back = json.decode(json.encode({ runId = "r1", nested = { x = 1.5 } }))
    t:eq(back.runId, "r1")
    t:eq(back.nested.x, 1.5)
  end,
  malformed_input_raises = function(t)
    t:fails(function() json.decode("{bad") end)
  end,
  malformed_numbers_raise = function(t)
    t:fails(function() json.decode("[1e]") end, "1e")
    t:fails(function() json.decode("[1-]") end, "1-")
  end,
  full_precision = function(t)
    t:eq(json.decode(json.encode(0.1 + 0.2)), 0.1 + 0.2)
  end,
  large_integers_on_windows = function(t)
    t:eq(json.encode(2 ^ 40), "1099511627776", "2^40 encodes without a C long")
    t:eq(json.encode(-2 ^ 31), "-2147483648")
    t:eq(json.encode(2 ^ 31), "2147483648")
  end,
  bad_keys_raise = function(t)
    t:fails(function() json.encode({ [true] = 1 }) end)
  end,
}
