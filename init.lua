--mod-version:4

local core = require "core"
local DocView = require "core.docview"
local Doc = require "core.doc"
local command = require "core.command"
local View = require "core.view"
local syntax = require "core.syntax"
local style = require "core.style"
local Object = require "core.object"
local config = require "core.config"
local common = require "core.common"
local keymap = require "core.keymap"
local ime = require "core.ime"
local json = require "libraries.json"

local Jupyter = {}

local JupyterView = View:extend()

Jupyter.JupyterView = JupyterView

local Block = DocView:extend()
function Block:draw_scrollbar() return end
function Block:get_scrollable_size() return self.size.y end

config.plugins.jupyter = common.merge({
  debug = true,
  python = { "python3" },
  kernel_timeout = 5,
  matplotlib_inline = true,
  kernel_path = USERDIR .. PATHSEP .. "plugins" .. PATHSEP ..  "jupyter" .. PATHSEP .. "kernel.py"
}, config.plugins.jupyter)

function Block:get_height()
  return #self.doc.lines * self:get_line_height() + style.padding.y * 2
end

local OutputView = Block:extend()
local MarkdownBlock = Block:extend()

function OutputView:new()
  OutputView.super.new(self, Doc())
  self.read_only = true
end
function OutputView:draw_line_gutter() end

local CodeBlock = Block:extend()

function CodeBlock:new(text)
  CodeBlock.super.new(self, Doc())
  if text then
    self.doc:insert(1, 1, text)
  end
  self.run_order = nil
  self.doc:reset_syntax()
end

-- This should probably be changed to DocView.
local old_reset_syntax = Doc.reset_syntax
function Doc:reset_syntax(...)
  old_reset_syntax(self, ...)
  for i, listener in ipairs(self.listeners) do
    if listener:extends(CodeBlock) then
      self.syntax = syntax.get(".py")
      return
    elseif listener:extends(MarkdownBlock) then
      self.syntax = syntax.get(".md")
      return
    end
  end
end

function CodeBlock:draw()
  CodeBlock.super.draw(self)
end

-- function Block:get_virtual_line_offset(...)
--   local x, y = Block.super.get_virtual_line_offset(self, ...)
--   return x, y + style.padding.y
-- end


function CodeBlock:get_gutter_width() return style.code_font:get_width(string.format("[%s]", self.run_order or "")) + style.padding.x * 2 end
function CodeBlock:draw_line_gutter(vline) 
  if vline == 1 then
    common.draw_text(style.code_font, style.text, string.format("[%s]", self.run_order and self.run_order or ""), "left", self.position.x + style.padding.x, self.position.y + style.padding.y, 0, self:get_line_height())
  end
end

function CodeBlock:run()
  self.jupyter:run(self)
end

local base64 = {}

function base64.makeencoder( s62, s63, spad )
	local encoder = {}
	for b64code, char in pairs{[0]='A','B','C','D','E','F','G','H','I','J',
		'K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y',
		'Z','a','b','c','d','e','f','g','h','i','j','k','l','m','n',
		'o','p','q','r','s','t','u','v','w','x','y','z','0','1','2',
		'3','4','5','6','7','8','9',s62 or '+',s63 or'/',spad or'='} do
		encoder[b64code] = char:byte()
	end
	return encoder
end


local extract = load[[return function( v, from, width )
  return ( v >> from ) & ((1 << width) - 1)
end]]()

function base64.makedecoder( s62, s63, spad )
	local decoder = {}
	for b64code, charcode in pairs( base64.makeencoder( s62, s63, spad )) do
		decoder[charcode] = b64code
	end
	return decoder
end

local char, concat = string.char, table.concat
local DEFAULT_DECODER = base64.makedecoder()

function base64.decode( b64, decoder, usecaching )
	decoder = decoder or DEFAULT_DECODER
	local pattern = '[^%w%+%/%=]'
	if decoder then
		local s62, s63
		for charcode, b64code in pairs( decoder ) do
			if b64code == 62 then s62 = charcode
			elseif b64code == 63 then s63 = charcode
			end
		end
		pattern = ('[^%%w%%%s%%%s%%=]'):format( char(s62), char(s63) )
	end
	b64 = b64:gsub( pattern, '' )
	local cache = usecaching and {}
	local t, k = {}, 1
	local n = #b64
	local padding = b64:sub(-2) == '==' and 2 or b64:sub(-1) == '=' and 1 or 0
	for i = 1, padding > 0 and n-4 or n, 4 do
		local a, b, c, d = b64:byte( i, i+3 )
		local s
		if usecaching then
			local v0 = a*0x1000000 + b*0x10000 + c*0x100 + d
			s = cache[v0]
			if not s then
				local v = decoder[a]*0x40000 + decoder[b]*0x1000 + decoder[c]*0x40 + decoder[d]
				s = char( extract(v,16,8), extract(v,8,8), extract(v,0,8))
				cache[v0] = s
			end
		else
			local v = decoder[a]*0x40000 + decoder[b]*0x1000 + decoder[c]*0x40 + decoder[d]
			s = char( extract(v,16,8), extract(v,8,8), extract(v,0,8))
		end
		t[k] = s
		k = k + 1
	end
	if padding == 1 then
		local a, b, c = b64:byte( n-3, n-1 )
		local v = decoder[a]*0x40000 + decoder[b]*0x1000 + decoder[c]*0x40
		t[k] = char( extract(v,16,8), extract(v,8,8))
	elseif padding == 2 then
		local a, b = b64:byte( n-3, n-2 )
		local v = decoder[a]*0x40000 + decoder[b]*0x1000
		t[k] = char( extract(v,16,8))
	end
	return concat( t )
end


function MarkdownBlock:new(text)
  MarkdownBlock.super.new(self, Doc())
  if text then
    self.doc:insert(1, 1, text)
  end
  self.doc:reset_syntax()
end
function MarkdownBlock:get_gutter_width() return style.padding.x * 2 end
function MarkdownBlock:draw_line_gutter() end

local Figure = Object:extend()

function Figure:new(bytes, width, height)
  Figure.super.new(self)
  self.position = { x = 0, y = 0 }
  self.size = { x = width, y = height }
  self.bytes = bytes
  self.canvas = canvas.new(self.size.x, self.size.y)
  self.canvas:set_pixels(self.bytes, 0, 0, self.size.x, self.size.y)
end

function Figure:draw()
  renderer.draw_canvas(self.canvas, math.floor(self.position.x), math.floor(self.position.y))
end

function Figure:get_height()
  return self.size.y
end

function JupyterView:new()
  JupyterView.super.new(self)
  self.blocks = {}
  self.path = nil
  self.kernel = nil
  self.total_run = 0
  self.active_view = nil
  self.run_queue = {}
end

function JupyterView:run(block)
  if not block.output_block then
    block.output_blocks = { }
  end
  if not self.kernel then
    self:restart()
  end
  local frame = json.encode({ action = "execute", code = block.doc:get_text(1, 1, math.huge, math.huge) }) 
  if config.plugins.jupyter.debug then print(">", frame) end
  self.kernel.stdin:write(frame .. "\n")
  frame = self.kernel.stdout:read("*line")
  if config.plugins.jupyter.debug then print("<", frame) end
  frame = json.decode(frame)
  if frame.status == "ok" then
    local outputs = {}
    for _, output in ipairs(frame.outputs) do
      if output.type == "stream" and output.name == "stdout" then
        if #block.output_blocks == 0 or block.output_blocks[#block.output_blocks]:is(Figure) then
          table.insert(block.output_blocks, OutputView(Doc()))
          block.output_blocks[#block.output_blocks].doc:remove(1, 1, math.huge, math.huge)
        end
        block.output_blocks[#block.output_blocks].doc:insert(math.huge,math.huge, output.text)
      elseif output.type == "display_data" and output.data["image/raw"] then
        table.insert(block.output_blocks, Figure(base64.decode(output.data["image/raw"]), output.metadata["width"], output.metadata["height"]))
      elseif output.type == "result" and output.data["text/plain"] then
        if #block.output_blocks == 0 or block.output_blocks[#block.output_blocks]:is(Figure) then
          table.insert(block.output_blocks, OutputView(Doc()))
          block.output_blocks[#block.output_blocks].doc:remove(1, 1, math.huge, math.huge)
        end
        block.output_blocks[#block.output_blocks].doc:insert(math.huge,math.huge, output.data["text/plain"])
      end
    end
  elseif frame.status == "error" then
    local outputs = { frame.evalue .. "\n" }
    for _, output in ipairs(frame.outputs) do
      if output.type == "error" and output.traceback then
        for i, level in ipairs(output.traceback) do
          table.insert(outputs, level:gsub("%c%[.-m", "") .. "\n")
        end
      end
    end
    table.insert(block.output_blocks, OutputView(Doc()))
    block.output_blocks[#block.output_blocks].doc:insert(1, 1, table.concat(outputs, ""))
  end
  self.total_run = self.total_run + 1
  block.run_order = self.total_run
  core.redraw = true
end

function JupyterView:draw()
  JupyterView.super.draw(self)
  self:draw_background(style.background3)
  local x = self.position.x + style.padding.x
  local y = self.position.y + style.padding.y
  for i, block in ipairs(self.blocks) do
    block.position.x = x
    block.position.y = y
    block.size.x = self.size.x - style.padding.x * 2
    block.size.y = block:get_height()
    block:draw()
    y = y + block:get_height() + style.padding.y
    if block.output_blocks and #block.output_blocks > 0 then
      for _, output_block in ipairs(block.output_blocks) do
        output_block.position.x = x
        output_block.position.y = y
        if not output_block:is(Figure) then
          output_block.size.x = self.size.x - style.padding.x * 2
          output_block.size.y = output_block:get_height()
        end
        output_block:draw()
        y = y + output_block:get_height() + style.padding.y
      end
    end
  end
end

function JupyterView:get_name()
  return string.format("Jupyter Notebook - %s", self.path or "New File")
end

function JupyterView:add_block(block, index)
  if not index then index = #self.blocks + 1 end
  table.insert(self.blocks, index, block)
  block.jupyter = self
  core.redraw = true
  return block
end

function JupyterView:remove_block(block)
  for i, sblock in ipairs(self.blocks) do
    if block == sblock then
      table.remove(self.blocks, i)
      if self.active_view == block then
        self:set_active_view(nil)
      end
      return i
    end
  end
  core.redraw = true
end

function JupyterView:set_active_view(view)
  self.active_view = view
  local target = view or self
  if self.root_view.active_view ~= target then
    self.root_view:set_active_view(target)
  end
end

function JupyterView:update()
  JupyterView.super.update(self)
  for i,v in ipairs(self.blocks) do
    v:update()
  end
end

local function create_kernel()
  assert(system.get_file_info(config.plugins.jupyter.kernel_path), string.format("can't find kernel at %s for Jupyter. Please adjust config.plugins.jupyter.kernel_path.", config.plugins.jupyter.kernel_path))
  local t = common.merge(config.plugins.jupyter.python, {})
  table.insert(t, config.plugins.jupyter.kernel_path)
  return process.start(t)
end

function JupyterView:restart()
  local path = USERDIR .. PATHSEP .. "plugins" .. PATHSEP .. "jupyter" .. PATHSEP .. "kernel.py"
  if self.kernel then
    core.log("Shutting down Jupyter kernel...")
    self.kernel.stdin:write(json.encode({ action = "shutdown" }) .. "\n")
    if self.kernel:wait() == 0 then
      core.log("Jupyter kernel successfully shutdown.")
    else
      core.log("Jupyter kernel unable to shutdown successfully.")
    end
  end
  self.kernel = create_kernel()
  if config.plugins.jupyter.matplotlib_inline then
    local frame = json.encode({ action = "execute", code = [[
import matplotlib
from IPython import get_ipython
ip = get_ipython()
ip.run_line_magic('matplotlib', 'inline')
]] })
    if config.plugins.debug then
      print(">", frame)
    end
    self.kernel.stdin:write(frame .. "\n")
    local output = self.kernel.stdout:read("*line")
    if config.plugins.debug then
      print("<", output:gsub("%c%[.-m", ""):gsub("\\n", "\n"))
    end
  end
  self.total_run = 0
  core.log("Jupyter kernel started.")
end

function JupyterView:run_all()
  for _, block in ipairs(self.blocks) do
    if block.run then
      block:run()
    end
  end
end

function JupyterView:clear()
  for _, block in ipairs(self.blocks) do
    block.output_blocks = {}
    block.run_order = nil
  end
end

function JupyterView:step_queue()
  while #self.run_queue > 0 do
    core.try(self.run_queue[1])
    table.remove(self.run_queue, 1)
  end
end

function JupyterView:queue(func)
  table.insert(self.run_queue, func)
  if #self.run_queue == 1 then
    core.add_thread(function()
      self:step_queue()
    end)
  end
end

function JupyterView:on_mouse_pressed(button, x, y, clicks)
  if button == "left" then
    self.holding_left = true
  end
  if self.hovering_block then
    self:set_active_view(self.hovering_block)
    return self.hovering_block:on_mouse_pressed(button, x, y, clicks)
  end
end


function JupyterView:on_mouse_released(button, ...)
  if button == "left" then
    self.holding_left = false
  end
  if self.hovering_block then
    return self.hovering_block:on_mouse_released(button, ...)
  end
  return JupyterView.super.on_mouse_released(self, button, ...)
end

function JupyterView:get_block_overlapping_point(x, y)
  for _, block in ipairs(self.blocks) do
    if x >= block.position.x and x < block.position.x + block.size.x and y >= block.position.y and y < block.position.y + block.size.y then
      return block
    end
  end  
end

function JupyterView:on_mouse_moved(x, y)
  if not self.holding_left then
    self.hovering_block = self:get_block_overlapping_point(x, y)
  end
  if self.hovering_block then
    return self.hovering_block:on_mouse_moved(x, y)
  end
  return JupyterView.super.on_mouse_moved(self, x, y)
end

function JupyterView:on_mouse_wheel(x, y)
  return 
end

local function pred(view)
  if view == JupyterView then
    return function(rv, options)
      local jupyter_view = rv.active_view:is(JupyterView) and rv.active_view or rv.active_view.jupyter
      return jupyter_view, jupyter_view, options
    end
  end
  return view
end


core.add_thread(function()
  core.try(function()
    -- check to see if we have python
    local t = common.merge(config.plugins.jupyter.python, {})
    table.insert(t, "--version")
    local test, err = process.start(t)
    local status = test:wait(config.plugins.jupyter.kernel_timeout)
    if status ~= 0 then
      core.error("Jupyter: You don't seem to have python installed at %s (exit: %s), please install python or configure config.plugins.jupyter.python: %s", config.plugins.jupyter.python[1], status or "timeout", test.stderr:read("*all") or "unknown error")
      return
    end
    -- check to see if we can boot a python kernel, and it has ipykernel installed
    local kernel = create_kernel()
    kernel.stdin:write(json.encode({ action = "shutdown" }) .. "\n")
    local status, err = pcall(function()
      local frame = kernel.stdout:read("*line", { timeout = config.plugins.jupyter.kernel_timeout })
      local status = kernel:wait()
      assert(status == 0, string.format("Jupyter: Unable to start an IPython kernel and matplotlib (exit: %s): %s. Please ensure you have ipykernel installed (pip install ipykernel matplotlib).", status or "timeout", test.stderr:read("*all") or "unknown error"))
    end)
    if not status then
      core.error("%s", err)
      return
    end

    core.log_quiet("Jupyter kernel successfully initialized.")
    Jupyter.initialized = true
    
    command.add(nil, {
      ["jupyter:new-notebook"] = function(rv)
        local node = rv:get_active_node_default()
        node:add_view(JupyterView())
      end
    })

    command.add(pred(JupyterView), {
      ["jupyter:add-code-block"] = function(jv, options)
        local block = jv:add_block(CodeBlock(options.text))
        jv:set_active_view(block)
        core.redraw = true
      end,
      ["jupyter:add-markdown-block"] = function(jv, options)
        local block = jv:add_block(MarkdownBlock(options.text))
        jv:set_active_view(block)
        core.redraw = true
      end,
      ["jupyter:restart"] = function(jv)
        jv:queue(function() jv:restart() end)
      end,
      ["jupyter:run-all"] = function(jv)
        jv:queue(function() jv:run_all() end)
      end,
      ["jupyter:clear-all-outputs"] = function(jv)
        jv:clear()
      end
    })

    command.add(MarkdownBlock, {
      ["jupyter:switch-to-code-block"] = function(block)
        block.jupyter:add_block(
          CodeBlock(block.doc:get_text(1, 1, math.huge, math.huge)),
          block.jupyter:remove_block(block)
        )
      end
    })
    command.add(CodeBlock, {
      ["jupyter:switch-to-markdown-block"] = function(block)
        block.jupyter:add_block(
          MarkdownBlock(block.doc:get_text(1, 1, math.huge, math.huge)),
          block.jupyter:remove_block(block)
        )
      end,
      ["jupyter:run-block"] = function(block)
        block.jupyter:queue(function() block:run() end)
      end
    })

    command.add(Block, {
      ["jupyter:deselect"] = function(block)
        block.jupyter:set_active_view(nil)
      end,
      ["jupyter:remove-block"] = function(block)
        block.jupyter:remove_block(block)
      end
    })
  end)

  keymap.add {
    ['escape'] = "jupyter:deselect",
    ['f8'] = "jupyter:run-block"
  }

  command.perform("jupyter:new-notebook")
  command.perform("jupyter:add-markdown-block", core.root_view, { text = "# Heading 1\nTest Markdown\nTest Line 2\nTest Line 3" })
  command.perform("jupyter:add-code-block", core.root_view, { text = "import pandas as pd\nimport matplotlib.pyplot as plt\nplt.figure()\nplt.plot([1, 2], [3, 4])\nplt.show()" })
  command.perform("jupyter:run-all")
end)

return Jupyter
