-- Reads the notes of a MusicXML export, which carries the noteheads and colours that Lua can't read from a score
-- whose noteheads were changed in Dorico (docs/dorico-lua-guide.md, section 2). Each note gets its sounding pitch,
-- its position in quarters from the start of the flow, its notehead and its colour, so it can be paired with the
-- notes Dorico's dumps list (hbuc.xmlnotes). The positions follow the dumps: a grace note sits at the onset of the
-- note it leads into, and a note tied over from an earlier one is not a note of its own.
--
-- Only what the export needs is understood. The DOCTYPE and any entity it declares are skipped, never fetched or
-- expanded: only the five predefined entities and numeric references are decoded.
local musicxml = {}

local STEP = { C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6 }
local SEMITONE = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
local NAMED = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }

local function utf8(code)
  if code < 0x80 then return string.char(code) end
  if code < 0x800 then return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40) end
  if code < 0x10000 then
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
  end
  return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
    0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local function decode(s)
  return (s:gsub("&(#?)([xX]?)(%w+);", function(hash, x, body)
    if hash == "" then return x == "" and NAMED[body] or nil end
    local code = tonumber(body, x == "" and 10 or 16)
    return code and code <= 0x10FFFF and utf8(code) or nil
  end))
end

-- A tree of {name, attrs, children, text}, or nil for anything that isn't well formed.
local function tree(text)
  local root = { name = "", attrs = {}, children = {}, text = {} }
  local stack = { root }
  local i, n = 1, #text
  while i <= n do
    local top = stack[#stack]
    local lt = text:find("<", i, true)
    if not lt then
      top.text[#top.text + 1] = text:sub(i)
      break
    end
    if lt > i then top.text[#top.text + 1] = text:sub(i, lt - 1) end
    if text:sub(lt, lt + 3) == "<!--" then
      local e = text:find("-->", lt + 4, true)
      if not e then return nil end
      i = e + 3
    elseif text:sub(lt, lt + 8) == "<![CDATA[" then
      local e = text:find("]]>", lt + 9, true)
      if not e then return nil end
      top.text[#top.text + 1] = text:sub(lt + 9, e - 1):gsub("&", "&amp;")
      i = e + 3
    elseif text:sub(lt, lt + 1) == "<?" then
      local e = text:find("?>", lt + 2, true)
      if not e then return nil end
      i = e + 2
    elseif text:sub(lt, lt + 1) == "<!" then
      -- a DOCTYPE, whose internal subset in [...] may hold ">"
      local close = text:find(">", lt, true)
      local open = text:find("[", lt, true)
      if open and close and open < close then
        local _, e = text:find("]%s*>", open)
        close = e
      end
      if not close then return nil end
      i = close + 1
    elseif text:sub(lt, lt + 1) == "</" then
      local name, after = text:match("^</([%w:_%.%-]+)%s*>()", lt)
      if not name or name ~= top.name or #stack == 1 then return nil end
      stack[#stack] = nil
      i = after
    else
      local name, j = text:match("^<([%w:_%.%-]+)()", lt)
      if not name then return nil end
      local el = { name = name, attrs = {}, children = {}, text = {} }
      local closed
      while true do
        j = text:match("^%s*()", j)
        if text:sub(j, j) == ">" then
          j = j + 1
          break
        elseif text:sub(j, j + 1) == "/>" then
          j, closed = j + 2, true
          break
        end
        local attr, quote, from = text:match("^([%w:_%.%-]+)%s*=%s*([\"'])()", j)
        if not attr then return nil end
        local to = text:find(quote, from, true)
        if not to then return nil end
        el.attrs[attr] = decode(text:sub(from, to - 1))
        j = to + 1
      end
      top.children[#top.children + 1] = el
      if not closed then stack[#stack + 1] = el end
      i = j
    end
  end
  if #stack ~= 1 then return nil end
  return root
end

local function child(el, name)
  for _, c in ipairs(el.children) do
    if c.name == name then return c end
  end
  return nil
end

local function textOf(el)
  if not el then return nil end
  return decode(table.concat(el.text)):match("^%s*(.-)%s*$")
end

local function numberOf(el, default)
  return tonumber(textOf(el) or "") or default
end

-- "#RRGGBB" or "#AARRGGBB" as Lua reads a colour ("#rrggbb"), else "".
local function colourOf(value)
  local hex = tostring(value or ""):match("^#(%x+)$")
  if hex and (#hex == 6 or #hex == 8) then return "#" .. hex:sub(-6):lower() end
  return ""
end

local function readPart(part)
  local notes = {}
  local divisions = 1
  local transpose = {}   -- by staff number, and [""] for every staff
  local start = 0
  for _, measure in ipairs(part.children) do
    if measure.name == "measure" then
      local cursor, longest, onset = start, start, start
      for _, el in ipairs(measure.children) do
        if el.name == "attributes" then
          divisions = numberOf(child(el, "divisions"), divisions)
          for _, tr in ipairs(el.children) do
            if tr.name == "transpose" then
              transpose[tr.attrs.number or ""] = { chromatic = numberOf(child(tr, "chromatic"), 0),
                diatonic = numberOf(child(tr, "diatonic"), 0), octaves = numberOf(child(tr, "octave-change"), 0) }
            end
          end
        elseif el.name == "note" then
          local grace, chord = child(el, "grace") ~= nil, child(el, "chord") ~= nil
          if not chord then onset = cursor end
          local pitch, tiedOver = child(el, "pitch"), false
          for _, c in ipairs(el.children) do
            if c.name == "tie" and c.attrs.type == "stop" then tiedOver = true end
          end
          if pitch and not child(el, "cue") and not tiedOver then
            local step, octave = textOf(child(pitch, "step")), numberOf(child(pitch, "octave"), nil)
            if STEP[step] and octave then
              local tr = transpose[textOf(child(el, "staff")) or "1"] or transpose[""]
                or { chromatic = 0, diatonic = 0, octaves = 0 }
              local head = child(el, "notehead")
              local colour = colourOf(el.attrs.color)
              if colour == "" and head then colour = colourOf(head.attrs.color) end
              notes[#notes + 1] = {
                pos = onset,
                pitch = (octave + 1) * 12 + SEMITONE[step] + numberOf(child(pitch, "alter"), 0) + tr.chromatic
                  + 12 * tr.octaves,
                diatonic = octave * 7 + STEP[step] + tr.diatonic + 7 * tr.octaves,
                grace = grace,
                head = textOf(head),
                filled = head and head.attrs.filled,
                colour = colour,
              }
            end
          end
          if not chord and not grace then cursor = cursor + numberOf(child(el, "duration"), 0) / divisions end
        elseif el.name == "backup" then
          cursor = cursor - numberOf(child(el, "duration"), 0) / divisions
        elseif el.name == "forward" then
          cursor = cursor + numberOf(child(el, "duration"), 0) / divisions
        end
        if cursor > longest then longest = cursor end
      end
      start = longest
    end
  end
  return notes
end

-- {parts = {{id, name, notes = {{pos, pitch, diatonic, grace, head, filled, colour}}}}}, or nil and why:
-- "compressed" (an .mxl), "notMusicXML" or "empty" (no parts).
function musicxml.parse(text)
  if type(text) ~= "string" then return nil, "notMusicXML" end
  if text:sub(1, 4) == "PK\3\4" then return nil, "compressed" end
  if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end
  local doc = tree(text)
  local root = doc and doc.children[1]
  if not root or root.name ~= "score-partwise" then return nil, "notMusicXML" end
  local names = {}
  local list = child(root, "part-list")
  if list then
    for _, sp in ipairs(list.children) do
      if sp.name == "score-part" and sp.attrs.id then names[sp.attrs.id] = textOf(child(sp, "part-name")) end
    end
  end
  local parts = {}
  for _, part in ipairs(root.children) do
    if part.name == "part" then
      parts[#parts + 1] = { id = part.attrs.id, name = names[part.attrs.id] or part.attrs.id or "",
        notes = readPart(part) }
    end
  end
  if #parts == 0 then return nil, "empty" end
  return { parts = parts }
end

return musicxml
