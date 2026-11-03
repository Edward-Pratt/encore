--!nonstrict
-- Where the lyrics overlay sits, from the overlay_position setting: one of the seven
-- spots "top-left", "top", "top-right", "center", "bottom-left", "bottom", "bottom-right"
-- ("top" and "bottom" are centred). Shared by service-overlay.luau (layer anchors and
-- margins) and overlay.luau (where the pill sits inside the layer).

local M = {}

-- { v = "top" | "center" | "bottom", h = "left" | "center" | "right" }
function M.of(value)
  value = type(value) == "string" and value or "bottom"
  if value == "center" then return { v = "center", h = "center" } end
  local v, h = string.match(value, "^(%a+)%-(%a+)$")
  if not v then v, h = value, "center" end
  if v ~= "top" then v = "bottom" end
  if h ~= "left" and h ~= "right" then h = "center" end
  return { v = v, h = h }
end

-- Flex alignment for a side: "start" | "center" | "end".
function M.flex(side)
  if side == "top" or side == "left" then return "start" end
  if side == "bottom" or side == "right" then return "end" end
  return "center"
end

return M
