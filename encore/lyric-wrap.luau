--!nonstrict
-- Word-timed lyric lines broken into rows that fit a width, for the overlay: labels wrap
-- themselves, but a karaoke line is one label per word, so its rows are broken here.
-- Pure, and plain Lua 5 so tests/pure.lua can run it without noctalia.

local M = {}

-- Average glyph width as a share of the font size. Slightly generous, so a row rather
-- breaks early than runs past the pill.
M.CHAR_WIDTH = 0.56

local function chars(text) return (utf8 and utf8.len(text)) or #text end

-- Rows of word indexes ({ {1, 2, 3}, {4, 5} }) that fit `width` px at font `size`.
-- yrc words can be syllables of one word, so syllables up to the next space form one
-- unit that moves to the next row whole; a unit longer than a row gets a row of its own.
function M.rows(words, size, width)
  local limit = math.max(8, math.floor(width / (size * M.CHAR_WIDTH)))
  local units, unit, len = {}, {}, 0
  for i, w in ipairs(words) do
    unit[#unit + 1] = i
    len = len + chars(w.text) + (w.space and 1 or 0)
    if w.space or i == #words then
      units[#units + 1] = { indexes = unit, len = len }
      unit, len = {}, 0
    end
  end
  local rows, row, used = {}, {}, 0
  for _, u in ipairs(units) do
    if #row > 0 and used + u.len > limit then
      rows[#rows + 1] = row
      row, used = {}, 0
    end
    for _, i in ipairs(u.indexes) do row[#row + 1] = i end
    used = used + u.len
  end
  if #row > 0 then rows[#rows + 1] = row end
  return rows
end

return M
