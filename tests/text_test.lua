-- Every string this mod puts in a text box has to be readable.
--
--   cd /path/to/gen1recomp
--   GEN151=/path/to/Gen151 luajit "$GEN151/tests/text_test.lua"
--
-- The bug this exists to stop:
--
-- TextBox shows TWO lines.  A page break (\f) waits for a button.  A line
-- break (\n) does not -- and neither does the scroll that a THIRD line on a
-- page forces.  src/render/TextBox.lua only waits between lines when the
-- break was \v (pokered's <CONT>, TextCommand_PROMPT_BUTTON); a plain \n runs
-- _ContTextNoPause, which scrolls the top line away and keeps typing.
--
-- So a three-line page shows its first line for as long as it takes to type
-- the second, then scrolls it off the top forever.  The player sees text move
-- and settle on something they were not reading.  That is not a style
-- preference, it is text the game destroys before it can be read, and the mod
-- did it in a dozen places.
--
-- Soft wrapping counts too: an 18-column box turns one long line into two, so
-- "two \n-separated lines" can still render as three.  The check therefore
-- runs the real TextBox.paginate rather than counting \n.

local GEN151 = os.getenv("GEN151") or "../Gen151"

if not package.path:find("./?/init.lua", 1, true) then
  package.path = "./?.lua;./?/init.lua;" .. package.path
end

local T = require("tests.modkit")
local check = T.check
local TextBox = require("src.render.TextBox")

-- The files that ship.  bench.lua is in here too: the bench is part of the
-- mod now, and its boxes are read by a human under exactly the same rules.
local FILES = {
  "main.lua", "linkcable.lua", "mewgate.lua", "hints.lua", "bench.lua",
}

-- Every "..." and '...' literal in a chunk, with escapes decoded.  Long
-- brackets are skipped on purpose: the mod uses them for comments only, and a
-- comment is not a text box.
local ESCAPES = { n = "\n", f = "\f", v = "\v", t = "\t", r = "\r",
                  ["\\"] = "\\", ['"'] = '"', ["'"] = "'" }

local function literals(source)
  local out = {}
  local i, n = 1, #source
  while i <= n do
    local c = source:sub(i, i)
    if c == "-" and source:sub(i + 1, i + 1) == "-" then
      -- a comment runs to end of line; long comments are not scanned
      local nl = source:find("\n", i, true)
      i = nl and nl + 1 or n + 1
    elseif c == '"' or c == "'" then
      local quote, buf, j = c, {}, i + 1
      while j <= n do
        local ch = source:sub(j, j)
        if ch == "\\" then
          local esc = source:sub(j + 1, j + 1)
          buf[#buf + 1] = ESCAPES[esc] or esc
          j = j + 2
        elseif ch == quote then
          break
        elseif ch == "\n" then
          break -- unterminated: not a literal we can trust, bail out
        else
          buf[#buf + 1] = ch
          j = j + 1
        end
      end
      out[#out + 1] = { text = table.concat(buf),
                        line = select(2, source:sub(1, i):gsub("\n", "")) + 1 }
      i = j + 1
    else
      i = i + 1
    end
  end
  return out
end

local MAX_LINES = 2
local MAX_COLS = 18

-- The one string that is allowed to run long, because it is not ours: it is
-- copied verbatim out of src/pokemon/Evolution.lua so that a LINK CABLE
-- evolution reads exactly like the level-up evolution the player has seen a
-- dozen times, third line and all.  Fixing it here would make this mod's
-- evolutions the odd ones out, and the box the engine prints is the one to
-- match.
local ENGINE_TEXT = {
  ["What?\n%s is\nevolving!"] = "src/pokemon/Evolution.lua:167",
}

local failures = 0
local scanned = 0

for _, name in ipairs(FILES) do
  local handle = assert(io.open(GEN151 .. "/" .. name, "r"),
    name .. " is missing")
  local source = handle:read("*a")
  handle:close()

  for _, literal in ipairs(literals(source)) do
    local text = literal.text
    -- Only strings that are actually box text: they carry a line or page
    -- break.  A one-line string cannot scroll anything away.
    if text:find("[\n\f]") and not ENGINE_TEXT[text] then
      scanned = scanned + 1
      -- %s and %d stand in for names and numbers at runtime.  Substituting
      -- something plausibly long keeps the check honest about wrapping:
      -- "MEW" fits where "NIDORAN%f" would not.
      local filled = text:gsub("%%%-?%d*d", "88"):gsub("%%s", "NIDORINO")
      local pages = TextBox.paginate(filled, MAX_COLS)
      for index, page in ipairs(pages) do
        local conts = pages.contBefore and pages.contBefore[index] or {}
        -- A line preceded by \v waits for a button, so it does not count
        -- against the two the box can hold: the player has read the pair
        -- above it before it scrolls.
        local unwaited = 0
        local worst = 0
        for lineIndex = 1, #page do
          if conts[lineIndex] then
            unwaited = 1
          else
            unwaited = unwaited + 1
          end
          worst = math.max(worst, unwaited)
        end
        if not check(worst <= MAX_LINES,
          ("%s:%d page %d renders %d lines with no wait -- the top one "
            .. "scrolls away unread: %q"):format(
            name, literal.line, index, worst, filled)) then
          failures = failures + 1
        end
      end
    end
  end
end

check(scanned > 0, "text: it found box strings to check at all")

io.write(("\ntext_test: %d strings scanned, %d unreadable pages\n")
  :format(scanned, failures))

T.finish("gen151 text")
