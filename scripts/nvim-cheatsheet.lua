-- Print every Neovim key mapping that has a description, as JSON.
--
-- Usage: nvim --headless -i NONE -c "luafile nvim-cheatsheet.lua" -c qa
--
-- Run by the Raycast script that scripts/nvim-cheatsheet.py formats. LazyVim
-- sets its own keymaps on VeryLazy, which a headless nvim never fires, and its
-- LSP keys only on LspAttach, so those are read from the lspconfig spec.

vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })

local function notation(keys)
  return vim.fn.keytrans(vim.api.nvim_replace_termcodes(keys, true, true, true))
end

local out = {}
local function add(mode, lhs, desc, server)
  if desc and desc ~= "" then
    table.insert(out, { mode = mode, lhs = lhs, desc = desc, server = server })
  end
end

for _, mode in ipairs({ "n", "x", "o", "i", "t" }) do
  for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
    add(mode, vim.fn.keytrans(map.lhsraw), map.desc)
  end
end

local ok, servers = pcall(function()
  return LazyVim.opts("nvim-lspconfig").servers
end)
if ok then
  local Keys = require("lazy.core.handler.keys")
  for name, server in pairs(servers) do
    if type(server) == "table" and server.keys then
      for _, key in pairs(Keys.resolve(server.keys)) do
        local modes = type(key.mode) == "table" and key.mode or { key.mode or "n" }
        for _, mode in ipairs(modes) do
          add(mode, notation(key.lhs), key.desc, name ~= "*" and name or nil)
        end
      end
    end
  end
end

io.stdout:write(vim.json.encode(out))
