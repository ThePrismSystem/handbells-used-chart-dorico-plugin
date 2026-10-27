-- Build option-setting commands in the form Dorico logs for the Remote API's setoptions:
--   Project.Layout.SetOptions?Dictionary=list: {string: "path"}\, {string: "value"}&OpenScoreID=n&LayoutIDArray=n
--   Project.Flow.SetNotationOptions?Dictionary=list: ...&OpenScoreID=n&FlowIDArray=n
local layoutopts = {}

-- Commas separate the list's items, so a comma inside a value is escaped as "\," (as Dorico logs it).
local function quote(s)
  local escaped = tostring(s):gsub('"', '\\"'):gsub(",", "\\,")
  return '{string: "' .. escaped .. '"}'
end

-- values: {path = value, ...}; paths are sorted so the command is stable.
local function dictionary(values)
  local paths = {}
  for path in pairs(values) do paths[#paths + 1] = path end
  table.sort(paths)
  local items = {}
  for _, path in ipairs(paths) do
    items[#items + 1] = quote(path)
    items[#items + 1] = quote(values[path])
  end
  return "list: " .. table.concat(items, "\\, ")
end

function layoutopts.setCommand(openScoreID, layoutId, values)
  return "Project.Layout.SetOptions?Dictionary=" .. dictionary(values)
    .. "&OpenScoreID=" .. openScoreID .. "&LayoutIDArray=" .. layoutId
end

function layoutopts.flowNotationCommand(openScoreID, flowId, values)
  return "Project.Flow.SetNotationOptions?Dictionary=" .. dictionary(values)
    .. "&OpenScoreID=" .. openScoreID .. "&FlowIDArray=" .. flowId
end

return layoutopts
